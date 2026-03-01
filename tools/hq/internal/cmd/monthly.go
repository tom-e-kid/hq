package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/tom-e-kid/hq/tools/hq/internal/parser"
)

func runMonthly(basePath string, args []string) int {
	jsonOut := false
	var monthArg string

	for _, a := range args {
		switch a {
		case "--json":
			jsonOut = true
		default:
			if !strings.HasPrefix(a, "-") {
				monthArg = a
			}
		}
	}

	var target time.Time
	if monthArg == "" {
		target = time.Now()
	} else {
		parts := strings.Split(monthArg, ".")
		if len(parts) != 2 {
			fmt.Fprintf(os.Stderr, "invalid month format: %s (expected YYYY.MM)\n", monthArg)
			return 1
		}
		y, err1 := strconv.Atoi(parts[0])
		m, err2 := strconv.Atoi(parts[1])
		if err1 != nil || err2 != nil || m < 1 || m > 12 {
			fmt.Fprintf(os.Stderr, "invalid month format: %s (expected YYYY.MM)\n", monthArg)
			return 1
		}
		target = time.Date(y, time.Month(m), 1, 0, 0, 0, 0, time.Local)
	}

	data, err := parser.LoadMonthly(basePath, target)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		return 1
	}

	if data.Month == "" {
		fmt.Fprintf(os.Stderr, "No data for %d-%02d\n", target.Year(), target.Month())
		return 1
	}

	if jsonOut {
		enc := json.NewEncoder(os.Stdout)
		enc.SetIndent("", "  ")
		if err := enc.Encode(data); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			return 1
		}
		return 0
	}

	// Text output
	fmt.Printf("Monthly: %s\n", data.Month)
	fmt.Printf("Total: %.1fh / %d days (avg %.1fh/day)\n", data.TotalHours, data.WorkingDays, data.AvgHours())
	if len(data.ClientHours) > 0 {
		fmt.Println()
		for _, ch := range data.ClientHours {
			fmt.Printf("  %-20s %6.1fh\n", ch.Client, ch.Hours)
		}
	}
	return 0
}
