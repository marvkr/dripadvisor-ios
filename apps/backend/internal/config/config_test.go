package config

import (
	"strings"
	"testing"
)

func TestLoad_RejectsShortSecret(t *testing.T) {
	t.Setenv("JWT_SIGNING_SECRET", "tooshort")
	if _, err := Load(); err == nil {
		t.Fatal("expected error for short secret")
	}
}

func TestLoad_Defaults(t *testing.T) {
	t.Setenv("JWT_SIGNING_SECRET", strings.Repeat("a", 32))
	c, err := Load()
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	if c.HTTPAddr != ":8080" {
		t.Fatalf("HTTPAddr default: %s", c.HTTPAddr)
	}
	if !c.S3UsePathStyle {
		t.Fatal("UsePathStyle default should be true")
	}
	if c.FreeTryOnsPerWeek != 3 {
		t.Fatalf("free try-ons default: %d", c.FreeTryOnsPerWeek)
	}
}
