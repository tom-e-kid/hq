package parser

import (
	"math"
	"testing"
)

func TestParseMonthly(t *testing.T) {
	content := `---
title: "2026-02 月間ログ"
month: "2026-02"
hours:
  total: 117.5
  client_b: 84.5
  client_a: 33.0
---

## 20260225

### 実績 ☔️

P:

- アクティブプロジェクトの整理

T:

- CLIENT_B:機能開発: 0.5
- CLIENT_B:改善対応: 0.0
- CLIENT_B:調査、問い合わせ対応: 1.5
  - cursor 形式のリスト API について
- CLIENT_B:全体: 1.0
  - MTG > 定例会議
- CLIENT_A:研究開発: 2.5
  - dashboard の整理
- CLIENT_A:運営: 0.0

## 20260224

### 実績 ☁️

P:

- dashboard の整理

T:

- CLIENT_B:機能開発: 2.0
- CLIENT_B:業務効率化: 1.5
- CLIENT_A:研究開発: 6.0
- CLIENT_A:運営: 0.0
`

	data, err := ParseMonthly(content)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if data.Month != "2026-02" {
		t.Errorf("unexpected month: %q", data.Month)
	}
	// Hours are calculated from body entries, not frontmatter
	if math.Abs(data.TotalHours-15.0) > 0.01 {
		t.Errorf("unexpected total hours: %f (expected 15.0)", data.TotalHours)
	}
	// ClientHours should be ordered by first appearance: CLIENT_B, CLIENT_A
	if len(data.ClientHours) != 2 {
		t.Fatalf("expected 2 client entries, got %d", len(data.ClientHours))
	}
	if data.ClientHours[0].Client != "CLIENT_B" {
		t.Errorf("expected first client 'CLIENT_B', got %q", data.ClientHours[0].Client)
	}
	if math.Abs(data.ClientHours[0].Hours-6.5) > 0.01 {
		t.Errorf("unexpected first client hours: %f (expected 6.5)", data.ClientHours[0].Hours)
	}
	if data.ClientHours[1].Client != "CLIENT_A" {
		t.Errorf("expected second client 'CLIENT_A', got %q", data.ClientHours[1].Client)
	}
	if math.Abs(data.ClientHours[1].Hours-8.5) > 0.01 {
		t.Errorf("unexpected second client hours: %f (expected 8.5)", data.ClientHours[1].Hours)
	}

	if len(data.DailyEntries) != 2 {
		t.Fatalf("expected 2 daily entries, got %d", len(data.DailyEntries))
	}

	// Feb 25
	day1 := data.DailyEntries[0]
	if day1.Date.Day() != 25 {
		t.Errorf("expected day 25, got %d", day1.Date.Day())
	}
	expectedHours := 5.5 // 0.5 + 0.0 + 1.5 + 1.0 + 2.5 + 0.0
	if math.Abs(day1.TotalHours-expectedHours) > 0.01 {
		t.Errorf("expected %.1f hours for day 25, got %.1f", expectedHours, day1.TotalHours)
	}

	// Feb 24
	day2 := data.DailyEntries[1]
	if day2.Date.Day() != 24 {
		t.Errorf("expected day 24, got %d", day2.Date.Day())
	}
	expectedHours2 := 9.5 // 2.0 + 1.5 + 6.0 + 0.0
	if math.Abs(day2.TotalHours-expectedHours2) > 0.01 {
		t.Errorf("expected %.1f hours for day 24, got %.1f", expectedHours2, day2.TotalHours)
	}

	// Working days: both have hours > 0
	if data.WorkingDays != 2 {
		t.Errorf("expected 2 working days, got %d", data.WorkingDays)
	}
}

func TestParseMonthly_CommaDecimal(t *testing.T) {
	content := `---
month: "2026-02"
hours:
  total: 10.0
  client_b: 5.0
  client_a: 5.0
---

## 20260201

### 実績

T:

- CLIENT_B:開発: 1,5
- CLIENT_A:研究開発: 2,0
`

	data, err := ParseMonthly(content)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(data.DailyEntries) != 1 {
		t.Fatalf("expected 1 entry, got %d", len(data.DailyEntries))
	}
	if math.Abs(data.DailyEntries[0].TotalHours-3.5) > 0.01 {
		t.Errorf("expected 3.5 hours, got %.1f", data.DailyEntries[0].TotalHours)
	}
}
