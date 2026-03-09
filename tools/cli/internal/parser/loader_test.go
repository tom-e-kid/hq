package parser

import (
	"os"
	"testing"
	"time"
)

func TestLoadAll_Integration(t *testing.T) {
	// This test runs against the real hq data if available
	basePath := os.Getenv("HQ_PATH")
	if basePath == "" {
		basePath = "/Users/testuser/dev/src/github.com/tom-e-kid/hq/db"
	}

	// Check if the path exists
	if _, err := os.Stat(basePath); os.IsNotExist(err) {
		t.Skip("hq path not available, skipping integration test")
	}

	now := time.Date(2026, 2, 25, 0, 0, 0, 0, time.Local)
	taskFiles := []TaskFileRole{{Name: "tasks.md", Role: "tasks"}}
	data, err := LoadAll(basePath, now, taskFiles)
	if err != nil {
		t.Fatalf("LoadAll failed: %v", err)
	}

	// Milestones
	if len(data.Milestones) == 0 {
		t.Error("expected at least 1 milestone")
	} else {
		t.Logf("Milestones: %d", len(data.Milestones))
		for _, ms := range data.Milestones {
			t.Logf("  - %s (%s, %d days remaining, checked=%v)",
				ms.Content, ms.Date.Format("2006-01-02"), ms.RemainingDays, ms.Checked)
		}
	}

	// WIP
	t.Logf("WIP entries: %d", len(data.WIPEntries))
	for _, w := range data.WIPEntries {
		t.Logf("  - %s: %s (branch: %s)", w.Project, w.Description, w.Branch)
	}

	// Tasks
	if len(data.ProjectTasks) == 0 {
		t.Error("expected at least 1 project with tasks")
	}
	totalOpen := data.TotalOpenTasks()
	t.Logf("Open tasks: %d across %d projects", totalOpen, len(data.ProjectTasks))
	for _, pt := range data.ProjectTasks {
		t.Logf("  - %s/%s: %d open / %d total", pt.Org, pt.Project, pt.OpenCount(), len(pt.Tasks))
	}

	// Monthly
	m := data.Monthly
	t.Logf("Monthly: %s — %.1fh total, %d working days", m.Month, m.TotalHours, m.WorkingDays)
	for _, ch := range m.ClientHours {
		t.Logf("  Client: %s — %.1fh", ch.Client, ch.Hours)
	}
	t.Logf("Daily entries: %d", len(m.DailyEntries))
	for _, d := range m.DailyEntries {
		t.Logf("  - %s: %.1fh", d.Date.Format("2006-01-02"), d.TotalHours)
	}
}
