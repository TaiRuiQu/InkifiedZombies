package main

import (
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"regexp"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"time"
	"unicode"
	"unicode/utf8"

	"github.com/gorilla/websocket"
)

const (
	roomCapacity  = 4
	frameLimit    = 256 * 1024
	sendQueueSize = 128
)

var roomPattern = regexp.MustCompile(`^[A-Z0-9]{4,16}$`)

// Config controls deployment limits. Timeouts are configurable for integration tests.
type Config struct {
	MaxRooms       int
	MaxConnections int
	JoinTimeout    time.Duration
	IdleTimeout    time.Duration
	PingInterval   time.Duration
	WriteTimeout   time.Duration
}

func (c Config) defaults() Config {
	if c.MaxRooms <= 0 {
		c.MaxRooms = 256
	}
	if c.MaxConnections <= 0 {
		c.MaxConnections = 1024
	}
	if c.JoinTimeout <= 0 {
		c.JoinTimeout = 10 * time.Second
	}
	if c.IdleTimeout <= 0 {
		c.IdleTimeout = 45 * time.Second
	}
	if c.PingInterval <= 0 {
		c.PingInterval = 15 * time.Second
	}
	if c.WriteTimeout <= 0 {
		c.WriteTimeout = 5 * time.Second
	}
	return c
}

type envelope struct {
	Op       string          `json:"op"`
	Room     string          `json:"room,omitempty"`
	Password string          `json:"password,omitempty"`
	Name     string          `json:"name,omitempty"`
	To       int             `json:"to,omitempty"`
	From     int             `json:"from,omitempty"`
	PeerID   int             `json:"peer_id,omitempty"`
	HostID   int             `json:"host_id,omitempty"`
	Peers    []peerInfo      `json:"peers,omitempty"`
	Data     json.RawMessage `json:"data,omitempty"`
	Code     string          `json:"code,omitempty"`
	Message  string          `json:"message,omitempty"`
	Reason   string          `json:"reason,omitempty"`
}

type peerInfo struct {
	ID   int    `json:"id"`
	Name string `json:"name"`
}

type protocolError struct{ code, message string }

func (e *protocolError) Error() string { return e.message }
func issue(code, message string) error { return &protocolError{code, message} }

type room struct {
	code         string
	passwordHash [32]byte
	peers        map[int]*peer
	nextID       int
}

type outgoing struct {
	data       []byte
	closeAfter bool
}

type peer struct {
	conn  *websocket.Conn
	id    int
	name  string
	room  *room
	send  chan outgoing
	done  chan struct{}
	once  sync.Once
	relay *relay
}

func (p *peer) stop() { p.once.Do(func() { close(p.done); _ = p.conn.Close() }) }

func (p *peer) enqueue(msg envelope, closeAfter bool) bool {
	payload, err := json.Marshal(msg)
	if err != nil {
		return false
	}
	select {
	case <-p.done:
		return false
	default:
	}
	select {
	case p.send <- outgoing{data: payload, closeAfter: closeAfter}:
		return true
	default:
		// A slow consumer cannot grow memory without bound or stall the room.
		p.stop()
		return false
	}
}

type relay struct {
	config      Config
	mu          sync.Mutex
	rooms       map[string]*room
	closed      bool
	connections atomic.Int64
	upgrader    websocket.Upgrader
}

func newRelay(c Config) *relay {
	return &relay{config: c.defaults(), rooms: make(map[string]*room), upgrader: websocket.Upgrader{
		ReadBufferSize: 4096, WriteBufferSize: 4096,
		// Nil CheckOrigin preserves Gorilla's same-host policy for browsers;
		// native Godot clients without an Origin header are accepted.
		HandshakeTimeout: 5 * time.Second,
	}}
}

func (h *relay) handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/ws", h.serveWebSocket)
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		h.mu.Lock()
		roomCount := len(h.rooms)
		closed := h.closed
		h.mu.Unlock()
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "no-store")
		if closed {
			w.WriteHeader(http.StatusServiceUnavailable)
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"ok": !closed, "version": version, "rooms": roomCount, "connections": h.connections.Load(), "room_capacity": roomCapacity})
	})
	return mux
}

func (h *relay) serveWebSocket(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "GET required", http.StatusMethodNotAllowed)
		return
	}
	if h.connections.Add(1) > int64(h.config.MaxConnections) {
		h.connections.Add(-1)
		http.Error(w, "Relay connection limit reached", http.StatusServiceUnavailable)
		return
	}
	defer h.connections.Add(-1)
	conn, err := h.upgrader.Upgrade(w, r, nil)
	if err != nil {
		return
	}
	defer conn.Close()
	conn.SetReadLimit(frameLimit)
	_ = conn.SetReadDeadline(time.Now().Add(h.config.JoinTimeout))
	messageType, raw, err := conn.ReadMessage()
	if err != nil {
		return
	}
	var first envelope
	if messageType != websocket.TextMessage || !utf8.Valid(raw) || json.Unmarshal(raw, &first) != nil {
		h.reject(conn, "bad_json", "First frame must be a UTF-8 JSON create/join request")
		return
	}
	p := &peer{conn: conn, send: make(chan outgoing, sendQueueSize), done: make(chan struct{}), relay: h}
	if err := h.attach(p, first); err != nil {
		var problem *protocolError
		if errors.As(err, &problem) {
			h.reject(conn, problem.code, problem.message)
		} else {
			h.reject(conn, "internal_error", "Unable to enter room")
		}
		return
	}
	defer h.detach(p)
	defer p.stop()
	_ = conn.SetReadDeadline(time.Now().Add(h.config.IdleTimeout))
	conn.SetPongHandler(func(string) error { return conn.SetReadDeadline(time.Now().Add(h.config.IdleTimeout)) })
	go p.writeLoop()
	// Server-injected identity is derived from p, never from a client's from field.
	for {
		messageType, raw, err = conn.ReadMessage()
		if err != nil {
			return
		}
		_ = conn.SetReadDeadline(time.Now().Add(h.config.IdleTimeout))
		if messageType != websocket.TextMessage || !utf8.Valid(raw) {
			p.enqueue(envelope{Op: "error", Code: "text_required", Message: "Only UTF-8 JSON text frames are accepted"}, true)
			<-p.done
			return
		}
		var msg envelope
		if json.Unmarshal(raw, &msg) != nil {
			p.enqueue(envelope{Op: "error", Code: "bad_json", Message: "Invalid JSON envelope"}, true)
			<-p.done
			return
		}
		if err := h.route(p, msg); err != nil {
			var problem *protocolError
			if errors.As(err, &problem) {
				p.enqueue(envelope{Op: "error", Code: problem.code, Message: problem.message}, false)
			}
		}
	}
}

func (h *relay) reject(conn *websocket.Conn, code, message string) {
	_ = conn.SetWriteDeadline(time.Now().Add(h.config.WriteTimeout))
	_ = conn.WriteJSON(envelope{Op: "error", Code: code, Message: message})
	_ = conn.WriteControl(websocket.CloseMessage, websocket.FormatCloseMessage(websocket.ClosePolicyViolation, code), time.Now().Add(time.Second))
}

func cleanName(value string) string {
	value = strings.TrimSpace(value)
	value = strings.Map(func(r rune) rune {
		if unicode.IsControl(r) {
			return -1
		}
		return r
	}, value)
	runes := []rune(value)
	if len(runes) > 24 {
		value = string(runes[:24])
	}
	if value == "" {
		value = "墨客"
	}
	return value
}

func randomCode() (string, error) {
	const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var bytes [6]byte
	if _, err := rand.Read(bytes[:]); err != nil {
		return "", err
	}
	for i := range bytes {
		bytes[i] = alphabet[int(bytes[i])%len(alphabet)]
	}
	return string(bytes[:]), nil
}

func (h *relay) attach(p *peer, request envelope) error {
	if request.Op != "create" && request.Op != "join" {
		return issue("handshake_required", "First operation must be create or join")
	}
	if len(request.Password) > 512 {
		return issue("password_too_long", "Password exceeds 512 UTF-8 bytes")
	}
	code := strings.ToUpper(strings.TrimSpace(request.Room))
	if code != "" && !roomPattern.MatchString(code) {
		return issue("invalid_room", "Room code must contain 4–16 ASCII letters or digits")
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.closed {
		return issue("server_closing", "Relay is shutting down")
	}
	var target *room
	if request.Op == "create" {
		if len(h.rooms) >= h.config.MaxRooms {
			return issue("server_full", "Relay room limit reached")
		}
		if code == "" {
			for {
				var err error
				code, err = randomCode()
				if err != nil {
					return err
				}
				if h.rooms[code] == nil {
					break
				}
			}
		}
		if h.rooms[code] != nil {
			return issue("room_exists", "Room code already in use")
		}
		target = &room{code: code, passwordHash: sha256.Sum256([]byte(request.Password)), peers: make(map[int]*peer), nextID: 2}
		p.id = 1
		h.rooms[code] = target
	} else {
		target = h.rooms[code]
		if target == nil {
			return issue("room_not_found", "Room does not exist or its host has left")
		}
		provided := sha256.Sum256([]byte(request.Password))
		if subtle.ConstantTimeCompare(provided[:], target.passwordHash[:]) != 1 {
			return issue("wrong_password", "Room password does not match")
		}
		if len(target.peers) >= roomCapacity {
			return issue("room_full", "Room already has four players")
		}
		p.id = target.nextID
		target.nextID++
	}
	p.name = cleanName(request.Name)
	p.room = target
	target.peers[p.id] = p
	roster := make([]peerInfo, 0, len(target.peers))
	for _, existing := range target.peers {
		roster = append(roster, peerInfo{ID: existing.id, Name: existing.name})
	}
	sort.Slice(roster, func(i, j int) bool { return roster[i].ID < roster[j].ID })
	// Queue welcome while holding the same lock as routing: it is always first.
	p.enqueue(envelope{Op: "welcome", PeerID: p.id, HostID: 1, Room: code, Peers: roster}, false)
	for _, existing := range target.peers {
		if existing != p {
			existing.enqueue(envelope{Op: "peer_joined", PeerID: p.id, Name: p.name}, false)
		}
	}
	log.Printf("room=%s peer=%d joined players=%d", code, p.id, len(target.peers))
	return nil
}

func (h *relay) route(sender *peer, msg envelope) error {
	if msg.Op == "ping" {
		sender.enqueue(envelope{Op: "pong"}, false)
		return nil
	}
	if msg.Op != "packet" {
		return issue("unknown_op", "Expected packet or ping")
	}
	if len(msg.Data) == 0 || !json.Valid(msg.Data) {
		return issue("invalid_data", "packet.data must be a JSON value")
	}
	if msg.To < 0 {
		return issue("invalid_target", "Target must be zero or a peer id")
	}
	// Guests submit inputs only to the host. Only the host may broadcast state.
	if sender.id != 1 && msg.To != 1 {
		return issue("host_only", "Guest packets must target host peer 1")
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	if sender.room == nil || sender.room.peers[sender.id] != sender || h.rooms[sender.room.code] != sender.room {
		return issue("room_closed", "Room has closed")
	}
	packet := envelope{Op: "packet", From: sender.id, Data: msg.Data}
	if msg.To == 0 {
		for _, recipient := range sender.room.peers {
			if recipient != sender {
				recipient.enqueue(packet, false)
			}
		}
		return nil
	}
	recipient := sender.room.peers[msg.To]
	if recipient == nil {
		return issue("peer_not_found", "Target peer is not in this room")
	}
	if recipient != sender {
		recipient.enqueue(packet, false)
	}
	return nil
}

func (h *relay) detach(p *peer) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if p.room == nil || p.room.peers[p.id] != p {
		return
	}
	target := p.room
	delete(target.peers, p.id)
	if p.id == 1 {
		delete(h.rooms, target.code)
		for _, guest := range target.peers {
			guest.enqueue(envelope{Op: "room_closed", Reason: "host_left", Message: "Host disconnected"}, true)
		}
		target.peers = make(map[int]*peer)
	} else {
		for _, remaining := range target.peers {
			remaining.enqueue(envelope{Op: "peer_left", PeerID: p.id}, false)
		}
	}
	log.Printf("room=%s peer=%d left", target.code, p.id)
	p.room = nil
}

func (p *peer) writeLoop() {
	defer p.stop()
	ticker := time.NewTicker(p.relay.config.PingInterval)
	defer ticker.Stop()
	for {
		select {
		case message := <-p.send:
			_ = p.conn.SetWriteDeadline(time.Now().Add(p.relay.config.WriteTimeout))
			if err := p.conn.WriteMessage(websocket.TextMessage, message.data); err != nil {
				return
			}
			if message.closeAfter {
				_ = p.conn.WriteControl(websocket.CloseMessage, websocket.FormatCloseMessage(websocket.CloseNormalClosure, "room closed"), time.Now().Add(time.Second))
				return
			}
		case <-ticker.C:
			if err := p.conn.WriteControl(websocket.PingMessage, nil, time.Now().Add(p.relay.config.WriteTimeout)); err != nil {
				return
			}
		case <-p.done:
			return
		}
	}
}

func (h *relay) close() {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.closed = true
	for _, target := range h.rooms {
		for _, p := range target.peers {
			p.enqueue(envelope{Op: "room_closed", Reason: "server_shutdown", Message: "Relay is shutting down"}, true)
		}
	}
	h.rooms = make(map[string]*room)
	fmt.Println("Relay rooms closed")
}
