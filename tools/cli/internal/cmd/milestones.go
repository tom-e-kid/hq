package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/tom-e-kid/hq/tools/cli/internal/parser"
)

func runMilestones(basePath string, args []string) int {
	if len(args) > 0 {
		switch args[0] {
		case "add":
			return runMilestonesAdd(basePath, args[1:])
		case "done":
			return runMilestonesDone(basePath, args[1:])
		}
	}
	return runMilestonesList(basePath, args)
}

func runMilestonesList(basePath string, args []string) int {
	showAll := false
	jsonOut := false
	for _, a := range args {
		switch a {
		case "--all":
			showAll = true
		case "--json":
			jsonOut = true
		}
	}

	now := time.Now()
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())

	if err := parser.MaterializeRecurring(basePath, now); err != nil {
		fmt.Fprintf(os.Stderr, "Warning: %v\n", err)
	}

	milestones, err := parser.LoadMilestones(basePath, now)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		return 1
	}

	if !showAll {
		filtered := milestones[:0]
		for _, m := range milestones {
			if m.HasDate {
				if m.Checked && m.Date.Before(today) {
					continue
				}
			} else if m.Checked {
				continue
			}
			filtered = append(filtered, m)
		}
		milestones = filtered
	}

	if jsonOut {
		enc := json.NewEncoder(os.Stdout)
		enc.SetIndent("", "  ")
		if err := enc.Encode(milestones); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			return 1
		}
		return 0
	}

	if len(milestones) == 0 {
		fmt.Println("No milestones found.")
		return 0
	}

	openCount := 0
	for _, m := range milestones {
		if !m.Checked {
			openCount++
		}
	}
	fmt.Printf("Milestones (%d open)\n", openCount)
	for _, m := range milestones {
		mark := " "
		if m.Checked {
			mark = "x"
		}
		dateStr := ""
		if m.Overdue {
			dateStr = fmt.Sprintf("! %s (%d日超過) ", m.Date.Format("2006-01-02"), -m.RemainingDays)
		} else if m.HasDate {
			dateStr = m.Date.Format("2006-01-02") + " "
			if !m.Checked {
				dateStr += fmt.Sprintf("(%dd) ", m.RemainingDays)
			}
		}
		fmt.Printf("  %3d. [%s] %s%s\n", m.Line, mark, dateStr, m.Content)
	}
	return 0
}

func runMilestonesAdd(basePath string, args []string) int {
	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, "usage: hq milestones add <text>")
		return 1
	}
	text := strings.Join(args, " ")
	filePath := parser.MilestoneFilePath(basePath)

	if err := parser.AddMilestone(filePath, text); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		return 1
	}
	fmt.Printf("Added: %s\n", text)
	return 0
}

func runMilestonesDone(basePath string, args []string) int {
	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, "usage: hq milestones done <line>")
		return 1
	}
	lineNum, err := strconv.Atoi(args[0])
	if err != nil {
		fmt.Fprintf(os.Stderr, "invalid line number: %s\n", args[0])
		return 1
	}

	filePath := parser.MilestoneFilePath(basePath)

	// Read milestone text for confirmation message
	now := time.Now()
	milestones, loadErr := parser.LoadMilestones(basePath, now)
	var msText string
	if loadErr == nil {
		for _, m := range milestones {
			if m.Line == lineNum {
				msText = m.Content
				break
			}
		}
	}

	if err := parser.ToggleMilestone(filePath, lineNum); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		return 1
	}

	if msText != "" {
		fmt.Printf("Done: %s\n", msText)
	} else {
		fmt.Printf("Toggled line %d\n", lineNum)
	}
	return 0
}
