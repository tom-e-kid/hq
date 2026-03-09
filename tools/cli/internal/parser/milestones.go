package parser

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"

	"github.com/tom-e-kid/hq/tools/cli/internal/model"
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

// Template regexes — checkbox-less recurring rules.
var (
	templateMonthlyRegex  = regexp.MustCompile(`^- @monthly (\d{1,2}) (.+)$`)
	templateMonthEndRegex = regexp.MustCompile(`^- @month-end (.+)$`)
	templateYearlyRegex   = regexp.MustCompile(`^- @yearly (\d{2}-\d{2}) (.+)$`)
	templateWeeklyRegex   = regexp.MustCompile(`(?i)^- @weekly (mon|tue|wed|thu|fri|sat|sun) (.+)$`)
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
				milestones = append(milestones, model.Milestone{
					Content:       m[3],
					Date:          date,
					RemainingDays: remaining,
					Checked:       checked,
					Overdue:       !checked && remaining < 0,
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
	milestones := ParseMilestones(string(data), path, now)
	SortMilestones(milestones)
	return milestones, nil
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

// SortMilestones sorts milestones: overdue first (date asc), then upcoming dated (date asc), then undated (file order).
func SortMilestones(milestones []model.Milestone) {
	sort.SliceStable(milestones, func(i, j int) bool {
		mi, mj := milestones[i], milestones[j]
		ci, cj := milestoneCategory(mi), milestoneCategory(mj)
		if ci != cj {
			return ci < cj
		}
		if mi.HasDate && mj.HasDate {
			return mi.Date.Before(mj.Date)
		}
		return false
	})
}

// milestoneCategory returns sort priority: 0=overdue, 1=dated, 2=undated.
func milestoneCategory(m model.Milestone) int {
	if m.Overdue {
		return 0
	}
	if m.HasDate {
		return 1
	}
	return 2
}

// recurringTemplate represents a checkbox-less recurring rule.
type recurringTemplate struct {
	ruleType string // "monthly", "month-end", "yearly", "weekly"
	param    string // day number, "", "MM-DD", weekday
	content  string
}

// ParseRecurringTemplates extracts checkbox-less recurring templates from content.
func ParseRecurringTemplates(content string) []recurringTemplate {
	var templates []recurringTemplate
	for _, line := range strings.Split(content, "\n") {
		trimmed := strings.TrimSpace(line)
		if m := templateMonthlyRegex.FindStringSubmatch(trimmed); m != nil {
			day := atoi(m[1])
			if day >= 1 && day <= 31 {
				templates = append(templates, recurringTemplate{
					ruleType: "monthly", param: m[1], content: m[2],
				})
			}
		} else if m := templateMonthEndRegex.FindStringSubmatch(trimmed); m != nil {
			templates = append(templates, recurringTemplate{
				ruleType: "month-end", content: m[1],
			})
		} else if m := templateYearlyRegex.FindStringSubmatch(trimmed); m != nil {
			parts := strings.Split(m[1], "-")
			month, day := atoi(parts[0]), atoi(parts[1])
			if month >= 1 && month <= 12 && day >= 1 && day <= 31 {
				templates = append(templates, recurringTemplate{
					ruleType: "yearly", param: m[1], content: m[2],
				})
			}
		} else if m := templateWeeklyRegex.FindStringSubmatch(trimmed); m != nil {
			templates = append(templates, recurringTemplate{
				ruleType: "weekly", param: strings.ToLower(m[1]), content: m[2],
			})
		}
	}
	return templates
}

// templateNextDate computes the next occurrence date for a recurring template.
func templateNextDate(tmpl recurringTemplate, today time.Time) time.Time {
	switch tmpl.ruleType {
	case "monthly":
		return nextMonthly(atoi(tmpl.param), today)
	case "month-end":
		return nextMonthEnd(today)
	case "yearly":
		return nextYearly(tmpl.param, today)
	case "weekly":
		return nextWeekly(tmpl.param, today)
	default:
		return today
	}
}

// MaterializeRecurring reads _milestones.md, generates concrete dated instances
// from recurring templates, and appends any missing instances to the file.
func MaterializeRecurring(basePath string, now time.Time) error {
	path := MilestoneFilePath(basePath)
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	content := string(data)

	templates := ParseRecurringTemplates(content)
	if len(templates) == 0 {
		return nil
	}

	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())

	// Collect existing dated lines for deduplication
	existing := make(map[string]bool)
	for _, line := range strings.Split(content, "\n") {
		trimmed := strings.TrimSpace(line)
		if m := milestoneDatedRegex.FindStringSubmatch(trimmed); m != nil {
			existing[m[2]+" "+m[3]] = true
		}
	}

	var toAppend []string
	for _, tmpl := range templates {
		date := templateNextDate(tmpl, today)
		dateStr := date.Format("2006-01-02")
		key := dateStr + " " + tmpl.content
		if !existing[key] {
			toAppend = append(toAppend, fmt.Sprintf("- [ ] %s %s", dateStr, tmpl.content))
			existing[key] = true
		}
	}

	if len(toAppend) == 0 {
		return nil
	}

	if !strings.HasSuffix(content, "\n") {
		content += "\n"
	}
	content += strings.Join(toAppend, "\n") + "\n"
	return os.WriteFile(path, []byte(content), 0644)
}
