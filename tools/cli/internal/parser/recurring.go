package parser

import (
	"strings"
	"time"
)

// nextMonthly returns the next occurrence of the given day-of-month.
// If today is before or on that day this month, returns this month (clamped).
// Otherwise returns next month (clamped).
func nextMonthly(day int, today time.Time) time.Time {
	thisMonth := clampDay(today.Year(), today.Month(), day, today.Location())
	if !thisMonth.Before(today) {
		return thisMonth
	}
	nextM := today.Month() + 1
	nextY := today.Year()
	if nextM > 12 {
		nextM = 1
		nextY++
	}
	return clampDay(nextY, nextM, day, today.Location())
}

// nextMonthEnd returns the last day of the current month if today <= that day,
// otherwise the last day of next month.
func nextMonthEnd(today time.Time) time.Time {
	endOfThis := lastDayOfMonth(today.Year(), today.Month(), today.Location())
	if !endOfThis.Before(today) {
		return endOfThis
	}
	nextM := today.Month() + 1
	nextY := today.Year()
	if nextM > 12 {
		nextM = 1
		nextY++
	}
	return lastDayOfMonth(nextY, nextM, today.Location())
}

// nextYearly returns the next occurrence of MM-DD.
// If this year's date is today or later, returns this year. Otherwise next year.
func nextYearly(mmdd string, today time.Time) time.Time {
	parts := strings.Split(mmdd, "-")
	month := time.Month(atoi(parts[0]))
	day := atoi(parts[1])
	thisYear := clampDay(today.Year(), month, day, today.Location())
	if !thisYear.Before(today) {
		return thisYear
	}
	return clampDay(today.Year()+1, month, day, today.Location())
}

// nextWeekly returns the next occurrence of the given weekday (including today).
func nextWeekly(dow string, today time.Time) time.Time {
	target := parseDow(dow)
	current := today.Weekday()
	diff := int(target) - int(current)
	if diff < 0 {
		diff += 7
	}
	return today.AddDate(0, 0, diff)
}

// clampDay returns the given date, clamping the day to the last valid day of the month.
func clampDay(year int, month time.Month, day int, loc *time.Location) time.Time {
	last := lastDayOfMonth(year, month, loc).Day()
	if day > last {
		day = last
	}
	if day < 1 {
		day = 1
	}
	return time.Date(year, month, day, 0, 0, 0, 0, loc)
}

// lastDayOfMonth returns the last day of the given month.
func lastDayOfMonth(year int, month time.Month, loc *time.Location) time.Time {
	// Go to the first day of next month, then subtract one day
	return time.Date(year, month+1, 1, 0, 0, 0, 0, loc).AddDate(0, 0, -1)
}

// parseDow converts a 3-letter weekday abbreviation to time.Weekday.
func parseDow(s string) time.Weekday {
	switch strings.ToLower(s) {
	case "sun":
		return time.Sunday
	case "mon":
		return time.Monday
	case "tue":
		return time.Tuesday
	case "wed":
		return time.Wednesday
	case "thu":
		return time.Thursday
	case "fri":
		return time.Friday
	case "sat":
		return time.Saturday
	default:
		return time.Monday
	}
}

// atoi converts a string to int, returning 0 on error.
func atoi(s string) int {
	n := 0
	for _, c := range s {
		if c >= '0' && c <= '9' {
			n = n*10 + int(c-'0')
		}
	}
	return n
}
