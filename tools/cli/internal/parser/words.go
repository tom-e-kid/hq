package parser

import (
	"os"
	"path/filepath"
	"strings"
)

// LoadWords reads projects/_words.md and returns top-level bullet lines.
func LoadWords(basePath string) ([]string, error) {
	path := filepath.Join(basePath, "projects", "_words.md")
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, err
	}

	_, body, _ := ExtractFrontmatter(string(data))

	var words []string
	for _, line := range strings.Split(body, "\n") {
		// Only top-level bullets (no leading whitespace)
		if strings.HasPrefix(line, "- ") {
			text := strings.TrimPrefix(line, "- ")
			if text != "" {
				words = append(words, text)
			}
		}
	}
	return words, nil
}
