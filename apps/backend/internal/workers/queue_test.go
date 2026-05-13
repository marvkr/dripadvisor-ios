package workers

import (
	"context"
	"errors"
	"testing"

	"github.com/riverqueue/river"
)

type fakeGemini struct {
	called bool
	err    error
}

func (f *fakeGemini) ComposeOutfit(_ context.Context, _ ComposeOutfitArgs) ([]byte, error) {
	f.called = true
	if f.err != nil {
		return nil, f.err
	}
	return []byte("pretend-png"), nil
}

func TestComposeOutfitWorker_NoGemini_IsNoop(t *testing.T) {
	w := &ComposeOutfitWorker{}
	job := &river.Job[ComposeOutfitArgs]{Args: ComposeOutfitArgs{OutfitID: "abc"}}
	if err := w.Work(context.Background(), job); err != nil {
		t.Fatalf("want nil err when Gemini unconfigured, got %v", err)
	}
}

func TestComposeOutfitWorker_HappyPath(t *testing.T) {
	fake := &fakeGemini{}
	w := &ComposeOutfitWorker{Gemini: fake}
	job := &river.Job[ComposeOutfitArgs]{Args: ComposeOutfitArgs{
		OutfitID: "abc", ItemIDs: []string{"1", "2"}, Occasion: "rooftop dinner",
	}}
	if err := w.Work(context.Background(), job); err != nil {
		t.Fatalf("want nil err, got %v", err)
	}
	if !fake.called {
		t.Fatal("expected Gemini to be called")
	}
}

func TestComposeOutfitWorker_WrapsGeminiError(t *testing.T) {
	boom := errors.New("gemini down")
	fake := &fakeGemini{err: boom}
	w := &ComposeOutfitWorker{Gemini: fake}
	err := w.Work(context.Background(), &river.Job[ComposeOutfitArgs]{
		Args: ComposeOutfitArgs{OutfitID: "abc"},
	})
	if err == nil {
		t.Fatal("expected error")
	}
	if !errors.Is(err, boom) {
		t.Fatalf("expected wrapped %v, got %v", boom, err)
	}
}

func TestKindsAreUnique(t *testing.T) {
	seen := map[string]bool{}
	kinds := []string{
		ExtractGarmentArgs{}.Kind(),
		IngestBookmarkArgs{}.Kind(),
		ComposeOutfitArgs{}.Kind(),
		StylistReplyArgs{}.Kind(),
		PushSendArgs{}.Kind(),
		AgedMessagePurgeArgs{}.Kind(),
	}
	for _, k := range kinds {
		if seen[k] {
			t.Errorf("duplicate kind: %s", k)
		}
		seen[k] = true
	}
}
