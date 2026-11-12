package main

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"github.com/gorilla/websocket"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
	"unicode/utf8"
)

func testRelay(t *testing.T, c Config) (*relay, string) {
	t.Helper()
	h := newRelay(c)
	server := httptest.NewServer(h.handler())
	t.Cleanup(func() { h.close(); server.Close() })
	return h, "ws" + strings.TrimPrefix(server.URL, "http") + "/ws"
}
func connect(t *testing.T, endpoint string, first envelope) (*websocket.Conn, envelope) {
	t.Helper()
	return connectHeader(t, endpoint, first, nil)
}
func connectHeader(t *testing.T, endpoint string, first envelope, header http.Header) (*websocket.Conn, envelope) {
	t.Helper()
	conn, _, err := websocket.DefaultDialer.Dial(endpoint, header)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = conn.Close() })
	if err := conn.WriteJSON(first); err != nil {
		t.Fatal(err)
	}
	return conn, read(t, conn)
}
func read(t *testing.T, conn *websocket.Conn) envelope {
	t.Helper()
	_ = conn.SetReadDeadline(time.Now().Add(2 * time.Second))
	var msg envelope
	if err := conn.ReadJSON(&msg); err != nil {
		t.Fatal(err)
	}
	return msg
}
func expectOp(t *testing.T, conn *websocket.Conn, expected string) envelope {
	t.Helper()
	msg := read(t, conn)
	if msg.Op != expected {
		t.Fatalf("op=%q; expected %q: %+v", msg.Op, expected, msg)
	}
	return msg
}

func TestCreateJoinCapacityPasswordAndNames(t *testing.T) {
	_, endpoint := testRelay(t, Config{})
	host, welcome := connect(t, endpoint, envelope{Op: "create", Room: "test42", Password: "private", Name: "守夜人"})
	if welcome.Op != "welcome" || welcome.PeerID != 1 || welcome.HostID != 1 || welcome.Room != "TEST42" || len(welcome.Peers) != 1 {
		t.Fatalf("bad welcome: %+v", welcome)
	}
	if welcome.Password != "" {
		t.Fatal("Password leaked in welcome")
	}
	_, denied := connect(t, endpoint, envelope{Op: "join", Room: "TEST42", Password: "wrong"})
	if denied.Code != "wrong_password" {
		t.Fatalf("bad denial: %+v", denied)
	}
	_, absent := connect(t, endpoint, envelope{Op: "join", Room: "MISSING"})
	if absent.Code != "room_not_found" {
		t.Fatalf("bad absent response: %+v", absent)
	}
	var guests []*websocket.Conn
	for i := 2; i <= 4; i++ {
		guest, info := connect(t, endpoint, envelope{Op: "join", Room: " test42 ", Password: "private", Name: strings.Repeat("墨", 30)})
		if info.PeerID != i || len(info.Peers) != i {
			t.Fatalf("bad guest welcome: %+v", info)
		}
		if utf8.RuneCountInString(info.Peers[i-1].Name) != 24 {
			t.Fatal("Name was not limited to 24 Unicode characters")
		}
		joined := expectOp(t, host, "peer_joined")
		if joined.PeerID != i {
			t.Fatalf("unexpected join: %+v", joined)
		}
		guests = append(guests, guest)
	}
	_, full := connect(t, endpoint, envelope{Op: "join", Room: "TEST42", Password: "private"})
	if full.Code != "room_full" {
		t.Fatalf("bad full denial: %+v", full)
	}
	_ = guests[0].Close()
	left := expectOp(t, host, "peer_left")
	if left.PeerID != 2 {
		t.Fatalf("unexpected departure: %+v", left)
	}
	_, replacement := connect(t, endpoint, envelope{Op: "join", Room: "TEST42", Password: "private"})
	if replacement.PeerID != 5 {
		t.Fatalf("Peer ids reused within a room: %+v", replacement)
	}
}

func TestRoutingIdentityAndGuestAuthority(t *testing.T) {
	_, endpoint := testRelay(t, Config{})
	host, welcome := connect(t, endpoint, envelope{Op: "create"})
	guest, _ := connect(t, endpoint, envelope{Op: "join", Room: welcome.Room})
	expectOp(t, host, "peer_joined")
	data := json.RawMessage(`{"kind":"input","data":{"forward":true}}`)
	if err := guest.WriteJSON(envelope{Op: "packet", To: 1, From: 999, Data: data}); err != nil {
		t.Fatal(err)
	}
	input := expectOp(t, host, "packet")
	if input.From != 2 || string(input.Data) != string(data) {
		t.Fatalf("Identity or payload corrupted: %+v", input)
	}
	if err := host.WriteJSON(envelope{Op: "packet", To: 0, Data: json.RawMessage(`{"kind":"snapshot","data":{"wave":3}}`)}); err != nil {
		t.Fatal(err)
	}
	snapshot := expectOp(t, guest, "packet")
	if snapshot.From != 1 {
		t.Fatalf("Bad host identity: %+v", snapshot)
	}
	if err := guest.WriteJSON(envelope{Op: "packet", To: 0, Data: data}); err != nil {
		t.Fatal(err)
	}
	if expectOp(t, guest, "error").Code != "host_only" {
		t.Fatal("Guest broadcast was not rejected")
	}
	if err := host.WriteJSON(envelope{Op: "packet", To: 99, Data: data}); err != nil {
		t.Fatal(err)
	}
	if expectOp(t, host, "error").Code != "peer_not_found" {
		t.Fatal("Missing target not rejected")
	}
	if err := guest.WriteJSON(envelope{Op: "ping"}); err != nil {
		t.Fatal(err)
	}
	expectOp(t, guest, "pong")
}

func TestHostDisconnectClosesRoom(t *testing.T) {
	h, endpoint := testRelay(t, Config{})
	host, info := connect(t, endpoint, envelope{Op: "create"})
	guest, _ := connect(t, endpoint, envelope{Op: "join", Room: info.Room})
	expectOp(t, host, "peer_joined")
	_ = host.Close()
	closed := expectOp(t, guest, "room_closed")
	if closed.Reason != "host_left" {
		t.Fatalf("bad close reason: %+v", closed)
	}
	h.mu.Lock()
	count := len(h.rooms)
	h.mu.Unlock()
	if count != 0 {
		t.Fatalf("Orphan room remains: %d", count)
	}
	_, reply := connect(t, endpoint, envelope{Op: "join", Room: info.Room})
	if reply.Code != "room_not_found" {
		t.Fatalf("Closed room accepts joins: %+v", reply)
	}
}

func TestInvalidHandshakeAndRoomLimit(t *testing.T) {
	_, endpoint := testRelay(t, Config{MaxRooms: 1})
	_, invalid := connect(t, endpoint, envelope{Op: "packet"})
	if invalid.Code != "handshake_required" {
		t.Fatal(invalid)
	}
	_, invalid = connect(t, endpoint, envelope{Op: "create", Room: "x/y?"})
	if invalid.Code != "invalid_room" {
		t.Fatal(invalid)
	}
	_, created := connect(t, endpoint, envelope{Op: "create"})
	if len(created.Room) != 6 {
		t.Fatalf("Bad generated room code: %q", created.Room)
	}
	_, full := connect(t, endpoint, envelope{Op: "create"})
	if full.Code != "server_full" {
		t.Fatal(full)
	}
}

func TestOversizedFrameDisconnectsAndNotifiesHost(t *testing.T) {
	_, endpoint := testRelay(t, Config{})
	host, info := connect(t, endpoint, envelope{Op: "create"})
	guest, _ := connect(t, endpoint, envelope{Op: "join", Room: info.Room})
	expectOp(t, host, "peer_joined")
	huge := `{"op":"packet","to":1,"data":"` + strings.Repeat("x", frameLimit) + `"}`
	_ = guest.WriteMessage(websocket.TextMessage, []byte(huge))
	_ = guest.SetReadDeadline(time.Now().Add(2 * time.Second))
	_, _, err := guest.ReadMessage()
	if err == nil {
		t.Fatal("Oversized frame should close connection")
	}
	expectOp(t, host, "peer_left")
}

func TestHandshakeTimeout(t *testing.T) {
	_, endpoint := testRelay(t, Config{JoinTimeout: 40 * time.Millisecond})
	conn, _, err := websocket.DefaultDialer.Dial(endpoint, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	_ = conn.SetReadDeadline(time.Now().Add(time.Second))
	if _, _, err := conn.ReadMessage(); err == nil {
		t.Fatal("Unauthenticated connection did not time out")
	}
}

func signTicket(t *testing.T, secret []byte, claims ticket) string {
	t.Helper()
	payload, err := json.Marshal(claims)
	if err != nil {
		t.Fatal(err)
	}
	segment := base64.RawURLEncoding.EncodeToString(payload)
	mac := hmac.New(sha256.New, secret)
	mac.Write([]byte(segment))
	return segment + "." + base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}

func browserHeader(endpoint string) http.Header {
	// Browsers send an Origin for the page host; Caddy preserves that host, so a
	// passing test origin must match the test server's own host.
	return http.Header{"Origin": []string{"http" + strings.TrimSuffix(strings.TrimPrefix(endpoint, "ws"), "/ws")}}
}

func TestBrowserRoomsRequireACenterTicket(t *testing.T) {
	secret := []byte(strings.Repeat("k", 32))
	_, endpoint := testRelay(t, Config{Login: loginWeb, TicketSecret: secret})
	header := browserHeader(endpoint)
	if _, denied := connectHeader(t, endpoint, envelope{Op: "create"}, header); denied.Code != "login_required" {
		t.Fatalf("anonymous browser create was not rejected: %+v", denied)
	}
	if _, invalid := connectHeader(t, endpoint, envelope{Op: "create", Ticket: "not-a-ticket"}, header); invalid.Code != "ticket_invalid" {
		t.Fatalf("malformed ticket was not rejected: %+v", invalid)
	}
	expired := signTicket(t, secret, ticket{Version: 1, Account: "user-1", Name: "守夜人", Expires: time.Now().Unix() - 1})
	if _, reply := connectHeader(t, endpoint, envelope{Op: "create", Ticket: expired}, header); reply.Code != "ticket_expired" {
		t.Fatalf("expired ticket was not rejected: %+v", reply)
	}
	valid := signTicket(t, secret, ticket{Version: 1, Account: "user-1", Name: "墨客甲", Expires: time.Now().Unix() + 60})
	host, welcome := connectHeader(t, endpoint, envelope{Op: "create", Ticket: valid, Name: "伪造昵称"}, header)
	if welcome.Op != "welcome" || welcome.Peers[0].Name != "墨客甲" {
		t.Fatalf("ticket did not establish host identity: %+v", welcome)
	}
	guestTicket := signTicket(t, secret, ticket{Version: 1, Account: "user-2", Name: "墨客乙", Expires: time.Now().Unix() + 60})
	_, joined := connectHeader(t, endpoint, envelope{Op: "join", Room: welcome.Room, Ticket: guestTicket}, header)
	if joined.Op != "welcome" || joined.PeerID != 2 {
		t.Fatalf("ticketed guest could not join: %+v", joined)
	}
	if expectOp(t, host, "peer_joined").PeerID != 2 {
		t.Fatal("host was not told about the ticketed guest")
	}
	// A signed payload naming another account still works, but only with the
	// shared secret; a client cannot forge one without it.
	forged := signTicket(t, []byte(strings.Repeat("x", 32)), ticket{Version: 1, Account: "user-3", Name: "伪客", Expires: time.Now().Unix() + 60})
	if _, reply := connectHeader(t, endpoint, envelope{Op: "create", Ticket: forged}, header); reply.Code != "ticket_invalid" {
		t.Fatalf("ticket signed with another secret was accepted: %+v", reply)
	}
}

func TestDesktopClientsKeepNativeRelayPlay(t *testing.T) {
	secret := []byte(strings.Repeat("k", 32))
	_, endpoint := testRelay(t, Config{Login: loginWeb, TicketSecret: secret})
	// Native Godot clients send no Origin header and remain unaffected.
	if _, welcome := connect(t, endpoint, envelope{Op: "create", Name: "桌面守夜人"}); welcome.Op != "welcome" {
		t.Fatalf("native client was blocked: %+v", welcome)
	}
}

func TestStrictModeRequiresTicketsForEveryClient(t *testing.T) {
	secret := []byte(strings.Repeat("k", 32))
	_, endpoint := testRelay(t, Config{Login: loginAll, TicketSecret: secret})
	if _, denied := connect(t, endpoint, envelope{Op: "create"}); denied.Code != "login_required" {
		t.Fatalf("anonymous native create was not rejected: %+v", denied)
	}
	valid := signTicket(t, secret, ticket{Version: 1, Account: "user-1", Name: "守夜人", Expires: time.Now().Unix() + 60})
	if _, welcome := connect(t, endpoint, envelope{Op: "create", Ticket: valid}); welcome.Op != "welcome" {
		t.Fatalf("ticketed native client was blocked: %+v", welcome)
	}
}

func TestOpenRelayIgnoresTickets(t *testing.T) {
	_, endpoint := testRelay(t, Config{})
	if _, welcome := connectHeader(t, endpoint, envelope{Op: "create", Ticket: "garbage"}, browserHeader(endpoint)); welcome.Op != "welcome" {
		t.Fatalf("open relay rejected a browser client: %+v", welcome)
	}
}

func TestHealthEndpoint(t *testing.T) {
	_, endpoint := testRelay(t, Config{})
	response, err := http.Get("http" + strings.TrimSuffix(strings.TrimPrefix(endpoint, "ws"), "/ws") + "/healthz")
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	var info map[string]any
	if err := json.NewDecoder(response.Body).Decode(&info); err != nil {
		t.Fatal(err)
	}
	if response.StatusCode != http.StatusOK || info["ok"] != true || info["room_capacity"] != float64(4) || info["login"] != "off" {
		t.Fatal(info)
	}
}
