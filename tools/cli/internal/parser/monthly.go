package parser

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/tom-e-kid/hq/tools/cli/internal/model"
)

type monthlyFrontmatter struct {
	Month   string `yaml:"month"`
	Summary string `yaml:"summary"`
}

var (
	dailyHeadingRegex = regexp.MustCompile(`^## (\d{8})$`)
	timeEntryRegex    = regexp.MustCompile(`^- (.+?):(.+?):\s*(\d+[.,]\d+|\d+)$`)
)

// ParseMonthly parses a monthly log file.
func ParseMonthly(content string) (model.MonthlyData, error) {
	fm, body, err := ExtractFrontmatterTyped[monthlyFrontmatter](content)
	if err != nil {
		return model.MonthlyData{}, err
	}

	data := model.MonthlyData{
		Month:   stripSmartQuotes(fm.Month),
		Summary: strings.TrimSpace(fm.Summary),
	}

	// Calculate hours from daily entries instead of frontmatter
	entries := parseDailyEntries(body)
	data.DailyEntries = entries

	var totalHours float64
	clientOrder := []string{}
	clientMap := map[string]float64{}
	workingDays := 0
	for _, e := range entries {
		if e.TotalHours > 0 {
			workingDays++
		}
		for _, te := range e.TimeEntries {
			totalHours += te.Hours
			if _, exists := clientMap[te.Client]; !exists {
				clientOrder = append(clientOrder, te.Client)
			}
			clientMap[te.Client] += te.Hours
		}
	}
	data.TotalHours = totalHours
	for _, c := range clientOrder {
		data.ClientHours = append(data.ClientHours, model.ClientHours{
			Client: c,
			Hours:  clientMap[c],
		})
	}
	data.WorkingDays = workingDays

	return data, nil
}

func parseDailyEntries(body string) []model.DailyEntry {
	var entries []model.DailyEntry
	lines := strings.Split(body, "\n")

	var currentEntry *model.DailyEntry
	inTSection := false

	for _, line := range lines {
		trimmed := strings.TrimSpace(line)

		// Check for daily heading
		if m := dailyHeadingRegex.FindStringSubmatch(trimmed); m != nil {
			// Save previous entry
			if currentEntry != nil {
				currentEntry.TotalHours = sumTimeEntries(currentEntry.TimeEntries)
				entries = append(entries, *currentEntry)
			}
			date, err := time.Parse("20060102", m[1])
			if err != nil {
				continue
			}
			currentEntry = &model.DailyEntry{Date: date}
			inTSection = false
			continue
		}

		if currentEntry == nil {
			continue
		}

		// Detect T: section
		if trimmed == "T:" {
			inTSection = true
			continue
		}

		// Other top-level sections end the T section
		if len(trimmed) > 0 && !strings.HasPrefix(trimmed, "-") && !strings.HasPrefix(trimmed, "#") && strings.HasSuffix(trimmed, ":") {
			inTSection = false
			continue
		}

		// Parse time entries within T section (only top-level, non-indented lines)
		if inTSection && strings.HasPrefix(line, "- ") {
			if m := timeEntryRegex.FindStringSubmatch(trimmed); m != nil {
				hours := parseHours(m[3])
				currentEntry.TimeEntries = append(currentEntry.TimeEntries, model.TimeEntry{
					Client:   strings.TrimSpace(m[1]),
					Category: strings.TrimSpace(m[2]),
					Hours:    hours,
				})
			}
		}
	}

	// Don't forget the last entry
	if currentEntry != nil {
		currentEntry.TotalHours = sumTimeEntries(currentEntry.TimeEntries)
		entries = append(entries, *currentEntry)
	}

	return entries
}

// stripSmartQuotes removes Unicode smart quotes (U+201C, U+201D) that may
// leak into YAML values when editors auto-replace straight quotes.
func stripSmartQuotes(s string) string {
	s = strings.ReplaceAll(s, "\u201c", "")
	s = strings.ReplaceAll(s, "\u201d", "")
	return strings.TrimSpace(s)
}

func parseHours(s string) float64 {
	// Handle comma decimal separator (e.g., "1,5" -> 1.5)
	s = strings.Replace(s, ",", ".", 1)
	v, err := strconv.ParseFloat(s, 64)
	if err != nil {
		return 0
	}
	return v
}

func sumTimeEntries(entries []model.TimeEntry) float64 {
	total := 0.0
	for _, e := range entries {
		total += e.Hours
	}
	return total
}

// LoadMonthly reads and parses the monthly log for the given time.
func LoadMonthly(basePath string, t time.Time) (model.MonthlyData, error) {
	path := filepath.Join(basePath, "logs", fmt.Sprintf("%d", t.Year()), fmt.Sprintf("%02d.md", t.Month()))
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return model.MonthlyData{}, nil
		}
		return model.MonthlyData{}, err
	}
	return ParseMonthly(string(data))
}

// LoadAllMonthly discovers and loads all monthly log files, sorted chronologically.
func LoadAllMonthly(basePath string) ([]model.MonthlyData, error) {
	logsDir := filepath.Join(basePath, "logs")
	yearDirs, err := os.ReadDir(logsDir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, err
	}

	var all []model.MonthlyData
	for _, yd := range yearDirs {
		if !yd.IsDir() {
			continue
		}
		yearPath := filepath.Join(logsDir, yd.Name())
		files, err := os.ReadDir(yearPath)
		if err != nil {
			continue
		}
		for _, f := range files {
			if f.IsDir() || !strings.HasSuffix(f.Name(), ".md") {
				continue
			}
			raw, err := os.ReadFile(filepath.Join(yearPath, f.Name()))
			if err != nil {
				continue
			}
			monthly, err := ParseMonthly(string(raw))
			if err != nil || monthly.Month == "" {
				continue
			}
			all = append(all, monthly)
		}
	}

	sort.Slice(all, func(i, j int) bool {
		mi := strings.ReplaceAll(all[i].Month, "\u2011", "-")
		mj := strings.ReplaceAll(all[j].Month, "\u2011", "-")
		return mi < mj
	})

	return all, nil
}
