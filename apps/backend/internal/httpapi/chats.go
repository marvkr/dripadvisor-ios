package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/riverqueue/river"

	"github.com/dripadvisor/backend/internal/auth"
	"github.com/dripadvisor/backend/internal/db"
	"github.com/dripadvisor/backend/internal/workers"
)

// v1.1 Chat endpoints. REST + DB only — realtime (WebSocket + Redis pub/sub)
// is PR2.

// ─── DTOs ───────────────────────────────────────────────────────────────────

type chatDTO struct {
	ID                 uuid.UUID  `json:"id"`
	Type               string     `json:"type"`
	Name               *string    `json:"name,omitempty"`
	IconURL            *string    `json:"icon_url,omitempty"`
	CreatedBy          *uuid.UUID `json:"created_by,omitempty"`
	LastMessageAt      *time.Time `json:"last_message_at,omitempty"`
	LastMessagePreview *string    `json:"last_message_preview,omitempty"`
	CreatedAt          time.Time  `json:"created_at"`
	UpdatedAt          time.Time  `json:"updated_at"`
}

func toChatDTO(c db.Chat) chatDTO {
	return chatDTO{
		ID: c.ID, Type: c.Type, Name: c.Name, IconURL: c.IconURL,
		CreatedBy: c.CreatedBy, LastMessageAt: c.LastMessageAt,
		LastMessagePreview: c.LastMessagePreview,
		CreatedAt:          c.CreatedAt, UpdatedAt: c.UpdatedAt,
	}
}

type participantDTO struct {
	UserID               *uuid.UUID `json:"user_id,omitempty"`
	AgentID              *uuid.UUID `json:"agent_id,omitempty"`
	Role                 string     `json:"role"`
	JoinedAt             time.Time  `json:"joined_at"`
	LastReadSeq          int64      `json:"last_read_seq"`
	NotificationsEnabled bool       `json:"notifications_enabled"`
	SharesWardrobe       bool       `json:"shares_wardrobe"`
}

func toParticipantDTO(p db.ChatParticipant) participantDTO {
	return participantDTO{
		UserID: p.UserID, AgentID: p.AgentID, Role: p.Role, JoinedAt: p.JoinedAt,
		LastReadSeq: p.LastReadSeq, NotificationsEnabled: p.NotificationsEnabled,
		SharesWardrobe: p.SharesWardrobe,
	}
}

type messageDTO struct {
	ID             uuid.UUID  `json:"id"`
	ChatID         uuid.UUID  `json:"chat_id"`
	SenderUserID   *uuid.UUID `json:"sender_user_id,omitempty"`
	SenderAgentID  *uuid.UUID `json:"sender_agent_id,omitempty"`
	Seq            int64      `json:"seq"`
	Body           *string    `json:"body,omitempty"`
	AttachmentType *string    `json:"attachment_type,omitempty"`
	AttachmentID   *uuid.UUID `json:"attachment_id,omitempty"`
	ReplyToID      *uuid.UUID `json:"reply_to_id,omitempty"`
	CreatedAt      time.Time  `json:"created_at"`
	EditedAt       *time.Time `json:"edited_at,omitempty"`
	DeletedAt      *time.Time `json:"deleted_at,omitempty"`
}

func toMessageDTO(m db.Message) messageDTO {
	return messageDTO{
		ID: m.ID, ChatID: m.ChatID, SenderUserID: m.SenderUserID,
		SenderAgentID: m.SenderAgentID, Seq: m.Seq, Body: m.Body,
		AttachmentType: m.AttachmentType, AttachmentID: m.AttachmentID,
		ReplyToID: m.ReplyToID, CreatedAt: m.CreatedAt,
		EditedAt: m.EditedAt, DeletedAt: m.DeletedAt,
	}
}

type reactionDTO struct {
	UserID    uuid.UUID `json:"user_id"`
	Emoji     string    `json:"emoji"`
	CreatedAt time.Time `json:"created_at"`
}

// ─── Handlers ───────────────────────────────────────────────────────────────

type createChatReq struct {
	Type            string      `json:"type"`             // 'direct' | 'group'
	Name            *string     `json:"name,omitempty"`   // group only
	ParticipantIDs  []uuid.UUID `json:"participant_ids"`  // user ids (creator implicit)
	AgentIDs        []uuid.UUID `json:"agent_ids,omitempty"`
}

func handleCreateChat(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, _ := auth.UserID(r.Context())
		var req createChatReq
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeError(w, http.StatusBadRequest, "invalid body")
			return
		}
		if req.Type != "direct" && req.Type != "group" {
			writeError(w, http.StatusBadRequest, "type must be 'direct' or 'group'")
			return
		}
		if req.Type == "group" && (req.Name == nil || strings.TrimSpace(*req.Name) == "") {
			writeError(w, http.StatusBadRequest, "group chats need a name")
			return
		}
		c, err := d.Chats.CreateChat(r.Context(), req.Type, req.Name, uid,
			req.ParticipantIDs, req.AgentIDs)
		if err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		writeJSON(w, http.StatusCreated, toChatDTO(*c))
	}
}

// handleEnsureStylistDirect creates a direct chat between the caller and the
// stylist agent if none exists yet, otherwise returns the existing one.
// Idempotent — safe to call on every app launch.
func handleEnsureStylistDirect(d *Deps) http.HandlerFunc {
	stylistID := uuid.MustParse(workers.StylistAgentID)
	stylistName := "Stylist"
	return func(w http.ResponseWriter, r *http.Request) {
		uid, _ := auth.UserID(r.Context())
		if existing, err := d.Chats.FindDirectChatWithAgent(r.Context(), uid, stylistID); err == nil {
			writeJSON(w, http.StatusOK, toChatDTO(*existing))
			return
		} else if !errors.Is(err, db.ErrNotFound) {
			writeError(w, http.StatusInternalServerError, "lookup failed")
			return
		}
		c, err := d.Chats.CreateChat(r.Context(), "direct", &stylistName, uid,
			nil, []uuid.UUID{stylistID})
		if err != nil {
			writeError(w, http.StatusInternalServerError, err.Error())
			return
		}
		writeJSON(w, http.StatusCreated, toChatDTO(*c))
	}
}

func handleListChats(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, _ := auth.UserID(r.Context())
		out, err := d.Chats.ListChatsForUser(r.Context(), uid, 100)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "list failed")
			return
		}
		dtos := make([]chatDTO, 0, len(out))
		for _, c := range out {
			dtos = append(dtos, toChatDTO(c))
		}
		writeJSON(w, http.StatusOK, map[string]any{"chats": dtos})
	}
}

func handleGetChat(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, _ := auth.UserID(r.Context())
		id, err := uuid.Parse(chi.URLParam(r, "id"))
		if err != nil {
			writeError(w, http.StatusBadRequest, "bad id")
			return
		}
		ok, _, err := d.Chats.IsParticipant(r.Context(), id, uid)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "lookup failed")
			return
		}
		if !ok {
			writeError(w, http.StatusForbidden, "not a participant")
			return
		}
		c, err := d.Chats.GetChat(r.Context(), id)
		if err != nil {
			writeError(w, http.StatusNotFound, "chat not found")
			return
		}
		ps, err := d.Chats.ListParticipants(r.Context(), id)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "participants failed")
			return
		}
		dtos := make([]participantDTO, 0, len(ps))
		for _, p := range ps {
			dtos = append(dtos, toParticipantDTO(p))
		}
		writeJSON(w, http.StatusOK, map[string]any{
			"chat":         toChatDTO(*c),
			"participants": dtos,
		})
	}
}

type addParticipantReq struct {
	UserID uuid.UUID `json:"user_id"`
}

func handleAddParticipant(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, _ := auth.UserID(r.Context())
		chatID, err := uuid.Parse(chi.URLParam(r, "id"))
		if err != nil {
			writeError(w, http.StatusBadRequest, "bad id")
			return
		}
		ok, role, err := d.Chats.IsParticipant(r.Context(), chatID, uid)
		if err != nil || !ok || role != "admin" {
			writeError(w, http.StatusForbidden, "admin required")
			return
		}
		var req addParticipantReq
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeError(w, http.StatusBadRequest, "invalid body")
			return
		}
		if err := d.Chats.AddParticipant(r.Context(), chatID, req.UserID); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

func handleRemoveParticipant(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, _ := auth.UserID(r.Context())
		chatID, err := uuid.Parse(chi.URLParam(r, "id"))
		if err != nil {
			writeError(w, http.StatusBadRequest, "bad id")
			return
		}
		target, err := uuid.Parse(chi.URLParam(r, "user_id"))
		if err != nil {
			writeError(w, http.StatusBadRequest, "bad user_id")
			return
		}
		// Self-remove always OK; otherwise require admin.
		if target != uid {
			ok, role, err := d.Chats.IsParticipant(r.Context(), chatID, uid)
			if err != nil || !ok || role != "admin" {
				writeError(w, http.StatusForbidden, "admin required")
				return
			}
		}
		if err := d.Chats.RemoveParticipant(r.Context(), chatID, target); err != nil {
			if errors.Is(err, db.ErrNotFound) {
				writeError(w, http.StatusNotFound, "participant not found")
				return
			}
			writeError(w, http.StatusInternalServerError, "remove failed")
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

type sendMessageReq struct {
	Body           *string    `json:"body,omitempty"`
	AttachmentType *string    `json:"attachment_type,omitempty"`
	AttachmentID   *uuid.UUID `json:"attachment_id,omitempty"`
	ReplyToID      *uuid.UUID `json:"reply_to_id,omitempty"`
}

func handleSendMessage(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, _ := auth.UserID(r.Context())
		chatID, err := uuid.Parse(chi.URLParam(r, "id"))
		if err != nil {
			writeError(w, http.StatusBadRequest, "bad id")
			return
		}
		ok, _, err := d.Chats.IsParticipant(r.Context(), chatID, uid)
		if err != nil || !ok {
			writeError(w, http.StatusForbidden, "not a participant")
			return
		}
		var req sendMessageReq
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeError(w, http.StatusBadRequest, "invalid body")
			return
		}
		if req.Body == nil && req.AttachmentType == nil {
			writeError(w, http.StatusBadRequest, "body or attachment required")
			return
		}
		if req.AttachmentType != nil && !validAttachmentType(*req.AttachmentType) {
			writeError(w, http.StatusBadRequest, "invalid attachment_type")
			return
		}
		m := &db.Message{
			ChatID:         chatID,
			SenderUserID:   &uid,
			Body:           req.Body,
			AttachmentType: req.AttachmentType,
			AttachmentID:   req.AttachmentID,
			ReplyToID:      req.ReplyToID,
		}

		// Locked v1.1 design: seq via redis.INCR chat:{id}:seq. Fall back to
		// Postgres advisory lock when Redis is down (still correct, slower).
		if d.Realtime != nil {
			seq, err := d.Realtime.NextSeq(r.Context(), chatID)
			if err != nil {
				writeError(w, http.StatusInternalServerError, "seq failed")
				return
			}
			m.Seq = seq
			if err := d.Chats.InsertMessage(r.Context(), m); err != nil {
				writeError(w, http.StatusInternalServerError, "send failed")
				return
			}
		} else {
			if err := d.Chats.SendMessage(r.Context(), m); err != nil {
				writeError(w, http.StatusInternalServerError, "send failed")
				return
			}
		}

		// Inbox durability backstop (per locked design): every participant
		// gets an inbox row bump so the chat list shows unread + survives
		// pub/sub delivery loss.
		if err := d.Chats.BumpInboxOnNewMessage(r.Context(), chatID, m.Seq); err != nil {
			// non-fatal — message already in `messages`. Log + continue.
			// TODO: structured slog here when we wire it.
		}

		dto := toMessageDTO(*m)

		// Fan out via Redis chat:{id}. Subscribed gateways forward to live
		// sockets. Best-effort; failure here doesn't fail the request because
		// the message is durable.
		if d.Realtime != nil {
			payload, _ := json.Marshal(map[string]any{
				"type":    "message.new",
				"message": dto,
			})
			_ = d.Realtime.PublishChat(r.Context(), chatID, payload)
		}

		// Enqueue a stylist reply when this chat has the agent as a
		// participant AND either:
		//   - it's a 1:1 (direct chat with the agent → every msg replies), OR
		//   - the body @mentions the stylist
		// The locked v1.1 design also allows iOS 26 on-device classifier to
		// auto-inject @stylist; that classifier just rewrites the body
		// client-side so the same server check applies.
		if d.River != nil && req.Body != nil {
			shouldReply, err := stylistShouldReply(r.Context(), d, chatID, *req.Body)
			if err == nil && shouldReply {
				_, ierr := d.River.Insert(r.Context(),
					workers.StylistReplyArgs{
						ChatID:  chatID.String(),
						UserID:  uid.String(),
						Prompt:  *req.Body,
						IdemKey: m.ID.String(),
					},
					&river.InsertOpts{Queue: workers.QueueCritical},
				)
				if ierr != nil {
					slog.Warn("stylist enqueue failed", "err", ierr.Error())
				}
			}
		}

		writeJSON(w, http.StatusCreated, dto)
	}
}

// stylistShouldReply gates whether a user message warrants a stylist
// follow-up. Returns true when:
//   - chat has an ai_agent participant, AND
//   - the chat is a 'direct' (so the agent reads everything), OR
//   - the body @mentions the stylist (case-insensitive "@stylist").
func stylistShouldReply(ctx context.Context, d *Deps, chatID uuid.UUID, body string) (bool, error) {
	parts, err := d.Chats.ListParticipants(ctx, chatID)
	if err != nil {
		return false, err
	}
	hasAgent := false
	for _, p := range parts {
		if p.AgentID != nil {
			hasAgent = true
			break
		}
	}
	if !hasAgent {
		return false, nil
	}
	chat, err := d.Chats.GetChat(ctx, chatID)
	if err != nil {
		return false, err
	}
	if chat.Type == "direct" {
		return true, nil
	}
	return strings.Contains(strings.ToLower(body), "@stylist"), nil
}

func handleListMessages(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, _ := auth.UserID(r.Context())
		chatID, err := uuid.Parse(chi.URLParam(r, "id"))
		if err != nil {
			writeError(w, http.StatusBadRequest, "bad id")
			return
		}
		ok, _, err := d.Chats.IsParticipant(r.Context(), chatID, uid)
		if err != nil || !ok {
			writeError(w, http.StatusForbidden, "not a participant")
			return
		}
		afterSeq, _ := strconv.ParseInt(r.URL.Query().Get("after_seq"), 10, 64)
		limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
		if limit <= 0 || limit > 200 {
			limit = 50
		}
		ms, err := d.Chats.ListMessages(r.Context(), chatID, afterSeq, limit)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "list failed")
			return
		}
		ids := make([]uuid.UUID, 0, len(ms))
		out := make([]messageDTO, 0, len(ms))
		for _, m := range ms {
			ids = append(ids, m.ID)
			out = append(out, toMessageDTO(m))
		}
		rxByMsg, err := d.Chats.ListReactions(r.Context(), ids)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "reactions failed")
			return
		}
		rxOut := map[string][]reactionDTO{}
		for mid, rxs := range rxByMsg {
			arr := make([]reactionDTO, 0, len(rxs))
			for _, rx := range rxs {
				arr = append(arr, reactionDTO{UserID: rx.UserID, Emoji: rx.Emoji, CreatedAt: rx.CreatedAt})
			}
			rxOut[mid.String()] = arr
		}
		writeJSON(w, http.StatusOK, map[string]any{
			"messages":  out,
			"reactions": rxOut,
		})
	}
}

type reactionReq struct {
	Emoji string `json:"emoji"`
}

func handleAddReaction(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, _ := auth.UserID(r.Context())
		msgID, err := uuid.Parse(chi.URLParam(r, "id"))
		if err != nil {
			writeError(w, http.StatusBadRequest, "bad id")
			return
		}
		var req reactionReq
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeError(w, http.StatusBadRequest, "invalid body")
			return
		}
		if l := len(req.Emoji); l == 0 || l > 16 {
			writeError(w, http.StatusBadRequest, "emoji 1..16 chars")
			return
		}
		if err := d.Chats.AddReaction(r.Context(), msgID, uid, req.Emoji); err != nil {
			writeError(w, http.StatusInternalServerError, "react failed")
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

func handleRemoveReaction(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, _ := auth.UserID(r.Context())
		msgID, err := uuid.Parse(chi.URLParam(r, "id"))
		if err != nil {
			writeError(w, http.StatusBadRequest, "bad id")
			return
		}
		emoji := chi.URLParam(r, "emoji")
		if l := len(emoji); l == 0 || l > 16 {
			writeError(w, http.StatusBadRequest, "emoji 1..16 chars")
			return
		}
		if err := d.Chats.RemoveReaction(r.Context(), msgID, uid, emoji); err != nil {
			writeError(w, http.StatusInternalServerError, "unreact failed")
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

type readReq struct {
	Seq int64 `json:"seq"`
}

func handleSetRead(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, _ := auth.UserID(r.Context())
		chatID, err := uuid.Parse(chi.URLParam(r, "id"))
		if err != nil {
			writeError(w, http.StatusBadRequest, "bad id")
			return
		}
		var req readReq
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeError(w, http.StatusBadRequest, "invalid body")
			return
		}
		if err := d.Chats.SetReadCursor(r.Context(), chatID, uid, req.Seq); err != nil {
			writeError(w, http.StatusInternalServerError, "set-read failed")
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

func validAttachmentType(t string) bool {
	switch t {
	case "outfit", "item", "image", "link":
		return true
	}
	return false
}
