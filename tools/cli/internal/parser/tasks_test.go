package parser

import (
	"testing"
	"time"
)

var testNow = time.Date(2026, 3, 1, 0, 0, 0, 0, time.Local)

func TestParseTasks(t *testing.T) {
	content := `---
title: "CLIENT_B iOS TODO"
purpose: "test"
---

- [ ] Task one
- [x] Task two done
- [ ] Task three
`

	tasks := ParseTasks(content, "/tmp/test.md", testNow)
	if len(tasks) != 3 {
		t.Fatalf("expected 3 tasks, got %d", len(tasks))
	}

	if tasks[0].Text != "Task one" || tasks[0].Checked {
		t.Errorf("task 0: got %+v", tasks[0])
	}
	if tasks[0].Line != 6 {
		t.Errorf("task 0 line: expected 6, got %d", tasks[0].Line)
	}
	if tasks[1].Text != "Task two done" || !tasks[1].Checked {
		t.Errorf("task 1: got %+v", tasks[1])
	}
	if tasks[2].Text != "Task three" || tasks[2].Checked {
		t.Errorf("task 2: got %+v", tasks[2])
	}
	if tasks[2].FilePath != "/tmp/test.md" {
		t.Errorf("task 2 filePath: got %q", tasks[2].FilePath)
	}
	// Undated tasks should have HasDate=false
	if tasks[0].HasDate {
		t.Errorf("task 0: expected HasDate=false")
	}
}

func TestParseTasks_NoFrontmatter(t *testing.T) {
	content := `- [ ] Simple task
- [X] Done task
`

	tasks := ParseTasks(content, "", testNow)
	if len(tasks) != 2 {
		t.Fatalf("expected 2 tasks, got %d", len(tasks))
	}
	if !tasks[1].Checked {
		t.Error("expected uppercase X to be checked")
	}
	if tasks[0].Line != 1 {
		t.Errorf("task 0 line: expected 1, got %d", tasks[0].Line)
	}
}

func TestParseTasks_Empty(t *testing.T) {
	tasks := ParseTasks("", "", testNow)
	if len(tasks) != 0 {
		t.Errorf("expected 0 tasks, got %d", len(tasks))
	}
}

func TestParseTasks_Dated(t *testing.T) {
	content := `- [ ] 2026-03-15 Submit report
- [x] 2026-02-28 Past deadline
- [ ] 2026-03-01 Due today
`
	tasks := ParseTasks(content, "/tmp/dated.md", testNow)
	if len(tasks) != 3 {
		t.Fatalf("expected 3 tasks, got %d", len(tasks))
	}

	// Task with future date
	if tasks[0].Text != "Submit report" {
		t.Errorf("task 0 text: got %q", tasks[0].Text)
	}
	if !tasks[0].HasDate {
		t.Error("task 0: expected HasDate=true")
	}
	if tasks[0].RemainingDays != 14 {
		t.Errorf("task 0 remaining: expected 14, got %d", tasks[0].RemainingDays)
	}
	if tasks[0].Date.Format("2006-01-02") != "2026-03-15" {
		t.Errorf("task 0 date: got %s", tasks[0].Date.Format("2006-01-02"))
	}

	// Past deadline should clamp to 0
	if tasks[1].RemainingDays != 0 {
		t.Errorf("task 1 remaining: expected 0, got %d", tasks[1].RemainingDays)
	}

	// Due today
	if tasks[2].RemainingDays != 0 {
		t.Errorf("task 2 remaining: expected 0, got %d", tasks[2].RemainingDays)
	}
}

func TestParseTasks_Monthly(t *testing.T) {
	content := `- [ ] @monthly 10 Pay invoice
`
	tasks := ParseTasks(content, "", testNow)
	if len(tasks) != 1 {
		t.Fatalf("expected 1 task, got %d", len(tasks))
	}
	task := tasks[0]
	if task.Text != "Pay invoice" {
		t.Errorf("text: got %q", task.Text)
	}
	if !task.HasDate || !task.Recurring {
		t.Error("expected HasDate=true, Recurring=true")
	}
	if task.RecurringRule != "@monthly 10" {
		t.Errorf("rule: got %q", task.RecurringRule)
	}
	if task.Date.Format("2006-01-02") != "2026-03-10" {
		t.Errorf("date: got %s", task.Date.Format("2006-01-02"))
	}
	if task.RemainingDays != 9 {
		t.Errorf("remaining: expected 9, got %d", task.RemainingDays)
	}
}

func TestParseTasks_MonthEnd(t *testing.T) {
	content := `- [ ] @month-end Monthly billing
`
	tasks := ParseTasks(content, "", testNow)
	if len(tasks) != 1 {
		t.Fatalf("expected 1 task, got %d", len(tasks))
	}
	task := tasks[0]
	if task.Text != "Monthly billing" {
		t.Errorf("text: got %q", task.Text)
	}
	if !task.Recurring || task.RecurringRule != "@month-end" {
		t.Errorf("recurring: got %v, rule: %q", task.Recurring, task.RecurringRule)
	}
	if task.Date.Format("2006-01-02") != "2026-03-31" {
		t.Errorf("date: got %s", task.Date.Format("2006-01-02"))
	}
}

func TestParseTasks_Yearly(t *testing.T) {
	content := `- [ ] @yearly 03-15 Tax filing
`
	tasks := ParseTasks(content, "", testNow)
	if len(tasks) != 1 {
		t.Fatalf("expected 1 task, got %d", len(tasks))
	}
	task := tasks[0]
	if task.Text != "Tax filing" {
		t.Errorf("text: got %q", task.Text)
	}
	if !task.Recurring || task.RecurringRule != "@yearly 03-15" {
		t.Errorf("recurring: got %v, rule: %q", task.Recurring, task.RecurringRule)
	}
	if task.Date.Format("2006-01-02") != "2026-03-15" {
		t.Errorf("date: got %s", task.Date.Format("2006-01-02"))
	}
}

func TestParseTasks_Weekly(t *testing.T) {
	// 2026-03-01 is a Sunday
	content := `- [ ] @weekly mon Team standup
`
	tasks := ParseTasks(content, "", testNow)
	if len(tasks) != 1 {
		t.Fatalf("expected 1 task, got %d", len(tasks))
	}
	task := tasks[0]
	if task.Text != "Team standup" {
		t.Errorf("text: got %q", task.Text)
	}
	if !task.Recurring || task.RecurringRule != "@weekly mon" {
		t.Errorf("recurring: got %v, rule: %q", task.Recurring, task.RecurringRule)
	}
	// Next Monday after Sunday 2026-03-01 is 2026-03-02
	if task.Date.Format("2006-01-02") != "2026-03-02" {
		t.Errorf("date: got %s", task.Date.Format("2006-01-02"))
	}
	if task.RemainingDays != 1 {
		t.Errorf("remaining: expected 1, got %d", task.RemainingDays)
	}
}

func TestParseTasks_InvalidRecurringFallsBackToUndated(t *testing.T) {
	content := `- [ ] @monthly 0 Invalid day zero
- [ ] @monthly 32 Invalid day 32
- [ ] @yearly 13-01 Invalid month
- [ ] @yearly 00-15 Invalid month zero
`
	tasks := ParseTasks(content, "", testNow)
	if len(tasks) != 4 {
		t.Fatalf("expected 4 tasks, got %d", len(tasks))
	}
	for i, task := range tasks {
		if task.Recurring {
			t.Errorf("task %d: expected Recurring=false for invalid input", i)
		}
		if task.HasDate {
			t.Errorf("task %d: expected HasDate=false for invalid input", i)
		}
	}
}

func TestParseTasks_InvalidDatedFallsBackToUndated(t *testing.T) {
	content := `- [ ] 2026-02-31 Invalid calendar date
`
	tasks := ParseTasks(content, "", testNow)
	if len(tasks) != 1 {
		t.Fatalf("expected 1 task, got %d", len(tasks))
	}
	task := tasks[0]
	if task.HasDate {
		t.Error("expected HasDate=false for invalid dated input")
	}
	if task.Recurring {
		t.Error("expected Recurring=false for invalid dated input")
	}
	if task.Text != "2026-02-31 Invalid calendar date" {
		t.Errorf("unexpected text: %q", task.Text)
	}
}

func TestParseTasks_MixedFormats(t *testing.T) {
	content := `- [ ] 2026-03-10 Dated task
- [ ] @monthly 15 Recurring task
- [ ] Undated task
- [x] @weekly fri Weekly done
`
	tasks := ParseTasks(content, "/tmp/mixed.md", testNow)
	if len(tasks) != 4 {
		t.Fatalf("expected 4 tasks, got %d", len(tasks))
	}

	// Dated
	if !tasks[0].HasDate || tasks[0].Recurring {
		t.Errorf("task 0: expected dated non-recurring")
	}
	if tasks[0].Text != "Dated task" {
		t.Errorf("task 0 text: got %q", tasks[0].Text)
	}

	// Recurring
	if !tasks[1].HasDate || !tasks[1].Recurring {
		t.Errorf("task 1: expected dated recurring")
	}
	if tasks[1].Text != "Recurring task" {
		t.Errorf("task 1 text: got %q", tasks[1].Text)
	}

	// Undated
	if tasks[2].HasDate || tasks[2].Recurring {
		t.Errorf("task 2: expected undated")
	}
	if tasks[2].Text != "Undated task" {
		t.Errorf("task 2 text: got %q", tasks[2].Text)
	}

	// Checked recurring
	if !tasks[3].Checked || !tasks[3].Recurring {
		t.Errorf("task 3: expected checked recurring")
	}
}
