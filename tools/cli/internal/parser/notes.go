package parser

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/tom-e-kid/hq/tools/cli/internal/model"
)

// ListNotes discovers .md files in the given directories and extracts frontmatter.
func ListNotes(notesDirs []string) ([]model.NoteInfo, error) {
	var notes []model.NoteInfo
	for _, dir := range notesDirs {
		dirName := filepath.Base(dir)
		pattern := filepath.Join(dir, "*.md")
		matches, err := filepath.Glob(pattern)
		if err != nil {
			continue
		}
		for _, path := range matches {
			data, err := os.ReadFile(path)
			if err != nil {
				continue
			}
			fm, _, err := ExtractFrontmatter(string(data))
			if err != nil || fm == nil {
				continue
			}

			info := model.NoteInfo{
				FileName: filepath.Base(path),
				Dir:      dirName,
			}
			if t, ok := fm["title"].(string); ok {
				info.Title = t
			}
			if d, ok := fm["date"].(string); ok {
				info.Date = d
			}
			if s, ok := fm["summary"].(string); ok {
				info.Summary = s
			}
			if tags, ok := fm["tags"].([]interface{}); ok {
				for _, tag := range tags {
					if s, ok := tag.(string); ok {
						info.Tags = append(info.Tags, s)
					}
				}
			}
			notes = append(notes, info)
		}
	}
	return notes, nil
}

// CreateNote writes a new note file with frontmatter and body.
// Returns the path of the created file.
func CreateNote(notesDir, title, body string, tags []string, date time.Time) (string, error) {
	if err := os.MkdirAll(notesDir, 0755); err != nil {
		return "", err
	}

	fileName := toKebabCase(title) + ".md"
	path := filepath.Join(notesDir, fileName)

	var sb strings.Builder
	sb.WriteString("---\n")
	sb.WriteString(fmt.Sprintf("title: %q\n", title))
	sb.WriteString(fmt.Sprintf("date: %s\n", date.Format("2006-01-02")))
	if len(tags) > 0 {
		sb.WriteString("tags:\n")
		for _, tag := range tags {
			sb.WriteString(fmt.Sprintf("  - %s\n", tag))
		}
	}
	sb.WriteString("---\n\n")
	sb.WriteString(body)
	if !strings.HasSuffix(body, "\n") {
		sb.WriteString("\n")
	}

	return path, os.WriteFile(path, []byte(sb.String()), 0644)
}

func toKebabCase(s string) string {
	s = strings.ToLower(s)
	s = strings.Map(func(r rune) rune {
		if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') || r == '-' {
			return r
		}
		return '-'
	}, s)
	// Collapse multiple dashes
	for strings.Contains(s, "--") {
		s = strings.ReplaceAll(s, "--", "-")
	}
	return strings.Trim(s, "-")
}
