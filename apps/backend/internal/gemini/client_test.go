package gemini

import (
	"strings"
	"testing"
)

func TestBuildPrompt_ContainsRequiredFrames(t *testing.T) {
	p := buildPrompt("rooftop dinner", 3)
	for _, needle := range []string{
		"fashion photographer",
		"3 garments",
		"rooftop dinner",
		"Preserve the person",
		"No logos added",
	} {
		if !strings.Contains(p, needle) {
			t.Errorf("prompt missing %q:\n%s", needle, p)
		}
	}
}

func TestBuildPrompt_OmitsOccasionWhenEmpty(t *testing.T) {
	p := buildPrompt("", 2)
	if strings.Contains(p, "Setting:") {
		t.Errorf("expected no Setting when occasion empty, got:\n%s", p)
	}
}

func TestNew_RejectsEmptyKey(t *testing.T) {
	_, err := New(t.Context(), "")
	if err == nil {
		t.Fatal("expected error for empty api key")
	}
}
