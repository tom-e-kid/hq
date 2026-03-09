package parser

import (
	"testing"
)

func TestParseWIP(t *testing.T) {
	content := `---
purpose: Track in-progress tasks
summary: Active WIP entries
---

- acme/webapp: Add Mock/API tabs and editable Raw JSON (branch: feature/mock-tab-and-json-editor)
- client_a/dashboard: Some task (branch: feature/some-thing)
- solo/project: No branch task
`

	entries := ParseWIP(content)
	if len(entries) != 3 {
		t.Fatalf("expected 3 entries, got %d", len(entries))
	}

	e := entries[0]
	if e.Project != "acme/webapp" {
		t.Errorf("unexpected project: %q", e.Project)
	}
	if e.Description != "Add Mock/API tabs and editable Raw JSON" {
		t.Errorf("unexpected description: %q", e.Description)
	}
	if e.Branch != "feature/mock-tab-and-json-editor" {
		t.Errorf("unexpected branch: %q", e.Branch)
	}

	e3 := entries[2]
	if e3.Branch != "" {
		t.Errorf("expected empty branch, got %q", e3.Branch)
	}
}
