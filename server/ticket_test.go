package main

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"strings"
	"testing"
	"time"
)

func TestTicketVerification(t *testing.T) {
	secret := []byte(strings.Repeat("k", 32))
	valid := signTicket(t, secret, ticket{Version: 1, Account: "user-1", Name: "墨客", Expires: time.Now().Unix() + 60})
	claims, err := verifyTicket(secret, valid, time.Now())
	if err != nil || claims.Account != "user-1" || claims.Name != "墨客" {
		t.Fatalf("valid ticket rejected: %+v %v", claims, err)
	}
	if _, err := verifyTicket([]byte(strings.Repeat("x", 32)), valid, time.Now()); err == nil {
		t.Fatal("ticket accepted under a different secret")
	}
	if _, err := verifyTicket(secret, "no-dot", time.Now()); err == nil {
		t.Fatal("malformed ticket accepted")
	}
	// Re-encode the payload with a changed account but keep the old signature.
	payload, _ := base64.RawURLEncoding.DecodeString(strings.Split(valid, ".")[0])
	var decoded map[string]any
	if err := json.Unmarshal(payload, &decoded); err != nil {
		t.Fatal(err)
	}
	decoded["sub"] = "user-2"
	tamperedPayload, _ := json.Marshal(decoded)
	tampered := base64.RawURLEncoding.EncodeToString(tamperedPayload) + "." + strings.Split(valid, ".")[1]
	if _, err := verifyTicket(secret, tampered, time.Now()); err == nil {
		t.Fatal("tampered payload accepted")
	}
	expired := signTicket(t, secret, ticket{Version: 1, Account: "user-1", Expires: time.Now().Unix() - 1})
	if _, err := verifyTicket(secret, expired, time.Now()); err == nil {
		t.Fatal("expired ticket accepted")
	}
	wrongVersion := signTicket(t, secret, ticket{Version: 2, Account: "user-1", Expires: time.Now().Unix() + 60})
	if _, err := verifyTicket(secret, wrongVersion, time.Now()); err == nil {
		t.Fatal("unsupported ticket version accepted")
	}
	anonymous := signTicket(t, secret, ticket{Version: 1, Expires: time.Now().Unix() + 60})
	if _, err := verifyTicket(secret, anonymous, time.Now()); err == nil {
		t.Fatal("ticket without an account accepted")
	}
}

func TestTicketMatchesCenterEncoding(t *testing.T) {
	secret := []byte(strings.Repeat("a", 32))
	payload := `{"v":1,"sub":"user-1","name":"墨客","iat":100,"exp":400}`
	segment := base64.RawURLEncoding.EncodeToString([]byte(payload))
	mac := hmac.New(sha256.New, secret)
	mac.Write([]byte(segment))
	raw := segment + "." + base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
	claims, err := verifyTicket(secret, raw, time.Unix(200, 0))
	if err != nil || claims.Account != "user-1" || claims.Name != "墨客" {
		t.Fatalf("Center-format ticket rejected: %+v %v", claims, err)
	}
}

func TestLoginModeAndSecretParsing(t *testing.T) {
	for value, expected := range map[string]loginMode{"": loginOff, "off": loginOff, "browser": loginWeb, "web": loginWeb, "all": loginAll} {
		if actual, err := parseLoginMode(value); err != nil || actual != expected {
			t.Fatalf("parseLoginMode(%q) = %v, %v", value, actual, err)
		}
	}
	if _, err := parseLoginMode("everyone"); err == nil {
		t.Fatal("unknown login policy accepted")
	}
	if _, err := parseTicketSecret("abc"); err == nil {
		t.Fatal("short ticket secret accepted")
	}
	if _, err := parseTicketSecret(strings.Repeat("z", 64)); err == nil {
		t.Fatal("non-hex ticket secret accepted")
	}
	if secret, err := parseTicketSecret(strings.Repeat("0f", 32)); err != nil || len(secret) != 32 {
		t.Fatalf("valid secret rejected: %v", err)
	}
}

func TestTicketNameLimit(t *testing.T) {
	long := strings.Repeat("墨", 40)
	if name := ticketName(long); len([]rune(name)) != ticketNameLimit {
		t.Fatalf("ticket name was not limited: %d", len([]rune(name)))
	}
	if name := ticketName("  墨\n客  "); name != "墨客" {
		t.Fatalf("ticket name was not cleaned: %q", name)
	}
}
