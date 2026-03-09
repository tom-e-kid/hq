package parser

import (
	"os"
	"regexp"
	"strings"

	"github.com/tom-e-kid/hq/tools/cli/internal/config"
	"github.com/tom-e-kid/hq/tools/cli/internal/model"
)

var wipRegex = regexp.MustCompile(`^- (.+?):\s+(.+?)(?:\s+\(branch:\s*(.+?)\))?$`)

// ParseWIP parses WIP task entries from markdown content.
func ParseWIP(content string) []model.WIPEntry {
	var entries []model.WIPEntry
	_, body, _ := ExtractFrontmatter(content)

	for _, line := range strings.Split(body, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		m := wipRegex.FindStringSubmatch(line)
		if m == nil {
			continue
		}
		entries = append(entries, model.WIPEntry{
			Project:     m[1],
			Description: m[2],
			Branch:      m[3],
		})
	}
	return entries
}

// LoadWIP reads and parses ~/.hq/wip.md.
func LoadWIP() ([]model.WIPEntry, error) {
	dir := config.HQDir()
	if dir == "" {
		return nil, nil
	}
	path := dir + "/wip.md"
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, err
	}
	return ParseWIP(string(data)), nil
}
