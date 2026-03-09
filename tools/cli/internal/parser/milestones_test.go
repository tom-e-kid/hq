package parser

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestParseMilestones(t *testing.T) {
	content := `---
title: "マイルストーン"
purpose: "test"
---

- [ ] 2026-03-05 project_b 5.0.0 リリース
- [x] 2026-02-01 some past milestone
`

	now := time.Date(2026, 2, 25, 0, 0, 0, 0, time.UTC)
	milestones := ParseMilestones(content, "test/milestones.md", now)

	if len(milestones) != 2 {
		t.Fatalf("expected 2 milestones, got %d", len(milestones))
	}

	ms := milestones[0]
	if ms.Content != "project_b 5.0.0 リリース" {
		t.Errorf("unexpected content: %q", ms.Content)
	}
	if ms.Checked {
		t.Error("expected unchecked")
	}
	if ms.RemainingDays != 8 {
		t.Errorf("expected 8 remaining days, got %d", ms.RemainingDays)
	}
	if ms.Overdue {
		t.Error("expected overdue=false for future milestone")
	}
	if ms.FilePath != "test/milestones.md" {
		t.Errorf("unexpected file path: %q", ms.FilePath)
	}
	if ms.Line != 6 {
		t.Errorf("expected line 6, got %d", ms.Line)
	}

	ms2 := milestones[1]
	if !ms2.Checked {
		t.Error("expected checked")
	}
	if ms2.RemainingDays >= 0 {
		t.Errorf("expected negative remaining days for past milestone, got %d", ms2.RemainingDays)
	}
	if ms2.Overdue {
		t.Error("expected overdue=false for checked past milestone")
	}
	if ms2.Line != 7 {
		t.Errorf("expected line 7, got %d", ms2.Line)
	}
}

func TestParseMilestones_Overdue(t *testing.T) {
	content := `- [ ] 2026-03-01 overdue task
- [x] 2026-03-01 done past task
- [ ] 2026-03-10 upcoming task
`
	now := time.Date(2026, 3, 5, 0, 0, 0, 0, time.UTC)
	milestones := ParseMilestones(content, "test.md", now)

	if len(milestones) != 3 {
		t.Fatalf("expected 3 milestones, got %d", len(milestones))
	}

	// Overdue unchecked
	if !milestones[0].Overdue {
		t.Error("expected overdue=true for unchecked past milestone")
	}
	if milestones[0].RemainingDays != -4 {
		t.Errorf("expected -4 remaining days, got %d", milestones[0].RemainingDays)
	}

	// Checked past — not overdue
	if milestones[1].Overdue {
		t.Error("expected overdue=false for checked past milestone")
	}

	// Future — not overdue
	if milestones[2].Overdue {
		t.Error("expected overdue=false for future milestone")
	}
	if milestones[2].RemainingDays != 5 {
		t.Errorf("expected 5 remaining days, got %d", milestones[2].RemainingDays)
	}
}

func TestParseRecurringMonthly(t *testing.T) {
	content := `- [ ] @monthly 10 任意健康保険期限`

	// now = March 1 → next occurrence is March 10
	now := time.Date(2026, 3, 1, 0, 0, 0, 0, time.UTC)
	milestones := ParseMilestones(content, "test.md", now)

	if len(milestones) != 1 {
		t.Fatalf("expected 1 milestone, got %d", len(milestones))
	}
	ms := milestones[0]
	if !ms.Recurring {
		t.Error("expected recurring=true")
	}
	if ms.RecurringRule != "@monthly 10" {
		t.Errorf("unexpected rule: %q", ms.RecurringRule)
	}
	if ms.Content != "任意健康保険期限" {
		t.Errorf("unexpected content: %q", ms.Content)
	}
	if !ms.HasDate {
		t.Error("expected has_date=true")
	}
	expectedDate := time.Date(2026, 3, 10, 0, 0, 0, 0, time.UTC)
	if !ms.Date.Equal(expectedDate) {
		t.Errorf("expected date %v, got %v", expectedDate, ms.Date)
	}
	if ms.RemainingDays != 9 {
		t.Errorf("expected 9 remaining days, got %d", ms.RemainingDays)
	}
}

func TestParseRecurringMonthlyPastDay(t *testing.T) {
	// now = March 15 → day 10 already passed → next is April 10
	now := time.Date(2026, 3, 15, 0, 0, 0, 0, time.UTC)
	content := `- [ ] @monthly 10 test`
	milestones := ParseMilestones(content, "test.md", now)

	if len(milestones) != 1 {
		t.Fatalf("expected 1 milestone, got %d", len(milestones))
	}
	expectedDate := time.Date(2026, 4, 10, 0, 0, 0, 0, time.UTC)
	if !milestones[0].Date.Equal(expectedDate) {
		t.Errorf("expected date %v, got %v", expectedDate, milestones[0].Date)
	}
}

func TestParseRecurringMonthlyOnDay(t *testing.T) {
	// now = March 10 → today is the day → should be today (remaining=0)
	now := time.Date(2026, 3, 10, 0, 0, 0, 0, time.UTC)
	content := `- [ ] @monthly 10 test`
	milestones := ParseMilestones(content, "test.md", now)

	if len(milestones) != 1 {
		t.Fatalf("expected 1 milestone, got %d", len(milestones))
	}
	expectedDate := time.Date(2026, 3, 10, 0, 0, 0, 0, time.UTC)
	if !milestones[0].Date.Equal(expectedDate) {
		t.Errorf("expected date %v, got %v", expectedDate, milestones[0].Date)
	}
	if milestones[0].RemainingDays != 0 {
		t.Errorf("expected 0 remaining days, got %d", milestones[0].RemainingDays)
	}
}

func TestParseRecurringMonthlyShortMonthClamp(t *testing.T) {
	// now = Jan 30 → @monthly 31 → Jan 31 (exists), should be Jan 31
	now := time.Date(2026, 1, 30, 0, 0, 0, 0, time.UTC)
	content := `- [ ] @monthly 31 test`
	milestones := ParseMilestones(content, "test.md", now)

	if len(milestones) != 1 {
		t.Fatalf("expected 1 milestone, got %d", len(milestones))
	}
	expectedDate := time.Date(2026, 1, 31, 0, 0, 0, 0, time.UTC)
	if !milestones[0].Date.Equal(expectedDate) {
		t.Errorf("expected date %v, got %v", expectedDate, milestones[0].Date)
	}

	// now = Feb 1 → @monthly 31 → Feb has 28 days → Feb 28
	now2 := time.Date(2026, 2, 1, 0, 0, 0, 0, time.UTC)
	milestones2 := ParseMilestones(content, "test.md", now2)

	if len(milestones2) != 1 {
		t.Fatalf("expected 1 milestone, got %d", len(milestones2))
	}
	expectedDate2 := time.Date(2026, 2, 28, 0, 0, 0, 0, time.UTC)
	if !milestones2[0].Date.Equal(expectedDate2) {
		t.Errorf("expected date %v, got %v", expectedDate2, milestones2[0].Date)
	}
}

func TestParseRecurringMonthEnd(t *testing.T) {
	content := `- [ ] @month-end 請求処理`

	// now = March 1 → month end is March 31
	now := time.Date(2026, 3, 1, 0, 0, 0, 0, time.UTC)
	milestones := ParseMilestones(content, "test.md", now)

	if len(milestones) != 1 {
		t.Fatalf("expected 1 milestone, got %d", len(milestones))
	}
	ms := milestones[0]
	if !ms.Recurring {
		t.Error("expected recurring=true")
	}
	if ms.RecurringRule != "@month-end" {
		t.Errorf("unexpected rule: %q", ms.RecurringRule)
	}
	expectedDate := time.Date(2026, 3, 31, 0, 0, 0, 0, time.UTC)
	if !ms.Date.Equal(expectedDate) {
		t.Errorf("expected date %v, got %v", expectedDate, ms.Date)
	}
	if ms.RemainingDays != 30 {
		t.Errorf("expected 30 remaining days, got %d", ms.RemainingDays)
	}
}

func TestParseRecurringMonthEndFeb(t *testing.T) {
	content := `- [ ] @month-end test`

	// now = Feb 1 → month end is Feb 28 (2026 is not a leap year)
	now := time.Date(2026, 2, 1, 0, 0, 0, 0, time.UTC)
	milestones := ParseMilestones(content, "test.md", now)

	if len(milestones) != 1 {
		t.Fatalf("expected 1 milestone, got %d", len(milestones))
	}
	expectedDate := time.Date(2026, 2, 28, 0, 0, 0, 0, time.UTC)
	if !milestones[0].Date.Equal(expectedDate) {
		t.Errorf("expected date %v, got %v", expectedDate, milestones[0].Date)
	}
}

func TestParseRecurringYearly(t *testing.T) {
	content := `- [ ] @yearly 03-15 確定申告期限`

	// now = March 1, 2026 → March 15 is in the future
	now := time.Date(2026, 3, 1, 0, 0, 0, 0, time.UTC)
	milestones := ParseMilestones(content, "test.md", now)

	if len(milestones) != 1 {
		t.Fatalf("expected 1 milestone, got %d", len(milestones))
	}
	ms := milestones[0]
	if !ms.Recurring {
		t.Error("expected recurring=true")
	}
	if ms.RecurringRule != "@yearly 03-15" {
		t.Errorf("unexpected rule: %q", ms.RecurringRule)
	}
	expectedDate := time.Date(2026, 3, 15, 0, 0, 0, 0, time.UTC)
	if !ms.Date.Equal(expectedDate) {
		t.Errorf("expected date %v, got %v", expectedDate, ms.Date)
	}
	if ms.RemainingDays != 14 {
		t.Errorf("expected 14 remaining days, got %d", ms.RemainingDays)
	}
}

func TestParseRecurringYearlyPastDate(t *testing.T) {
	content := `- [ ] @yearly 01-15 test`

	// now = March 1, 2026 → Jan 15 already passed → next is Jan 15, 2027
	now := time.Date(2026, 3, 1, 0, 0, 0, 0, time.UTC)
	milestones := ParseMilestones(content, "test.md", now)

	if len(milestones) != 1 {
		t.Fatalf("expected 1 milestone, got %d", len(milestones))
	}
	expectedDate := time.Date(2027, 1, 15, 0, 0, 0, 0, time.UTC)
	if !milestones[0].Date.Equal(expectedDate) {
		t.Errorf("expected date %v, got %v", expectedDate, milestones[0].Date)
	}
}

func TestParseRecurringWeekly(t *testing.T) {
	content := `- [ ] @weekly mon 週次ミーティング`

	// now = March 1, 2026 (Sunday) → next Monday is March 2
	now := time.Date(2026, 3, 1, 0, 0, 0, 0, time.UTC)
	milestones := ParseMilestones(content, "test.md", now)

	if len(milestones) != 1 {
		t.Fatalf("expected 1 milestone, got %d", len(milestones))
	}
	ms := milestones[0]
	if !ms.Recurring {
		t.Error("expected recurring=true")
	}
	if ms.RecurringRule != "@weekly mon" {
		t.Errorf("unexpected rule: %q", ms.RecurringRule)
	}
	expectedDate := time.Date(2026, 3, 2, 0, 0, 0, 0, time.UTC)
	if !ms.Date.Equal(expectedDate) {
		t.Errorf("expected date %v, got %v", expectedDate, ms.Date)
	}
	if ms.RemainingDays != 1 {
		t.Errorf("expected 1 remaining day, got %d", ms.RemainingDays)
	}
}

func TestParseRecurringWeeklyToday(t *testing.T) {
	content := `- [ ] @weekly wed test`

	// now = Wednesday March 4, 2026 → today is the day
	now := time.Date(2026, 3, 4, 0, 0, 0, 0, time.UTC)
	milestones := ParseMilestones(content, "test.md", now)

	if len(milestones) != 1 {
		t.Fatalf("expected 1 milestone, got %d", len(milestones))
	}
	expectedDate := time.Date(2026, 3, 4, 0, 0, 0, 0, time.UTC)
	if !milestones[0].Date.Equal(expectedDate) {
		t.Errorf("expected date %v, got %v", expectedDate, milestones[0].Date)
	}
	if milestones[0].RemainingDays != 0 {
		t.Errorf("expected 0 remaining days, got %d", milestones[0].RemainingDays)
	}
}

func TestParseRecurringMonthlyInvalidDayFallsBackToUndated(t *testing.T) {
	content := `- [ ] @monthly 00 invalid`
	now := time.Date(2026, 3, 1, 0, 0, 0, 0, time.UTC)
	milestones := ParseMilestones(content, "test.md", now)

	if len(milestones) != 1 {
		t.Fatalf("expected 1 milestone, got %d", len(milestones))
	}
	ms := milestones[0]
	if ms.Recurring {
		t.Error("expected recurring=false for invalid monthly day")
	}
	if ms.HasDate {
		t.Error("expected has_date=false for invalid monthly day")
	}
	if ms.Content != "@monthly 00 invalid" {
		t.Errorf("unexpected content: %q", ms.Content)
	}
}

func TestParseRecurringYearlyInvalidMonthFallsBackToUndated(t *testing.T) {
	content := `- [ ] @yearly 13-15 invalid`
	now := time.Date(2026, 3, 1, 0, 0, 0, 0, time.UTC)
	milestones := ParseMilestones(content, "test.md", now)

	if len(milestones) != 1 {
		t.Fatalf("expected 1 milestone, got %d", len(milestones))
	}
	ms := milestones[0]
	if ms.Recurring {
		t.Error("expected recurring=false for invalid yearly date")
	}
	if ms.HasDate {
		t.Error("expected has_date=false for invalid yearly date")
	}
	if ms.Content != "@yearly 13-15 invalid" {
		t.Errorf("unexpected content: %q", ms.Content)
	}
}

func TestParseMixedMilestones(t *testing.T) {
	content := `---
title: "マイルストーン"
---

- [ ] 2026-03-05 リリース
- [ ] @monthly 10 保険期限
- [ ] @month-end 請求処理
- [ ] @yearly 03-15 確定申告
- [ ] @weekly mon ミーティング
- [ ] undated task
- [x] 2026-02-01 completed
`

	now := time.Date(2026, 3, 1, 0, 0, 0, 0, time.UTC)
	milestones := ParseMilestones(content, "test.md", now)

	if len(milestones) != 7 {
		t.Fatalf("expected 7 milestones, got %d", len(milestones))
	}

	// Verify types: dated, recurring*4, undated, dated(checked)
	if milestones[0].HasDate && !milestones[0].Recurring {
		// dated - ok
	} else {
		t.Errorf("milestone 0 should be dated non-recurring")
	}

	for i := 1; i <= 4; i++ {
		if !milestones[i].Recurring {
			t.Errorf("milestone %d should be recurring", i)
		}
		if !milestones[i].HasDate {
			t.Errorf("milestone %d should have date", i)
		}
	}

	if milestones[5].HasDate || milestones[5].Recurring {
		t.Errorf("milestone 5 should be undated non-recurring")
	}
	if milestones[5].Content != "undated task" {
		t.Errorf("unexpected content for milestone 5: %q", milestones[5].Content)
	}

	if !milestones[6].Checked {
		t.Error("milestone 6 should be checked")
	}
}

func TestParseMilestones_InvalidDatedFallsBackToUndated(t *testing.T) {
	content := `- [ ] 2026-02-31 Invalid calendar date
`
	now := time.Date(2026, 3, 1, 0, 0, 0, 0, time.UTC)
	milestones := ParseMilestones(content, "test.md", now)
	if len(milestones) != 1 {
		t.Fatalf("expected 1 milestone, got %d", len(milestones))
	}
	ms := milestones[0]
	if ms.HasDate {
		t.Error("expected HasDate=false for invalid dated input")
	}
	if ms.Recurring {
		t.Error("expected Recurring=false for invalid dated input")
	}
	if ms.Content != "2026-02-31 Invalid calendar date" {
		t.Errorf("unexpected content: %q", ms.Content)
	}
}

func TestNextMonthlyYearBoundary(t *testing.T) {
	// now = Dec 15 → @monthly 10 → next is Jan 10 of next year
	now := time.Date(2026, 12, 15, 0, 0, 0, 0, time.UTC)
	date := nextMonthly(10, now)
	expected := time.Date(2027, 1, 10, 0, 0, 0, 0, time.UTC)
	if !date.Equal(expected) {
		t.Errorf("expected %v, got %v", expected, date)
	}
}

func TestNextMonthEndYearBoundary(t *testing.T) {
	// now = Dec 31 → month end is Dec 31 (today) → remaining=0
	now := time.Date(2026, 12, 31, 0, 0, 0, 0, time.UTC)
	date := nextMonthEnd(now)
	expected := time.Date(2026, 12, 31, 0, 0, 0, 0, time.UTC)
	if !date.Equal(expected) {
		t.Errorf("expected %v, got %v", expected, date)
	}
}

func TestNextYearlyOnDay(t *testing.T) {
	// now = March 15 → @yearly 03-15 → today
	now := time.Date(2026, 3, 15, 0, 0, 0, 0, time.UTC)
	date := nextYearly("03-15", now)
	expected := time.Date(2026, 3, 15, 0, 0, 0, 0, time.UTC)
	if !date.Equal(expected) {
		t.Errorf("expected %v, got %v", expected, date)
	}
}

func TestNextWeeklyWrapAround(t *testing.T) {
	// now = Saturday March 7, 2026 → @weekly mon → March 9
	now := time.Date(2026, 3, 7, 0, 0, 0, 0, time.UTC)
	date := nextWeekly("mon", now)
	expected := time.Date(2026, 3, 9, 0, 0, 0, 0, time.UTC)
	if !date.Equal(expected) {
		t.Errorf("expected %v, got %v", expected, date)
	}
}

// --- Template parsing tests ---

func TestParseRecurringTemplates(t *testing.T) {
	content := `---
title: milestones
---

- @monthly 10 保険期限
- @month-end 請求処理
- @yearly 03-15 確定申告
- @weekly mon ミーティング
- [ ] 2026-03-05 リリース
- [ ] undated task
`
	templates := ParseRecurringTemplates(content)
	if len(templates) != 4 {
		t.Fatalf("expected 4 templates, got %d", len(templates))
	}

	if templates[0].ruleType != "monthly" || templates[0].param != "10" || templates[0].content != "保険期限" {
		t.Errorf("unexpected template 0: %+v", templates[0])
	}
	if templates[1].ruleType != "month-end" || templates[1].content != "請求処理" {
		t.Errorf("unexpected template 1: %+v", templates[1])
	}
	if templates[2].ruleType != "yearly" || templates[2].param != "03-15" || templates[2].content != "確定申告" {
		t.Errorf("unexpected template 2: %+v", templates[2])
	}
	if templates[3].ruleType != "weekly" || templates[3].param != "mon" || templates[3].content != "ミーティング" {
		t.Errorf("unexpected template 3: %+v", templates[3])
	}
}

func TestParseRecurringTemplates_NoCheckboxLinesOnly(t *testing.T) {
	content := `- [ ] @monthly 10 checkbox monthly
- @monthly 10 template monthly
`
	templates := ParseRecurringTemplates(content)
	if len(templates) != 1 {
		t.Fatalf("expected 1 template (checkbox-less only), got %d", len(templates))
	}
	if templates[0].content != "template monthly" {
		t.Errorf("unexpected content: %q", templates[0].content)
	}
}

func TestParseRecurringTemplates_InvalidSkipped(t *testing.T) {
	content := `- @monthly 0 invalid day
- @monthly 32 invalid day
- @yearly 13-15 invalid month
`
	templates := ParseRecurringTemplates(content)
	if len(templates) != 0 {
		t.Fatalf("expected 0 templates for invalid rules, got %d", len(templates))
	}
}

// --- Materialization tests ---

func TestMaterializeRecurring(t *testing.T) {
	dir := t.TempDir()
	projDir := filepath.Join(dir, "projects")
	if err := os.MkdirAll(projDir, 0755); err != nil {
		t.Fatal(err)
	}

	initial := `---
title: milestones
---

- @monthly 10 保険期限
- [ ] 2026-03-05 リリース
`
	msFile := filepath.Join(projDir, "_milestones.md")
	if err := os.WriteFile(msFile, []byte(initial), 0644); err != nil {
		t.Fatal(err)
	}

	now := time.Date(2026, 3, 1, 0, 0, 0, 0, time.UTC)
	if err := MaterializeRecurring(dir, now); err != nil {
		t.Fatal(err)
	}

	data, err := os.ReadFile(msFile)
	if err != nil {
		t.Fatal(err)
	}
	content := string(data)

	// Should have appended "- [ ] 2026-03-10 保険期限"
	if !strings.Contains(content, "- [ ] 2026-03-10 保険期限") {
		t.Errorf("expected materialized milestone, got:\n%s", content)
	}

	// Original content preserved
	if !strings.Contains(content, "- @monthly 10 保険期限") {
		t.Error("template should be preserved")
	}
	if !strings.Contains(content, "- [ ] 2026-03-05 リリース") {
		t.Error("existing milestone should be preserved")
	}
}

func TestMaterializeRecurring_NoDuplicates(t *testing.T) {
	dir := t.TempDir()
	projDir := filepath.Join(dir, "projects")
	if err := os.MkdirAll(projDir, 0755); err != nil {
		t.Fatal(err)
	}

	// File already has the materialized instance
	initial := `- @monthly 10 保険期限
- [ ] 2026-03-10 保険期限
`
	msFile := filepath.Join(projDir, "_milestones.md")
	if err := os.WriteFile(msFile, []byte(initial), 0644); err != nil {
		t.Fatal(err)
	}

	now := time.Date(2026, 3, 1, 0, 0, 0, 0, time.UTC)
	if err := MaterializeRecurring(dir, now); err != nil {
		t.Fatal(err)
	}

	data, _ := os.ReadFile(msFile)
	// Should not duplicate
	count := strings.Count(string(data), "- [ ] 2026-03-10 保険期限")
	if count != 1 {
		t.Errorf("expected 1 instance, found %d in:\n%s", count, string(data))
	}
}

func TestMaterializeRecurring_CheckedInstanceCountsAsExisting(t *testing.T) {
	dir := t.TempDir()
	projDir := filepath.Join(dir, "projects")
	if err := os.MkdirAll(projDir, 0755); err != nil {
		t.Fatal(err)
	}

	// Checked instance already exists
	initial := `- @monthly 10 保険期限
- [x] 2026-03-10 保険期限
`
	msFile := filepath.Join(projDir, "_milestones.md")
	if err := os.WriteFile(msFile, []byte(initial), 0644); err != nil {
		t.Fatal(err)
	}

	now := time.Date(2026, 3, 1, 0, 0, 0, 0, time.UTC)
	if err := MaterializeRecurring(dir, now); err != nil {
		t.Fatal(err)
	}

	data, _ := os.ReadFile(msFile)
	// Should not add another instance
	if strings.Contains(string(data), "- [ ] 2026-03-10 保険期限") {
		t.Errorf("should not add unchecked instance when checked one exists:\n%s", string(data))
	}
}

func TestMaterializeRecurring_NoFile(t *testing.T) {
	dir := t.TempDir()
	// No milestones file — should not error
	if err := MaterializeRecurring(dir, time.Now()); err != nil {
		t.Errorf("expected nil error for missing file, got %v", err)
	}
}

// --- Sort tests ---

func TestSortMilestones(t *testing.T) {
	content := `- [ ] undated task
- [ ] 2026-03-10 upcoming
- [ ] 2026-03-01 overdue
- [x] 2026-02-15 done past
- [ ] 2026-03-15 later
`
	now := time.Date(2026, 3, 5, 0, 0, 0, 0, time.UTC)
	milestones := ParseMilestones(content, "test.md", now)
	SortMilestones(milestones)

	// Expected order: overdue(03-01), dated by date asc(02-15, 03-10, 03-15), undated
	if len(milestones) != 5 {
		t.Fatalf("expected 5, got %d", len(milestones))
	}
	expected := []string{"overdue", "done past", "upcoming", "later", "undated task"}
	for i, e := range expected {
		if milestones[i].Content != e {
			t.Errorf("milestones[%d] = %q, want %q", i, milestones[i].Content, e)
		}
	}
}

// --- Visibility rules tests ---

func TestVisibilityRules(t *testing.T) {
	content := `- [ ] 2026-03-10 future unchecked
- [x] 2026-03-10 future checked
- [ ] 2026-03-01 overdue unchecked
- [x] 2026-03-01 past checked
- [ ] undated unchecked
- [x] undated checked
`
	now := time.Date(2026, 3, 5, 0, 0, 0, 0, time.UTC)
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
	milestones := ParseMilestones(content, "test.md", now)

	// Apply the same visibility rules as the CLI
	var visible []string
	for _, m := range milestones {
		if m.HasDate {
			if m.Checked && m.Date.Before(today) {
				continue
			}
		} else if m.Checked {
			continue
		}
		visible = append(visible, m.Content)
	}

	expected := []string{
		"future unchecked",
		"future checked",
		"overdue unchecked",
		"undated unchecked",
	}
	if len(visible) != len(expected) {
		t.Fatalf("expected %d visible, got %d: %v", len(expected), len(visible), visible)
	}
	for i, e := range expected {
		if visible[i] != e {
			t.Errorf("visible[%d] = %q, want %q", i, visible[i], e)
		}
	}
}
