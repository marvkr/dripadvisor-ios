package gemini

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// Stylist talks to Gemini 3 Pro via the OpenAI-compatible endpoint
// (locked decision in README). Function calling routes wardrobe lookups
// back to a host-supplied callback so the model can plan outfits from the
// user's actual closet.

const (
	openAICompatBase = "https://generativelanguage.googleapis.com/v1beta/openai"
	stylistModel     = "gemini-3-pro"
)

// Stylist is a thin OpenAI-protocol HTTP client.
type Stylist struct {
	apiKey string
	http   *http.Client
}

func NewStylist(apiKey string) *Stylist {
	return &Stylist{
		apiKey: apiKey,
		http:   &http.Client{Timeout: 60 * time.Second},
	}
}

// ChatMessage mirrors OpenAI's chat schema.
type ChatMessage struct {
	Role       string     `json:"role"`              // 'system' | 'user' | 'assistant' | 'tool'
	Content    string     `json:"content,omitempty"`
	Name       string     `json:"name,omitempty"`
	ToolCalls  []ToolCall `json:"tool_calls,omitempty"`
	ToolCallID string     `json:"tool_call_id,omitempty"`
}

type ToolCall struct {
	ID       string       `json:"id"`
	Type     string       `json:"type"` // 'function'
	Function FunctionCall `json:"function"`
}

type FunctionCall struct {
	Name      string `json:"name"`
	Arguments string `json:"arguments"` // raw JSON string per OpenAI spec
}

// WardrobeQuery is the structured args the model emits for lookup_wardrobe.
type WardrobeQuery struct {
	Category *string `json:"category,omitempty"` // top|bottom|dress|shoes|outerwear|accessory
	Color    *string `json:"color,omitempty"`
	Source   *string `json:"source,omitempty"` // owned|wishlist
	Limit    *int    `json:"limit,omitempty"`
}

// WardrobeLookup is implemented by the worker — backend-side fan-out into
// the wardrobe_items table for the user the chat belongs to.
type WardrobeLookup func(ctx context.Context, query WardrobeQuery) ([]map[string]any, error)

// Reply runs a single multi-turn loop: send history, handle tool calls,
// return the final assistant text. Caps at 3 tool-call rounds to bound cost.
func (s *Stylist) Reply(
	ctx context.Context,
	systemPrompt string,
	history []ChatMessage,
	lookup WardrobeLookup,
) (string, error) {
	msgs := make([]ChatMessage, 0, len(history)+1)
	msgs = append(msgs, ChatMessage{Role: "system", Content: systemPrompt})
	msgs = append(msgs, history...)

	const maxRounds = 3
	for round := 0; round < maxRounds; round++ {
		resp, err := s.completion(ctx, msgs)
		if err != nil {
			return "", err
		}
		choice := resp.Choices[0]
		msgs = append(msgs, choice.Message)
		if len(choice.Message.ToolCalls) == 0 {
			return strings.TrimSpace(choice.Message.Content), nil
		}
		for _, tc := range choice.Message.ToolCalls {
			result, err := s.dispatchTool(ctx, tc, lookup)
			if err != nil {
				result = `{"error":"` + err.Error() + `"}`
			}
			msgs = append(msgs, ChatMessage{
				Role:       "tool",
				Name:       tc.Function.Name,
				Content:    result,
				ToolCallID: tc.ID,
			})
		}
	}
	return "", errors.New("stylist: tool-call loop exceeded")
}

func (s *Stylist) dispatchTool(ctx context.Context, tc ToolCall, lookup WardrobeLookup) (string, error) {
	switch tc.Function.Name {
	case "lookup_wardrobe":
		var q WardrobeQuery
		if err := json.Unmarshal([]byte(tc.Function.Arguments), &q); err != nil {
			return "", fmt.Errorf("bad lookup_wardrobe args: %w", err)
		}
		items, err := lookup(ctx, q)
		if err != nil {
			return "", err
		}
		out, _ := json.Marshal(map[string]any{"items": items})
		return string(out), nil
	default:
		return "", fmt.Errorf("unknown tool %q", tc.Function.Name)
	}
}

// completion sends one POST /chat/completions w/ the lookup_wardrobe tool.
func (s *Stylist) completion(ctx context.Context, messages []ChatMessage) (*completionResp, error) {
	body, _ := json.Marshal(map[string]any{
		"model":    stylistModel,
		"messages": messages,
		"tools":    []any{wardrobeToolSpec()},
		"temperature": 0.7,
	})
	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		openAICompatBase+"/chat/completions", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+s.apiKey)
	resp, err := s.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer func() { _ = resp.Body.Close() }()
	raw, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 400 {
		return nil, fmt.Errorf("gemini openai-compat %d: %s", resp.StatusCode, string(raw))
	}
	var out completionResp
	if err := json.Unmarshal(raw, &out); err != nil {
		return nil, err
	}
	if len(out.Choices) == 0 {
		return nil, errors.New("no choices")
	}
	return &out, nil
}

type completionResp struct {
	Choices []struct {
		Message ChatMessage `json:"message"`
	} `json:"choices"`
}

func wardrobeToolSpec() map[string]any {
	return map[string]any{
		"type": "function",
		"function": map[string]any{
			"name":        "lookup_wardrobe",
			"description": "Search the user's wardrobe by category/color/source. Returns up to 'limit' matching items as JSON.",
			"parameters": map[string]any{
				"type": "object",
				"properties": map[string]any{
					"category": map[string]any{
						"type":        "string",
						"enum":        []string{"top", "bottom", "dress", "shoes", "outerwear", "accessory"},
						"description": "Garment category",
					},
					"color":  map[string]any{"type": "string", "description": "Hex color (e.g. '#1A1A1A') or freeform color name"},
					"source": map[string]any{"type": "string", "enum": []string{"owned", "wishlist"}, "description": "Restrict to closet vs wishlist"},
					"limit":  map[string]any{"type": "integer", "minimum": 1, "maximum": 50, "default": 10},
				},
			},
		},
	}
}
