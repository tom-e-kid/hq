package parser

import (
	"testing"
)

func TestExtractFrontmatter(t *testing.T) {
	content := `---
title: "Test"
purpose: "Testing"
---

Body content here.`

	fm, body, err := ExtractFrontmatter(content)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if fm["title"] != "Test" {
		t.Errorf("expected title 'Test', got %v", fm["title"])
	}
	if fm["purpose"] != "Testing" {
		t.Errorf("expected purpose 'Testing', got %v", fm["purpose"])
	}
	if body != "Body content here." {
		t.Errorf("unexpected body: %q", body)
	}
}

func TestExtractFrontmatter_NoFrontmatter(t *testing.T) {
	content := "Just plain text"
	fm, body, err := ExtractFrontmatter(content)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if fm != nil {
		t.Errorf("expected nil frontmatter, got %v", fm)
	}
	if body != "Just plain text" {
		t.Errorf("unexpected body: %q", body)
	}
}

func TestExtractFrontmatterTyped(t *testing.T) {
	type FM struct {
		Title   string `yaml:"title"`
		Purpose string `yaml:"purpose"`
	}

	content := `---
title: "Test"
purpose: "Testing"
---

Body`

	fm, body, err := ExtractFrontmatterTyped[FM](content)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if fm.Title != "Test" {
		t.Errorf("expected title 'Test', got %q", fm.Title)
	}
	if body != "Body" {
		t.Errorf("unexpected body: %q", body)
	}
}
