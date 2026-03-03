package ui

import (
	"strings"

	"github.com/charmbracelet/lipgloss"
)

var (
	// Colors
	colorTitle    = lipgloss.Color("#FFFFFF")
	colorSubtle   = lipgloss.Color("#666666")
	colorAccent   = lipgloss.Color("#7D56F4")
	colorGreen    = lipgloss.Color("#04B575")
	colorYellow   = lipgloss.Color("#FFCC00")
	colorRed      = lipgloss.Color("#FF4444")
	colorDim      = lipgloss.Color("#444444")
	colorCursorBg = lipgloss.Color("#2D2D2D")
	// Client color palette (assigned by order of appearance)
	clientColors = []lipgloss.Color{
		lipgloss.Color("#4A9EFF"), // blue
		lipgloss.Color("#FF8C42"), // orange
		lipgloss.Color("#04B575"), // green
		lipgloss.Color("#FFCC00"), // yellow
		lipgloss.Color("#FF6B9D"), // pink
		lipgloss.Color("#A78BFA"), // purple
	}
	colorFocusBord = lipgloss.Color("#7D56F4")

	// Activity calendar colors
	colorOver    = lipgloss.Color("#FF4444") // 10h+ (red - overwork)
	colorWarning = lipgloss.Color("#FFCC00") // 8-10h (yellow - warning)
	colorHigh    = lipgloss.Color("#39D353") // 6-8h
	colorMedium  = lipgloss.Color("#26A641") // 3-6h
	colorLow     = lipgloss.Color("#006D32") // 1-3h
	colorLight   = lipgloss.Color("#0E4429") // 0-1h

	// Styles
	titleStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(colorTitle).
			Background(colorAccent).
			Padding(0, 1)

	dateStyle = lipgloss.NewStyle().
			Foreground(colorSubtle)

	sectionHeaderStyle = lipgloss.NewStyle().
				Bold(true).
				Foreground(colorSubtle)

	focusedHeaderStyle = lipgloss.NewStyle().
				Bold(true).
				Foreground(colorTitle).
				Background(colorAccent).
				Padding(0, 1)

	focusedSectionStyle = lipgloss.NewStyle().
				Border(lipgloss.RoundedBorder()).
				BorderForeground(colorFocusBord).
				Padding(0, 1)

	normalSectionStyle = lipgloss.NewStyle().
				Border(lipgloss.RoundedBorder()).
				BorderForeground(colorDim).
				Padding(0, 1)

	progressFullStyle = lipgloss.NewStyle().
				Foreground(colorGreen)

	progressEmptyStyle = lipgloss.NewStyle().
				Foreground(colorDim)

	// Milestone urgency styles
	urgencyRedStyle = lipgloss.NewStyle().
			Foreground(colorRed)

	urgencyYellowStyle = lipgloss.NewStyle().
				Foreground(colorYellow)

	urgencyGreenStyle = lipgloss.NewStyle().
				Foreground(colorGreen)

	wordStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#AAAAAA")).
			Italic(true).
			PaddingLeft(1)

	todoLabelStyle = lipgloss.NewStyle().
			Foreground(colorAccent).
			Bold(true)

	todoCursorStyle = lipgloss.NewStyle().
			Foreground(colorTitle).
			Bold(true).
			Background(colorCursorBg)

	summaryStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#555555")).
			Italic(true)

	recurringIndicatorStyle = lipgloss.NewStyle().
				Foreground(colorAccent).
				Bold(true)

	modalBorderStyle = lipgloss.NewStyle().
				Border(lipgloss.RoundedBorder()).
				BorderForeground(colorAccent).
				Padding(1, 2)

	modalTitleStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(colorTitle)

	modalHelpStyle = lipgloss.NewStyle().
			Foreground(colorSubtle)
)

// clientStyle returns a style for the given client index using the color palette.
func clientStyle(index int) lipgloss.Style {
	color := clientColors[index%len(clientColors)]
	return lipgloss.NewStyle().Foreground(color)
}

// MilestoneUrgencyIndicator returns a colored indicator based on remaining days.
func MilestoneUrgencyIndicator(days int) string {
	switch {
	case days <= 7:
		return urgencyRedStyle.Render("●")
	case days <= 14:
		return urgencyYellowStyle.Render("●")
	default:
		return urgencyGreenStyle.Render("●")
	}
}

// ProgressBar renders a text-based progress bar.
func ProgressBar(done, total, width int) string {
	if total == 0 {
		return ""
	}
	filled := width * done / total
	if filled > width {
		filled = width
	}
	bar := progressFullStyle.Render(repeat("█", filled)) +
		progressEmptyStyle.Render(repeat("░", width-filled))
	return bar
}

// RatioBar renders a colored ratio bar for a value relative to a total.
func RatioBar(value, total float64, width int, style lipgloss.Style) string {
	if total == 0 {
		return progressEmptyStyle.Render(repeat("░", width))
	}
	filled := int(float64(width) * value / total)
	if filled > width {
		filled = width
	}
	return style.Render(repeat("█", filled)) +
		progressEmptyStyle.Render(repeat("░", width-filled))
}

// StackedBar renders a single bar with segments colored per client.
// segments is a slice of (hours, clientIndex) pairs.
func StackedBar(segments []ClientSegment, total float64, width int) string {
	if total == 0 || len(segments) == 0 {
		return progressEmptyStyle.Render(repeat("░", width))
	}
	var bar string
	used := 0
	for i, seg := range segments {
		w := int(float64(width) * seg.Hours / total)
		if i == len(segments)-1 && used+w < width && seg.Hours > 0 {
			w = width - used // last segment gets the remainder
		}
		if w > 0 {
			bar += clientStyle(seg.ColorIndex).Render(repeat("█", w))
			used += w
		}
	}
	if used < width {
		bar += progressEmptyStyle.Render(repeat("░", width-used))
	}
	return bar
}

// ClientSegment holds one segment of a stacked bar.
type ClientSegment struct {
	Hours      float64
	ColorIndex int
}

// ActivityBlock returns a fixed-width block using background-colored spaces.
// Each block is exactly 2 columns wide (2 spaces with background color).
func ActivityBlock(hours float64) string {
	switch {
	case hours > 10:
		return lipgloss.NewStyle().Background(colorOver).Render("  ")
	case hours > 8:
		return lipgloss.NewStyle().Background(colorWarning).Render("  ")
	case hours > 6:
		return lipgloss.NewStyle().Background(colorHigh).Render("  ")
	case hours > 3:
		return lipgloss.NewStyle().Background(colorMedium).Render("  ")
	case hours > 1:
		return lipgloss.NewStyle().Background(colorLow).Render("  ")
	case hours > 0:
		return lipgloss.NewStyle().Background(colorLight).Render("  ")
	default:
		return lipgloss.NewStyle().Foreground(colorSubtle).Render("--")
	}
}

// FutureBlock returns a fixed-width block for future dates.
func FutureBlock() string {
	return lipgloss.NewStyle().Foreground(colorDim).Render("..")
}

// EmptyBlock returns a fixed-width empty block (outside month).
func EmptyBlock() string {
	return "  "
}

// cursorLine renders a selected item line with ▸ prefix and background highlight.
func cursorLine(text string) string {
	return todoCursorStyle.Render("▸ " + text)
}

// normalLine renders a non-selected item line with blank prefix for alignment.
func normalLine(text string) string {
	return "  " + text
}

func repeat(s string, n int) string {
	if n <= 0 {
		return ""
	}
	return strings.Repeat(s, n)
}
