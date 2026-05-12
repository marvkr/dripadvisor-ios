package auth

import (
	"strings"
	"testing"

	"github.com/google/uuid"
)

func TestSignerRoundtrip(t *testing.T) {
	s := NewSigner(strings.Repeat("x", 32), 1)
	uid := uuid.New()
	tok, _, err := s.Issue(uid)
	if err != nil {
		t.Fatalf("issue: %v", err)
	}
	claims, err := s.Verify(tok)
	if err != nil {
		t.Fatalf("verify: %v", err)
	}
	if claims.UserID != uid {
		t.Fatalf("want %s got %s", uid, claims.UserID)
	}
}

func TestSignerRejectsTamperedToken(t *testing.T) {
	s := NewSigner(strings.Repeat("a", 32), 1)
	tok, _, _ := s.Issue(uuid.New())
	tampered := tok + "x"
	if _, err := s.Verify(tampered); err == nil {
		t.Fatal("expected error for tampered token")
	}
}
