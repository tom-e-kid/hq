package parser

import (
	"os"
	"path/filepath"
	"testing"
)

func TestCopyNote_File(t *testing.T) {
	tmpDir := t.TempDir()

	// Create source file
	srcFile := filepath.Join(tmpDir, "source.md")
	content := []byte("# Hello\nThis is a test note.\n")
	if err := os.WriteFile(srcFile, content, 0644); err != nil {
		t.Fatal(err)
	}

	// Copy to notes dir
	notesDir := filepath.Join(tmpDir, "notes")
	dest, err := CopyNote(notesDir, srcFile)
	if err != nil {
		t.Fatalf("CopyNote failed: %v", err)
	}

	if filepath.Base(dest) != "source.md" {
		t.Errorf("expected dest basename source.md, got %s", filepath.Base(dest))
	}

	// Verify content
	got, err := os.ReadFile(dest)
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != string(content) {
		t.Errorf("content mismatch: got %q, want %q", got, content)
	}
}

func TestCopyNote_Directory(t *testing.T) {
	tmpDir := t.TempDir()

	// Create source directory with files
	srcDir := filepath.Join(tmpDir, "mydir")
	subDir := filepath.Join(srcDir, "sub")
	if err := os.MkdirAll(subDir, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(srcDir, "a.md"), []byte("file a"), 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(subDir, "b.md"), []byte("file b"), 0644); err != nil {
		t.Fatal(err)
	}

	// Copy to notes dir
	notesDir := filepath.Join(tmpDir, "notes")
	dest, err := CopyNote(notesDir, srcDir)
	if err != nil {
		t.Fatalf("CopyNote failed: %v", err)
	}

	// Verify files exist
	got, err := os.ReadFile(filepath.Join(dest, "a.md"))
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != "file a" {
		t.Errorf("a.md content mismatch: got %q", got)
	}

	got, err = os.ReadFile(filepath.Join(dest, "sub", "b.md"))
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != "file b" {
		t.Errorf("sub/b.md content mismatch: got %q", got)
	}
}

func TestCopyNote_AlreadyExists(t *testing.T) {
	tmpDir := t.TempDir()

	// Create source file
	srcFile := filepath.Join(tmpDir, "existing.md")
	if err := os.WriteFile(srcFile, []byte("content"), 0644); err != nil {
		t.Fatal(err)
	}

	// Create notes dir with same file name
	notesDir := filepath.Join(tmpDir, "notes")
	if err := os.MkdirAll(notesDir, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(notesDir, "existing.md"), []byte("old"), 0644); err != nil {
		t.Fatal(err)
	}

	_, err := CopyNote(notesDir, srcFile)
	if err == nil {
		t.Fatal("expected error for existing file, got nil")
	}
}

func TestCopyNote_SourceNotFound(t *testing.T) {
	tmpDir := t.TempDir()
	notesDir := filepath.Join(tmpDir, "notes")

	_, err := CopyNote(notesDir, filepath.Join(tmpDir, "nonexistent.md"))
	if err == nil {
		t.Fatal("expected error for missing source, got nil")
	}
}
