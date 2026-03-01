package parser

import (
	"strings"

	"gopkg.in/yaml.v3"
)

// ExtractFrontmatter splits a markdown file into YAML frontmatter and body.
// Returns the parsed frontmatter map and the remaining body text.
func ExtractFrontmatter(content string) (map[string]interface{}, string, error) {
	content = strings.TrimSpace(content)
	if !strings.HasPrefix(content, "---") {
		return nil, content, nil
	}

	// Find closing ---
	rest := content[3:]
	idx := strings.Index(rest, "\n---")
	if idx < 0 {
		return nil, content, nil
	}

	yamlStr := rest[:idx]
	body := strings.TrimSpace(rest[idx+4:])

	var fm map[string]interface{}
	if err := yaml.Unmarshal([]byte(yamlStr), &fm); err != nil {
		return nil, content, err
	}

	return fm, body, nil
}

// ExtractFrontmatterTyped parses frontmatter into a typed struct.
func ExtractFrontmatterTyped[T any](content string) (*T, string, error) {
	content = strings.TrimSpace(content)
	if !strings.HasPrefix(content, "---") {
		var zero T
		return &zero, content, nil
	}

	rest := content[3:]
	idx := strings.Index(rest, "\n---")
	if idx < 0 {
		var zero T
		return &zero, content, nil
	}

	yamlStr := rest[:idx]
	body := strings.TrimSpace(rest[idx+4:])

	var result T
	if err := yaml.Unmarshal([]byte(yamlStr), &result); err != nil {
		return nil, content, err
	}

	return &result, body, nil
}
