package parser

import (
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
	if ms2.RemainingDays != 0 {
		t.Errorf("expected 0 remaining days for past milestone, got %d", ms2.RemainingDays)
	}
	if ms2.Line != 7 {
		t.Errorf("expected line 7, got %d", ms2.Line)
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
