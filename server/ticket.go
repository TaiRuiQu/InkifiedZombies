package main

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"
)

// Center signs a short-lived room ticket for a signed-in Paper account; the
// relay only verifies it with the shared secret. Keep this format compatible
// with packages/center/server/game-ticket.ts: base64url(payloadJSON) + "." +
// base64url(HMAC-SHA256(secret, payloadSegment)), both without padding.
const (
	ticketVersion   = 1
	ticketNameLimit = 24
)

type ticket struct {
	Version int    `json:"v"`
	Account string `json:"sub"`
	Name    string `json:"name"`
	Issued  int64  `json:"iat"`
	Expires int64  `json:"exp"`
}

type loginMode int

const (
	// loginOff keeps the relay open; use it only for isolated local play.
	loginOff loginMode = iota
	// loginWeb requires a ticket from clients that send an Origin header, which
	// browser builds always do. Native builds keep their own LAN/relay play.
	loginWeb
	// loginAll requires a ticket for every client.
	loginAll
)

func parseLoginMode(value string) (loginMode, error) {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "", "off", "none":
		return loginOff, nil
	case "browser", "web":
		return loginWeb, nil
	case "all":
		return loginAll, nil
	}
	return loginOff, fmt.Errorf("unknown login policy %q; expected off, browser or all", value)
}

func (m loginMode) String() string {
	switch m {
	case loginWeb:
		return "browser"
	case loginAll:
		return "all"
	}
	return "off"
}

func parseTicketSecret(value string) ([]byte, error) {
	if len(value) != 64 {
		return nil, errors.New("INK_TIDE_TICKET_SECRET must contain 64 hex characters")
	}
	secret, err := hex.DecodeString(value)
	if err != nil {
		return nil, errors.New("INK_TIDE_TICKET_SECRET must contain 64 hex characters")
	}
	return secret, nil
}

func verifyTicket(secret []byte, raw string, at time.Time) (ticket, error) {
	var claims ticket
	parts := strings.Split(raw, ".")
	if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
		return claims, issue("ticket_invalid", "Room ticket is malformed")
	}
	provided, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return claims, issue("ticket_invalid", "Room ticket is malformed")
	}
	mac := hmac.New(sha256.New, secret)
	mac.Write([]byte(parts[0]))
	if !hmac.Equal(mac.Sum(nil), provided) {
		return claims, issue("ticket_invalid", "Room ticket signature does not match")
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil || json.Unmarshal(payload, &claims) != nil {
		return claims, issue("ticket_invalid", "Room ticket payload is not readable")
	}
	if claims.Version != ticketVersion || strings.TrimSpace(claims.Account) == "" {
		return claims, issue("ticket_invalid", "Room ticket is not usable")
	}
	if claims.Expires <= at.Unix() {
		return claims, issue("ticket_expired", "Room ticket has expired")
	}
	return claims, nil
}

func ticketName(value string) string {
	var builder strings.Builder
	for _, r := range value {
		if r < 0x20 || r == 0x7f {
			continue
		}
		builder.WriteRune(r)
	}
	runes := []rune(strings.TrimSpace(builder.String()))
	if len(runes) > ticketNameLimit {
		runes = runes[:ticketNameLimit]
	}
	return string(runes)
}
