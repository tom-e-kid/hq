package parser

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/tom-e-kid/hq/tools/hq/internal/model"
)

// Shared recurring regexes (used by both milestones and tasks parsers).
var (
	recurringMonthlyRegex  = regexp.MustCompile(`^- \[([ xX])\] @monthly (\d{1,2}) (.+)$`)
	recurringMonthEndRegex = regexp.MustCompile(`^- \[([ xX])\] @month-end (.+)$`)
	recurringYearlyRegex   = regexp.MustCompile(`^- \[([ xX])\] @yearly (\d{2}-\d{2}) (.+)$`)
	recurringWeeklyRegex   = regexp.MustCompile(`(?i)^- \[([ xX])\] @weekly (mon|tue|wed|thu|fri|sat|sun) (.+)$`)
)

var (
	milestoneDatedRegex   = regexp.MustCompile(`^- \[([ xX])\] (\d{4}-\d{2}-\d{2}) (.+)$`)
	milestoneUndatedRegex = regexp.MustCompile(`^- \[([ xX])\] (.+)$`)
)

// ParseMilestones parses milestone entries from markdown content.
// Iterates over all lines (including frontmatter) to track accurate line numbers.
func ParseMilestones(content string, filePath string, now time.Time) []model.Milestone {
	var milestones []model.Milestone

	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())

	for i, line := range strings.Split(content, "\n") {
		trimmed := strings.TrimSpace(line)
		lineNum := i + 1

		// Try dated format first
		if m := milestoneDatedRegex.FindStringSubmatch(trimmed); m != nil {
			checked := strings.ToLower(m[1]) == "x"
			date, err := time.ParseInLocation("2006-01-02", m[2], now.Location())
			if err == nil {
				remaining := int(date.Sub(today).Hours() / 24)
				if remaining < 0 {
					remaining = 0
				}
				milestones = append(milestones, model.Milestone{
					Content:       m[3],
					Date:          date,
					RemainingDays: remaining,
					Checked:       checked,
					HasDate:       true,
					FilePath:      filePath,
					Line:          lineNum,
				})
				continue
			}
			// Invalid YYYY-MM-DD should fall back to undated handling below.
		}

		// Try recurring formats (before undated)
		if ms, ok := parseRecurringMilestone(trimmed, filePath, lineNum, today); ok {
			milestones = append(milestones, ms)
			continue
		}

		// Undated format
		if m := milestoneUndatedRegex.FindStringSubmatch(trimmed); m != nil {
			checked := strings.ToLower(m[1]) == "x"
			milestones = append(milestones, model.Milestone{
				Content:  m[2],
				Checked:  checked,
				FilePath: filePath,
				Line:     lineNum,
			})
		}
	}
	return milestones
}

// parseRecurringMilestone tries to parse a line as a recurring milestone.
func parseRecurringMilestone(line, filePath string, lineNum int, today time.Time) (model.Milestone, bool) {
	// @monthly N
	if m := recurringMonthlyRegex.FindStringSubmatch(line); m != nil {
		checked := strings.ToLower(m[1]) == "x"
		day := atoi(m[2])
		if day < 1 || day > 31 {
			return model.Milestone{}, false
		}
		date := nextMonthly(day, today)
		remaining := int(date.Sub(today).Hours() / 24)
		return model.Milestone{
			Content:       m[3],
			Date:          date,
			RemainingDays: remaining,
			Checked:       checked,
			HasDate:       true,
			Recurring:     true,
			RecurringRule: "@monthly " + m[2],
			FilePath:      filePath,
			Line:          lineNum,
		}, true
	}

	// @month-end
	if m := recurringMonthEndRegex.FindStringSubmatch(line); m != nil {
		checked := strings.ToLower(m[1]) == "x"
		date := nextMonthEnd(today)
		remaining := int(date.Sub(today).Hours() / 24)
		return model.Milestone{
			Content:       m[2],
			Date:          date,
			RemainingDays: remaining,
			Checked:       checked,
			HasDate:       true,
			Recurring:     true,
			RecurringRule: "@month-end",
			FilePath:      filePath,
			Line:          lineNum,
		}, true
	}

	// @yearly MM-DD
	if m := recurringYearlyRegex.FindStringSubmatch(line); m != nil {
		checked := strings.ToLower(m[1]) == "x"
		parts := strings.Split(m[2], "-")
		month := atoi(parts[0])
		day := atoi(parts[1])
		if month < 1 || month > 12 || day < 1 || day > 31 {
			return model.Milestone{}, false
		}
		date := nextYearly(m[2], today)
		remaining := int(date.Sub(today).Hours() / 24)
		return model.Milestone{
			Content:       m[3],
			Date:          date,
			RemainingDays: remaining,
			Checked:       checked,
			HasDate:       true,
			Recurring:     true,
			RecurringRule: "@yearly " + m[2],
			FilePath:      filePath,
			Line:          lineNum,
		}, true
	}

	// @weekly dow
	if m := recurringWeeklyRegex.FindStringSubmatch(line); m != nil {
		checked := strings.ToLower(m[1]) == "x"
		dow := strings.ToLower(m[2])
		date := nextWeekly(dow, today)
		remaining := int(date.Sub(today).Hours() / 24)
		return model.Milestone{
			Content:       m[3],
			Date:          date,
			RemainingDays: remaining,
			Checked:       checked,
			HasDate:       true,
			Recurring:     true,
			RecurringRule: "@weekly " + dow,
			FilePath:      filePath,
			Line:          lineNum,
		}, true
	}

	return model.Milestone{}, false
}

// MilestoneFilePath returns the path to projects/_milestones.md.
func MilestoneFilePath(basePath string) string {
	return filepath.Join(basePath, "projects", "_milestones.md")
}

// LoadMilestones reads and parses projects/milestones.md.
func LoadMilestones(basePath string, now time.Time) ([]model.Milestone, error) {
	path := MilestoneFilePath(basePath)
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, err
	}
	return ParseMilestones(string(data), path, now), nil
}

// ToggleMilestone toggles a milestone checkbox at the given line in the file.
func ToggleMilestone(filePath string, lineNum int) error {
	return ToggleTask(filePath, lineNum)
}

// AddMilestone appends a new unchecked milestone to the given file.
func AddMilestone(filePath string, text string) error {
	data, err := os.ReadFile(filePath)
	if err != nil {
		if os.IsNotExist(err) {
			return os.WriteFile(filePath, []byte(fmt.Sprintf("- [ ] %s\n", text)), 0644)
		}
		return err
	}
	content := string(data)
	if len(content) > 0 && !strings.HasSuffix(content, "\n") {
		content += "\n"
	}
	content += fmt.Sprintf("- [ ] %s\n", text)
	return os.WriteFile(filePath, []byte(content), 0644)
}
