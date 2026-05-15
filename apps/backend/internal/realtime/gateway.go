package realtime

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/gorilla/websocket"
	"github.com/redis/go-redis/v9"
)

// Gateway upgrades HTTP → WebSocket and bridges client sockets to Redis
// per-chat pub/sub. One Gateway per backend process; many clients (each user
// can have multiple devices). Heartbeats (10s ping / 5s pong timeout) are
// the locked v1.1 design.
type Gateway struct {
	rdb   *Redis
	ups   websocket.Upgrader
	hub   *hub
	chats ChatLookup
}

// ChatLookup is what the gateway needs from the chat repo. Defined here as
// an interface so this package doesn't depend on internal/db.
type ChatLookup interface {
	ChatIDsForUser(ctx context.Context, userID uuid.UUID) ([]uuid.UUID, error)
}

func NewGateway(rdb *Redis, chats ChatLookup) *Gateway {
	return &Gateway{
		rdb:   rdb,
		chats: chats,
		ups: websocket.Upgrader{
			ReadBufferSize:  4096,
			WriteBufferSize: 4096,
			// CORS-equivalent for WS. iOS app sends no Origin, browsers vary.
			// Tighten in prod via Caddy header check or explicit allowlist.
			CheckOrigin: func(_ *http.Request) bool { return true },
		},
		hub: newHub(),
	}
}

// ServeHTTP upgrades an authenticated request and starts the per-conn loop.
// Caller (httpapi) is responsible for auth — gateway trusts the userID arg.
func (g *Gateway) ServeHTTP(w http.ResponseWriter, r *http.Request, userID uuid.UUID) {
	conn, err := g.ups.Upgrade(w, r, nil)
	if err != nil {
		slog.Warn("ws upgrade", "err", err.Error())
		return
	}
	c := &client{
		userID: userID,
		conn:   conn,
		send:   make(chan []byte, 64),
	}
	g.hub.register(c)
	defer g.hub.unregister(c)

	chatIDs, err := g.chats.ChatIDsForUser(r.Context(), userID)
	if err != nil {
		slog.Warn("ws chat lookup", "err", err.Error())
		_ = conn.Close()
		return
	}

	pubsubCtx, cancel := context.WithCancel(context.Background())
	defer cancel()

	if len(chatIDs) > 0 {
		ps := g.rdb.SubscribeChats(pubsubCtx, chatIDs...)
		go g.pumpPubSubToClient(pubsubCtx, ps, c)
		defer func() { _ = ps.Close() }()
	}

	go c.writePump()
	c.readPump()
}

// pumpPubSubToClient relays Redis chat:{id} messages to the client socket.
// Each Redis message is already a JSON envelope authored by SendMessage etc.
func (g *Gateway) pumpPubSubToClient(ctx context.Context, ps *redis.PubSub, c *client) {
	ch := ps.Channel()
	for {
		select {
		case <-ctx.Done():
			return
		case m, ok := <-ch:
			if !ok {
				return
			}
			select {
			case c.send <- []byte(m.Payload):
			default:
				// client too slow → drop. Inbox table covers durability.
				slog.Warn("ws send buffer full; dropping", "user", c.userID.String())
			}
		}
	}
}

// ─── hub ────────────────────────────────────────────────────────────────────

type hub struct {
	mu      sync.RWMutex
	clients map[uuid.UUID]map[*client]struct{} // userID → set of sockets
}

func newHub() *hub {
	return &hub{clients: map[uuid.UUID]map[*client]struct{}{}}
}

func (h *hub) register(c *client) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if _, ok := h.clients[c.userID]; !ok {
		h.clients[c.userID] = map[*client]struct{}{}
	}
	h.clients[c.userID][c] = struct{}{}
}

func (h *hub) unregister(c *client) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if set, ok := h.clients[c.userID]; ok {
		delete(set, c)
		if len(set) == 0 {
			delete(h.clients, c.userID)
		}
	}
	close(c.send)
	_ = c.conn.Close()
}

// ─── client ─────────────────────────────────────────────────────────────────

const (
	pongTimeout = 5 * time.Second
	pingPeriod  = 10 * time.Second
	writeWait   = 10 * time.Second
	readLimit   = 4 << 10 // 4KB per inbound frame
)

type client struct {
	userID uuid.UUID
	conn   *websocket.Conn
	send   chan []byte
}

func (c *client) writePump() {
	ticker := time.NewTicker(pingPeriod)
	defer ticker.Stop()
	for {
		select {
		case msg, ok := <-c.send:
			if !ok {
				_ = c.conn.WriteMessage(websocket.CloseMessage, nil)
				return
			}
			_ = c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.conn.WriteMessage(websocket.TextMessage, msg); err != nil {
				return
			}
		case <-ticker.C:
			_ = c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

func (c *client) readPump() {
	defer c.conn.Close()
	c.conn.SetReadLimit(readLimit)
	_ = c.conn.SetReadDeadline(time.Now().Add(pingPeriod + pongTimeout))
	c.conn.SetPongHandler(func(string) error {
		return c.conn.SetReadDeadline(time.Now().Add(pingPeriod + pongTimeout))
	})
	for {
		_, raw, err := c.conn.ReadMessage()
		if err != nil {
			return
		}
		// We accept simple {type:"ack"} / {type:"typing"} frames; nothing
		// else is wired in PR2. Echo nothing on success.
		var env struct {
			Type string `json:"type"`
		}
		if err := json.Unmarshal(raw, &env); err != nil {
			continue
		}
		// TODO: handle ack frames (mark inbox row delivered) + typing pings.
	}
}
