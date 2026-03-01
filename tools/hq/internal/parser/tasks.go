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

var (
	taskDatedRegex   = regexp.MustCompile(`^- \[([ xX])\] (\d{4}-\d{2}-\d{2}) (.+)$`)
	taskUndatedRegex = regexp.MustCompile(`^- \[([ xX])\] (.+)$`)
)

// ParseTasks parses checkbox tasks from markdown content.
// filePath is stored on each task for write-back support.
func ParseTasks(content string, filePath string, now time.Time) []model.Task {
	var tasks []model.Task
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())

	for i, line := range strings.Split(content, "\n") {
		trimmed := strings.TrimSpace(line)
		lineNum := i + 1

		// Try dated format first
		if m := taskDatedRegex.FindStringSubmatch(trimmed); m != nil {
			checked := strings.ToLower(m[1]) == "x"
			date, err := time.ParseInLocation("2006-01-02", m[2], now.Location())
			if err == nil {
				remaining := int(date.Sub(today).Hours() / 24)
				if remaining < 0 {
					remaining = 0
				}
				tasks = append(tasks, model.Task{
					Text:          m[3],
					Checked:       checked,
					Date:          date,
					RemainingDays: remaining,
					HasDate:       true,
					FilePath:      filePath,
					Line:          lineNum,
				})
				continue
			}
			// Invalid YYYY-MM-DD should fall back to undated handling below.
		}

		// Try recurring formats (before undated)
		if t, ok := parseRecurringTask(trimmed, filePath, lineNum, today); ok {
			tasks = append(tasks, t)
			continue
		}

		// Undated format
		if m := taskUndatedRegex.FindStringSubmatch(trimmed); m != nil {
			checked := strings.ToLower(m[1]) == "x"
			tasks = append(tasks, model.Task{
				Text:     m[2],
				Checked:  checked,
				FilePath: filePath,
				Line:     lineNum,
			})
		}
	}
	return tasks
}

// parseRecurringTask tries to parse a line as a recurring task.
func parseRecurringTask(line, filePath string, lineNum int, today time.Time) (model.Task, bool) {
	// @monthly N
	if m := recurringMonthlyRegex.FindStringSubmatch(line); m != nil {
		checked := strings.ToLower(m[1]) == "x"
		day := atoi(m[2])
		if day < 1 || day > 31 {
			return model.Task{}, false
		}
		date := nextMonthly(day, today)
		remaining := int(date.Sub(today).Hours() / 24)
		return model.Task{
			Text:          m[3],
			Checked:       checked,
			Date:          date,
			RemainingDays: remaining,
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
		return model.Task{
			Text:          m[2],
			Checked:       checked,
			Date:          date,
			RemainingDays: remaining,
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
			return model.Task{}, false
		}
		date := nextYearly(m[2], today)
		remaining := int(date.Sub(today).Hours() / 24)
		return model.Task{
			Text:          m[3],
			Checked:       checked,
			Date:          date,
			RemainingDays: remaining,
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
		return model.Task{
			Text:          m[3],
			Checked:       checked,
			Date:          date,
			RemainingDays: remaining,
			HasDate:       true,
			Recurring:     true,
			RecurringRule: "@weekly " + dow,
			FilePath:      filePath,
			Line:          lineNum,
		}, true
	}

	return model.Task{}, false
}

// ToggleTask toggles a checkbox at the given line in the file.
func ToggleTask(filePath string, lineNum int) error {
	data, err := os.ReadFile(filePath)
	if err != nil {
		return err
	}
	lines := strings.Split(string(data), "\n")
	if lineNum < 1 || lineNum > len(lines) {
		return fmt.Errorf("line %d out of range", lineNum)
	}
	target := lines[lineNum-1]
	switch {
	case strings.Contains(target, "- [ ]"):
		lines[lineNum-1] = strings.Replace(target, "- [ ]", "- [x]", 1)
	case strings.Contains(target, "- [x]"):
		lines[lineNum-1] = strings.Replace(target, "- [x]", "- [ ]", 1)
	case strings.Contains(target, "- [X]"):
		lines[lineNum-1] = strings.Replace(target, "- [X]", "- [ ]", 1)
	}
	return os.WriteFile(filePath, []byte(strings.Join(lines, "\n")), 0644)
}

// AddTask appends a new unchecked task to the given file.
func AddTask(filePath string, text string) error {
	data, err := os.ReadFile(filePath)
	if err != nil {
		if os.IsNotExist(err) {
			if err := os.MkdirAll(filepath.Dir(filePath), 0755); err != nil {
				return err
			}
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

// TaskFileRole pairs a filename with its resource role.
type TaskFileRole struct {
	Name string // e.g. "tasks.md"
	Role string // e.g. "tasks", "backlog"
}

// LoadProjectTasks discovers and parses all project task files under basePath/projects/.
// taskFile is the filename to look for (e.g. "tasks.md").
func LoadProjectTasks(basePath string, taskFile string, now time.Time) ([]model.ProjectTasks, error) {
	return LoadProjectTasksWithRole(basePath, taskFile, "", now)
}

// LoadProjectTasksWithRole discovers and parses project task files, setting the role on each.
func LoadProjectTasksWithRole(basePath string, taskFile string, role string, now time.Time) ([]model.ProjectTasks, error) {
	pattern := filepath.Join(basePath, "projects", "*", "*", taskFile)
	matches, err := filepath.Glob(pattern)
	if err != nil {
		return nil, err
	}

	var result []model.ProjectTasks
	for _, path := range matches {
		data, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		tasks := ParseTasks(string(data), path, now)
		if len(tasks) == 0 {
			continue
		}

		// Extract org/project from path: .../projects/{org}/{project}/<taskFile>
		rel, _ := filepath.Rel(filepath.Join(basePath, "projects"), path)
		parts := strings.Split(rel, string(filepath.Separator))
		if len(parts) < 3 {
			continue
		}
		org := parts[0]
		project := parts[1]

		result = append(result, model.ProjectTasks{
			Org:     org,
			Project: project,
			Role:    role,
			Tasks:   tasks,
		})
	}
	return result, nil
}

// LoadAllProjectTasks loads tasks from multiple task files, merging the results.
func LoadAllProjectTasks(basePath string, taskFiles []TaskFileRole, now time.Time) ([]model.ProjectTasks, error) {
	var all []model.ProjectTasks
	for _, tf := range taskFiles {
		pts, err := LoadProjectTasksWithRole(basePath, tf.Name, tf.Role, now)
		if err != nil {
			return nil, err
		}
		all = append(all, pts...)
	}
	return all, nil
}
