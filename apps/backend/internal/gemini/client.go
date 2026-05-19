package gemini

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"

	"google.golang.org/genai"
)

func jsonUnmarshal(b []byte, v any) error { return json.Unmarshal(b, v) }

// Model identifiers — locked in the grill. Never swap to Seedream/Flux.
const (
	ModelNanoBananaPro = "gemini-3-pro-image-preview"
	ModelNanoBanana2   = "gemini-3.1-flash-image-preview"
)

// Client wraps google.golang.org/genai with the narrow methods we need.
type Client struct {
	c *genai.Client
}

// New creates a Gemini client. Needs GEMINI_API_KEY via env (picked up by the SDK).
func New(ctx context.Context, apiKey string) (*Client, error) {
	if apiKey == "" {
		return nil, errors.New("gemini: missing api key")
	}
	c, err := genai.NewClient(ctx, &genai.ClientConfig{APIKey: apiKey})
	if err != nil {
		return nil, fmt.Errorf("gemini new client: %w", err)
	}
	return &Client{c: c}, nil
}

// ReferenceImage is one input image to the compositing prompt.
type ReferenceImage struct {
	MIMEType string // "image/png", "image/jpeg"
	Data     []byte
}

// ComposeOutfit generates an outfit try-on composite image.
//
// Given a body reference photo and 1–5 garment reference images, Gemini renders
// the person wearing the garments. Returns the generated PNG bytes.
//
// Per the writeup, body photo bytes are held in memory only and dropped after
// this call returns — never persisted server-side.
func (c *Client) ComposeOutfit(
	ctx context.Context,
	body ReferenceImage,
	garments []ReferenceImage,
	occasion string,
) ([]byte, error) {
	if len(garments) == 0 {
		return nil, errors.New("gemini: need at least one garment")
	}
	if len(garments) > 13 {
		return nil, errors.New("gemini: at most 13 garment references (14 inputs total)")
	}

	prompt := buildPrompt(occasion, len(garments))

	parts := []*genai.Part{genai.NewPartFromText(prompt)}
	parts = append(parts, &genai.Part{InlineData: &genai.Blob{
		MIMEType: body.MIMEType, Data: body.Data,
	}})
	for _, g := range garments {
		parts = append(parts, &genai.Part{InlineData: &genai.Blob{
			MIMEType: g.MIMEType, Data: g.Data,
		}})
	}
	contents := []*genai.Content{genai.NewContentFromParts(parts, genai.RoleUser)}

	resp, err := c.c.Models.GenerateContent(ctx, ModelNanoBananaPro, contents, nil)
	if err != nil {
		return nil, fmt.Errorf("gemini generate: %w", err)
	}
	return extractImage(resp)
}

// buildPrompt returns the system-level direction for outfit compositing.
// Kept deliberately short — Nano Banana Pro handles multi-ref identity fidelity
// well without heavy steering.
func buildPrompt(occasion string, garmentCount int) string {
	var buf bytes.Buffer
	buf.WriteString("You are a professional fashion photographer. ")
	buf.WriteString(fmt.Sprintf(
		"Generate a single photorealistic studio image of the person in reference image 1 wearing the %d garments shown in the remaining reference images. ",
		garmentCount,
	))
	buf.WriteString("Preserve the person's face, body proportions, skin tone, and hair exactly. ")
	buf.WriteString("Match each garment's color, pattern, texture, and fit precisely. ")
	if occasion != "" {
		buf.WriteString(fmt.Sprintf("Setting: %s. ", occasion))
	}
	buf.WriteString("Clean studio lighting, subtle shadow, neutral backdrop. Full-body shot, camera at eye level. No logos added. No text overlay.")
	return buf.String()
}

func extractImage(resp *genai.GenerateContentResponse) ([]byte, error) {
	if resp == nil || len(resp.Candidates) == 0 {
		return nil, errors.New("gemini: no candidates")
	}
	parts := resp.Candidates[0].Content.Parts
	for _, p := range parts {
		if p.InlineData != nil && len(p.InlineData.Data) > 0 {
			return p.InlineData.Data, nil
		}
	}
	return nil, errors.New("gemini: response had no image part")
}

// GarmentAnalysis is the structured output we ask Gemini to return for a
// single garment photo. All fields are best-effort; the user can edit later.
type GarmentAnalysis struct {
	Name         string   `json:"name"`
	Brand        string   `json:"brand"`
	Category     string   `json:"category"` // matches GarmentCategory enum on the iOS side
	ColorPrimary string   `json:"color_primary"`
	Tags         []string `json:"tags"`
}

// AnalyzeGarment asks Gemini Flash (vision) to classify a garment photo and
// return structured fields so we can pre-fill the wardrobe form. The user
// can correct anything wrong from the detail view later.
func (c *Client) AnalyzeGarment(ctx context.Context, img ReferenceImage) (*GarmentAnalysis, error) {
	const prompt = `Look at this single garment photo and return a JSON object describing it.

Schema:
{
  "name":          string — short, neutral product name (e.g., "Blue Oxford Shirt", "Black Denim Jacket"). Max 40 chars.
  "brand":         string — visible brand on the garment, or "" if unknown. Never guess. Max 30 chars.
  "category":      one of "top", "bottom", "outer", "dress", "shoes", "accessory", "bag"
  "color_primary": dominant color word, lowercased (e.g., "blue", "off-white", "olive")
  "tags":          array of 1-4 short tags about style/fit (e.g., "casual", "long-sleeve", "linen")
}

Return ONLY the JSON object, no prose.`

	parts := []*genai.Part{
		genai.NewPartFromText(prompt),
		{InlineData: &genai.Blob{MIMEType: img.MIMEType, Data: img.Data}},
	}
	contents := []*genai.Content{genai.NewContentFromParts(parts, genai.RoleUser)}

	cfg := &genai.GenerateContentConfig{
		ResponseMIMEType: "application/json",
	}
	resp, err := c.c.Models.GenerateContent(ctx, "gemini-2.5-flash", contents, cfg)
	if err != nil {
		return nil, fmt.Errorf("gemini analyze: %w", err)
	}
	text := extractText(resp)
	if text == "" {
		return nil, errors.New("gemini: empty analysis response")
	}
	out := &GarmentAnalysis{}
	if err := jsonUnmarshal([]byte(text), out); err != nil {
		return nil, fmt.Errorf("gemini analysis parse: %w (raw: %s)", err, text)
	}
	return out, nil
}

func extractText(resp *genai.GenerateContentResponse) string {
	if resp == nil || len(resp.Candidates) == 0 {
		return ""
	}
	var b bytes.Buffer
	for _, p := range resp.Candidates[0].Content.Parts {
		if p.Text != "" {
			b.WriteString(p.Text)
		}
	}
	return b.String()
}

// FetchGarment downloads a garment PNG from object storage and wraps it.
func FetchGarment(ctx context.Context, r io.Reader, mime string) (ReferenceImage, error) {
	data, err := io.ReadAll(r)
	if err != nil {
		return ReferenceImage{}, err
	}
	return ReferenceImage{MIMEType: mime, Data: data}, nil
}
