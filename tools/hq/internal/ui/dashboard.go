package ui

import (
	"fmt"
	"math"
	"strings"
	"time"

	"github.com/charmbracelet/lipgloss"
	"github.com/tom-e-kid/hq/tools/hq/internal/model"
)

// Section identifiers for keyboard navigation.
type Section int

const (
	SectionMilestones Section = iota
	SectionWIP
	SectionTodo
	SectionMonthly
	sectionCount
)

// sectionBounds stores the Y coordinate range for a section.
type sectionBounds struct {
	Section Section
	StartY  int
	EndY    int // exclusive
}

// DashboardView holds the rendering state for the dashboard.
type DashboardView struct {
	Data                  model.DashboardData
	Width                 int
	Height                int
	FocusSection          Section
	ScrollOffset          map[Section]int
	WordIndex             int
	MonthlyIndex          int
	TodoCursor            int
	AddingTodo            bool
	AddTodoCursor         int
	AddTodoInputView      string
	MilestoneCursor       int
	AddingMilestone       bool
	AddMilestoneCursor    int
	AddMilestoneInputView string
	SectionBounds         []sectionBounds
}

// NewDashboardView creates a new dashboard view.
func NewDashboardView(data model.DashboardData, width, height int) *DashboardView {
	return &DashboardView{
		Data:         data,
		Width:        width,
		Height:       height,
		FocusSection: SectionMilestones,
		ScrollOffset: make(map[Section]int),
	}
}

// SectionAtY returns the section at the given Y coordinate, or -1 if none.
func (dv *DashboardView) SectionAtY(y int) Section {
	for _, b := range dv.SectionBounds {
		if y >= b.StartY && y < b.EndY {
			return b.Section
		}
	}
	return -1
}

func (dv *DashboardView) NextSection() {
	dv.FocusSection = (dv.FocusSection + 1) % sectionCount
}

func (dv *DashboardView) PrevSection() {
	dv.FocusSection = (dv.FocusSection - 1 + sectionCount) % sectionCount
}

func (dv *DashboardView) ScrollDown() {
	switch dv.FocusSection {
	case SectionTodo:
		items := dv.buildTodoItems()
		next := dv.TodoCursor + 1
		// Skip separator lines
		for next < len(items) && items[next].isSeparator {
			next++
		}
		if next < len(items) {
			dv.TodoCursor = next
		}
		return
	case SectionMilestones:
		items := dv.buildMilestoneItems()
		if dv.MilestoneCursor < len(items)-1 {
			dv.MilestoneCursor++
		}
		return
	}
	max := dv.maxScroll(dv.FocusSection)
	if dv.ScrollOffset[dv.FocusSection] < max {
		dv.ScrollOffset[dv.FocusSection]++
	}
}

func (dv *DashboardView) ScrollUp() {
	switch dv.FocusSection {
	case SectionTodo:
		items := dv.buildTodoItems()
		prev := dv.TodoCursor - 1
		// Skip separator lines
		for prev >= 0 && items[prev].isSeparator {
			prev--
		}
		if prev >= 0 {
			dv.TodoCursor = prev
		}
		return
	case SectionMilestones:
		if dv.MilestoneCursor > 0 {
			dv.MilestoneCursor--
		}
		return
	}
	if dv.ScrollOffset[dv.FocusSection] > 0 {
		dv.ScrollOffset[dv.FocusSection]--
	}
}

func (dv *DashboardView) currentMonthly() model.MonthlyData {
	if len(dv.Data.AllMonthly) == 0 {
		return dv.Data.Monthly
	}
	idx := dv.MonthlyIndex
	if idx < 0 || idx >= len(dv.Data.AllMonthly) {
		return dv.Data.Monthly
	}
	return dv.Data.AllMonthly[idx]
}

func (dv *DashboardView) MonthlyPrev() bool {
	if dv.FocusSection != SectionMonthly {
		return false
	}
	if dv.MonthlyIndex > 0 {
		dv.MonthlyIndex--
		return true
	}
	return false
}

func (dv *DashboardView) MonthlyNext() bool {
	if dv.FocusSection != SectionMonthly {
		return false
	}
	if dv.MonthlyIndex < len(dv.Data.AllMonthly)-1 {
		dv.MonthlyIndex++
		return true
	}
	return false
}

// currentTodoItem returns the currently selected todo item (may be a label or task).
func (dv *DashboardView) currentTodoItem() (todoItem, bool) {
	items := dv.buildTodoItems()
	if dv.TodoCursor < 0 || dv.TodoCursor >= len(items) {
		return todoItem{}, false
	}
	return items[dv.TodoCursor], true
}

// milestoneItem is a flattened milestone entry with source location.
type milestoneItem struct {
	milestoneIdx int // index into dv.Data.Milestones, -1 for add row
	filePath     string
	line         int
	isAddRow     bool
}

func (dv *DashboardView) buildMilestoneItems() []milestoneItem {
	var items []milestoneItem
	for i, ms := range dv.Data.Milestones {
		// Hide recurring milestones more than 10 days away
		if ms.Recurring && ms.RemainingDays > 10 {
			continue
		}
		items = append(items, milestoneItem{
			milestoneIdx: i,
			filePath:     ms.FilePath,
			line:         ms.Line,
		})
	}
	// Add row at the bottom
	items = append(items, milestoneItem{
		milestoneIdx: -1,
		filePath:     dv.Data.MilestoneFilePath,
		isAddRow:     true,
	})
	return items
}

// currentMilestoneItem returns the currently selected milestone item.
func (dv *DashboardView) currentMilestoneItem() (milestoneItem, bool) {
	items := dv.buildMilestoneItems()
	if dv.MilestoneCursor < 0 || dv.MilestoneCursor >= len(items) {
		return milestoneItem{}, false
	}
	return items[dv.MilestoneCursor], true
}

func (dv *DashboardView) maxScroll(s Section) int {
	switch s {
	case SectionWIP:
		return max(0, len(dv.Data.WIPEntries)-3)
	case SectionTodo:
		return max(0, dv.totalTodoLines()-dv.todoVisibleLines())
	default:
		return 0
	}
}

func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}

func cloneScrollOffsets(src map[Section]int) map[Section]int {
	dst := make(map[Section]int, len(src))
	for k, v := range src {
		dst[k] = v
	}
	return dst
}

// Render produces the full dashboard string.
func (dv *DashboardView) Render() string {
	contentWidth := dv.Width - 4
	if contentWidth < 40 {
		contentWidth = 40
	}

	var sections []string

	// Word ticker + header
	sections = append(sections, dv.renderHeader(contentWidth))

	// Milestones
	sections = append(sections, dv.renderSection(
		SectionMilestones,
		"MILESTONES",
		dv.renderMilestones(contentWidth-4),
		contentWidth,
	))

	// WIP
	sections = append(sections, dv.renderSection(
		SectionWIP,
		"WIP",
		dv.renderWIP(contentWidth-4),
		contentWidth,
	))

	// Pre-render Monthly to measure its exact height
	monthlySection := dv.renderSection(
		SectionMonthly,
		dv.monthlyHeader(),
		dv.renderMonthlyAndActivity(contentWidth-4),
		contentWidth,
	)

	// Calculate TODO flex height by measured rendering so section borders never clip.
	todoTitle := fmt.Sprintf("TODO — %d open", dv.Data.TotalOpenTasks())
	bestTodoLines := 1
	maxProbeLines := max(1, dv.Height)
	for lines := 1; lines <= maxProbeLines; lines++ {
		probe := *dv
		probe.ScrollOffset = cloneScrollOffsets(dv.ScrollOffset)
		todoContent := probe.renderTodo(contentWidth-4, lines)
		todoSection := probe.renderSection(SectionTodo, todoTitle, todoContent, contentWidth)
		candidate := append(append([]string{}, sections...), todoSection, monthlySection)
		if lipgloss.Height(lipgloss.JoinVertical(lipgloss.Left, candidate...)) <= dv.Height {
			bestTodoLines = lines
			continue
		}
		break
	}

	// TODO (flex)
	todoSection := dv.renderSection(
		SectionTodo,
		todoTitle,
		dv.renderTodo(contentWidth-4, bestTodoLines),
		contentWidth,
	)
	sections = append(sections, todoSection)

	// Monthly (pinned at bottom)
	sections = append(sections, monthlySection)

	// Record section Y boundaries for mouse click detection.
	// sections[0]=header, [1]=milestones, [2]=wip, [3]=todo, [4]=monthly
	dv.SectionBounds = nil
	y := 0
	sectionMap := []Section{-1, SectionMilestones, SectionWIP, SectionTodo, SectionMonthly}
	for i, s := range sections {
		h := lipgloss.Height(s)
		if i < len(sectionMap) && sectionMap[i] >= 0 {
			dv.SectionBounds = append(dv.SectionBounds, sectionBounds{
				Section: sectionMap[i],
				StartY:  y,
				EndY:    y + h,
			})
		}
		y += h
	}

	return lipgloss.JoinVertical(lipgloss.Left, sections...)
}

func (dv *DashboardView) renderHeader(width int) string {
	title := titleStyle.Render(" HQ ")
	date := dateStyle.Render(dv.Data.Date.Format("2006-01-02"))

	word := ""
	if len(dv.Data.Words) > 0 {
		idx := dv.WordIndex % len(dv.Data.Words)
		word = wordStyle.Render(dv.Data.Words[idx])
	}

	// Layout: [title] [word ...] [date]
	fixedWidth := lipgloss.Width(title) + lipgloss.Width(date)
	gap := width - fixedWidth
	if gap < 1 {
		gap = 1
	}

	if word == "" {
		return title + strings.Repeat(" ", gap) + date
	}

	wordWidth := lipgloss.Width(word)
	if wordWidth+2 > gap {
		// Truncate word to fit
		maxRunes := gap - 4
		if maxRunes > 0 {
			runes := []rune(dv.Data.Words[dv.WordIndex%len(dv.Data.Words)])
			if len(runes) > maxRunes {
				runes = runes[:maxRunes]
			}
			word = wordStyle.Render(string(runes) + "…")
			wordWidth = lipgloss.Width(word)
		} else {
			word = ""
			wordWidth = 0
		}
	}

	if word == "" {
		return title + strings.Repeat(" ", gap) + date
	}

	remaining := gap - wordWidth
	padLeft := 2
	padRight := remaining - padLeft
	if padRight < 1 {
		padRight = 1
	}

	return title + strings.Repeat(" ", padLeft) + word + strings.Repeat(" ", padRight) + date
}

func (dv *DashboardView) renderSection(sec Section, title, content string, width int) string {
	var header string
	style := normalSectionStyle
	if sec == dv.FocusSection {
		style = focusedSectionStyle
		header = focusedHeaderStyle.Render("> " + title)
	} else {
		header = sectionHeaderStyle.Render("  " + title)
	}
	body := header + "\n" + content
	return style.Width(width - 4).Render(body)
}

func (dv *DashboardView) renderMilestones(width int) string {
	items := dv.buildMilestoneItems()
	if len(items) == 0 {
		return dimText("  No milestones")
	}

	// Clamp cursor
	if dv.MilestoneCursor >= len(items) {
		dv.MilestoneCursor = len(items) - 1
	}
	if dv.MilestoneCursor < 0 {
		dv.MilestoneCursor = 0
	}

	// Build display lines
	type msLine struct {
		text      string
		itemIndex int
		isAddRow  bool
		isInput   bool
	}
	var allLines []msLine
	for i, item := range items {
		if item.isAddRow {
			allLines = append(allLines, msLine{itemIndex: i, isAddRow: true})
			if dv.AddingMilestone && i == dv.AddMilestoneCursor {
				allLines = append(allLines, msLine{isInput: true, itemIndex: -1})
			}
		} else {
			allLines = append(allLines, msLine{itemIndex: i})
		}
	}

	// Find cursor line index
	cursorLineIdx := 0
	for i, l := range allLines {
		if l.itemIndex == dv.MilestoneCursor {
			cursorLineIdx = i
			break
		}
	}

	// Auto-scroll to keep cursor visible
	maxVisible := 5
	offset := dv.ScrollOffset[SectionMilestones]
	if cursorLineIdx < offset {
		offset = cursorLineIdx
	} else if cursorLineIdx >= offset+maxVisible {
		offset = cursorLineIdx - maxVisible + 1
	}
	dv.ScrollOffset[SectionMilestones] = offset

	if offset > len(allLines) {
		offset = len(allLines)
	}
	visible := allLines[offset:]
	if len(visible) > maxVisible {
		visible = visible[:maxVisible]
	}

	isFocused := dv.FocusSection == SectionMilestones
	var rendered []string
	for _, l := range visible {
		if l.isInput {
			rendered = append(rendered, "    "+dv.AddMilestoneInputView)
		} else if l.isAddRow {
			if isFocused && l.itemIndex == dv.MilestoneCursor {
				rendered = append(rendered, todoCursorStyle.Render("  + add"))
			} else {
				rendered = append(rendered, dimText("  + add"))
			}
		} else {
			ms := dv.Data.Milestones[items[l.itemIndex].milestoneIdx]
			var line string
			check := "[ ]"
			if ms.Checked {
				check = "[x]"
			}
			if ms.HasDate {
				var indicator string
				if ms.Recurring {
					indicator = recurringIndicatorStyle.Render("@")
				} else {
					indicator = MilestoneUrgencyIndicator(ms.RemainingDays)
				}
				dateStr := ms.Date.Format("01-02")
				remaining := fmt.Sprintf("(残り%d日)", ms.RemainingDays)
				content := truncateToWidth(ms.Content, width-30)
				line = fmt.Sprintf("  %s %s %s  %s %s", check, indicator, content, dateStr, remaining)
			} else {
				content := truncateToWidth(ms.Content, width-10)
				line = fmt.Sprintf("  %s %s", check, content)
			}
			if isFocused && l.itemIndex == dv.MilestoneCursor {
				rendered = append(rendered, todoCursorStyle.Render(line))
			} else {
				rendered = append(rendered, line)
			}
		}
	}

	// Pad to stable height
	for len(rendered) < maxVisible {
		rendered = append(rendered, "")
	}

	result := strings.Join(rendered, "\n")
	total := len(allLines)
	if total > maxVisible {
		shown := offset + len(visible)
		result += "\n" + dimText(fmt.Sprintf("  (%d-%d / %d)", offset+1, shown, total))
	}
	return result
}

func (dv *DashboardView) renderWIP(width int) string {
	if len(dv.Data.WIPEntries) == 0 {
		return dimText("  No WIP tasks")
	}

	offset := dv.ScrollOffset[SectionWIP]
	visible := 3
	end := offset + visible
	if end > len(dv.Data.WIPEntries) {
		end = len(dv.Data.WIPEntries)
	}

	var lines []string
	for _, w := range dv.Data.WIPEntries[offset:end] {
		branchInfo := ""
		if w.Branch != "" {
			branch := w.Branch
			if len(branch) > 30 {
				branch = branch[:27] + "..."
			}
			branchInfo = dimText(fmt.Sprintf(" (%s)", branch))
		}
		lines = append(lines, fmt.Sprintf("  ○ %s: %s%s", w.Project, w.Description, branchInfo))
	}

	result := strings.Join(lines, "\n")
	if len(dv.Data.WIPEntries) > visible {
		result += "\n" + dimText(fmt.Sprintf("  (%d/%d)", offset+1, len(dv.Data.WIPEntries)))
	}
	return result
}

// todoItem is a flattened task with its project label and source location.
type todoItem struct {
	label         string // "org/project", "inbox", etc.
	text          string
	filePath      string
	line          int
	isLabel       bool // true for section headers (selectable for adding)
	isSeparator   bool // true for zone separator lines
	inUrgentZone  bool // true for items in the urgent zone (show project suffix)
	hasDate       bool
	remainingDays int
	recurring     bool
	recurringRule string
	dateStr       string // "MM-DD" formatted date
	checked       bool
}

func (dv *DashboardView) buildTodoItems() []todoItem {
	// Determine the default task role for label suffix logic
	defaultRole := ""
	for _, pt := range dv.Data.ProjectTasks {
		if pt.Role != "" {
			defaultRole = pt.Role
			break
		}
	}

	// Helper to build label from project
	projectLabel := func(pt model.ProjectTasks) string {
		label := pt.Org + "/" + pt.Project
		if pt.Org == "_" && pt.Project == "inbox" {
			label = "inbox"
		}
		if pt.Role != "" && pt.Role != defaultRole {
			label += " (" + pt.Role + ")"
		}
		return label
	}

	// Collect urgent tasks (HasDate && RemainingDays <= 7, unchecked) across all projects
	type urgentTask struct {
		item  todoItem
		order int // for stable sort
	}
	var urgentTasks []urgentTask
	urgentIdx := 0
	for _, pt := range dv.Data.ProjectTasks {
		label := projectLabel(pt)
		for _, t := range pt.Tasks {
			if !t.Checked && t.HasDate && t.RemainingDays <= 7 {
				urgentTasks = append(urgentTasks, urgentTask{
					item: todoItem{
						label:         label,
						text:          t.Text,
						filePath:      t.FilePath,
						line:          t.Line,
						hasDate:       true,
						remainingDays: t.RemainingDays,
						recurring:     t.Recurring,
						recurringRule: t.RecurringRule,
						dateStr:       t.Date.Format("01-02"),
						checked:       t.Checked,
					},
					order: urgentIdx,
				})
				urgentIdx++
			}
		}
	}

	// Sort urgent tasks by RemainingDays ascending (stable)
	for i := 1; i < len(urgentTasks); i++ {
		for j := i; j > 0 && urgentTasks[j].item.remainingDays < urgentTasks[j-1].item.remainingDays; j-- {
			urgentTasks[j], urgentTasks[j-1] = urgentTasks[j-1], urgentTasks[j]
		}
	}

	var items []todoItem

	// Zone 1: Urgent tasks
	if len(urgentTasks) > 0 {
		items = append(items, todoItem{isSeparator: true, text: "期限1週間以内"})
		for _, ut := range urgentTasks {
			ut.item.inUrgentZone = true
			items = append(items, ut.item)
		}
	}

	// Zone 2: Per-project tasks
	hasProjectItems := false
	for _, pt := range dv.Data.ProjectTasks {
		label := projectLabel(pt)
		var filePath string
		if len(pt.Tasks) > 0 {
			filePath = pt.Tasks[0].FilePath
		}
		var taskItems []todoItem
		for _, t := range pt.Tasks {
			if !t.Checked {
				item := todoItem{
					label:    label,
					text:     t.Text,
					filePath: t.FilePath,
					line:     t.Line,
					checked:  t.Checked,
				}
				if t.HasDate {
					item.hasDate = true
					item.remainingDays = t.RemainingDays
					item.recurring = t.Recurring
					item.recurringRule = t.RecurringRule
					item.dateStr = t.Date.Format("01-02")
				}
				taskItems = append(taskItems, item)
			}
		}
		if len(taskItems) > 0 {
			// Sort within project: dated first (by RemainingDays), then undated
			for i := 1; i < len(taskItems); i++ {
				for j := i; j > 0; j-- {
					a, b := taskItems[j], taskItems[j-1]
					// dated < undated; within dated, lower remaining first
					aKey := 1000000
					if a.hasDate {
						aKey = a.remainingDays
					}
					bKey := 1000000
					if b.hasDate {
						bKey = b.remainingDays
					}
					if aKey < bKey {
						taskItems[j], taskItems[j-1] = taskItems[j-1], taskItems[j]
					}
				}
			}
			if !hasProjectItems {
				items = append(items, todoItem{isSeparator: true, text: "プロジェクト別"})
				hasProjectItems = true
			}
			items = append(items, todoItem{
				label:    label,
				filePath: filePath,
				isLabel:  true,
			})
			items = append(items, taskItems...)
		}
	}
	return items
}

func (dv *DashboardView) totalTodoLines() int {
	items := dv.buildTodoItems()
	if len(items) == 0 {
		return 1
	}
	total := len(items)
	if dv.AddingTodo {
		total++ // input line
	}
	return total
}

func (dv *DashboardView) todoVisibleLines() int {
	// A rough estimate; the actual value depends on remaining height
	return 10
}

func (dv *DashboardView) renderTodo(width, maxLines int) string {
	items := dv.buildTodoItems()
	if len(items) == 0 {
		return dimText("  No open tasks")
	}

	// Clamp cursor — skip separator lines
	if dv.TodoCursor >= len(items) {
		dv.TodoCursor = len(items) - 1
	}
	if dv.TodoCursor < 0 {
		dv.TodoCursor = 0
	}
	// Ensure cursor is not on a separator
	for dv.TodoCursor < len(items) && items[dv.TodoCursor].isSeparator {
		dv.TodoCursor++
	}
	if dv.TodoCursor >= len(items) {
		dv.TodoCursor = len(items) - 1
		for dv.TodoCursor > 0 && items[dv.TodoCursor].isSeparator {
			dv.TodoCursor--
		}
	}

	// Build display lines (items + optional input line)
	type todoLine struct {
		text        string
		itemIndex   int
		isLabel     bool
		isSeparator bool
		isInput     bool
	}
	var allLines []todoLine
	for i, item := range items {
		if item.isSeparator {
			allLines = append(allLines, todoLine{text: item.text, itemIndex: i, isSeparator: true})
		} else if item.isLabel {
			allLines = append(allLines, todoLine{text: item.label, itemIndex: i, isLabel: true})
			if dv.AddingTodo && i == dv.AddTodoCursor {
				allLines = append(allLines, todoLine{isInput: true, itemIndex: -1})
			}
		} else {
			allLines = append(allLines, todoLine{text: item.text, itemIndex: i})
		}
	}

	// Find which line the cursor is on
	cursorLineIdx := 0
	for i, l := range allLines {
		if l.itemIndex == dv.TodoCursor {
			cursorLineIdx = i
			break
		}
	}

	// Auto-scroll to keep cursor visible
	offset := dv.ScrollOffset[SectionTodo]
	if cursorLineIdx < offset {
		offset = cursorLineIdx
	} else if cursorLineIdx >= offset+maxLines {
		offset = cursorLineIdx - maxLines + 1
	}
	dv.ScrollOffset[SectionTodo] = offset

	if offset > len(allLines) {
		offset = len(allLines)
	}
	visible := allLines[offset:]
	if len(visible) > maxLines {
		visible = visible[:maxLines]
	}

	isFocused := dv.FocusSection == SectionTodo
	var rendered []string
	for _, l := range visible {
		if l.isInput {
			rendered = append(rendered, "    "+dv.AddTodoInputView)
		} else if l.isSeparator {
			rendered = append(rendered, dimText("  ── "+l.text+" ──"))
		} else if l.isLabel {
			label := truncateToWidth(l.text, width-4)
			if isFocused && l.itemIndex == dv.TodoCursor {
				rendered = append(rendered, todoCursorStyle.Render("  "+label+" +"))
			} else {
				rendered = append(rendered, todoLabelStyle.Render("  "+label)+" "+dimText("+"))
			}
		} else {
			item := items[l.itemIndex]
			line := dv.formatTodoLine(item, width, isFocused && l.itemIndex == dv.TodoCursor)
			rendered = append(rendered, line)
		}
	}

	// Pad to fixed height so section doesn't fluctuate
	for len(rendered) < maxLines {
		rendered = append(rendered, "")
	}

	result := strings.Join(rendered, "\n")
	total := len(allLines)
	if total > maxLines {
		shown := offset + len(visible)
		result += "\n" + dimText(fmt.Sprintf("  (%d-%d / %d)", offset+1, shown, total))
	}
	return result
}

// formatTodoLine renders a single todo task item line.
func (dv *DashboardView) formatTodoLine(item todoItem, width int, isCursor bool) string {
	check := "[ ]"
	if item.checked {
		check = "[x]"
	}

	if item.hasDate {
		var indicator string
		if item.recurring {
			indicator = recurringIndicatorStyle.Render("@")
		} else {
			indicator = MilestoneUrgencyIndicator(item.remainingDays)
		}
		remaining := fmt.Sprintf("(残り%d日)", item.remainingDays)
		// In urgent zone, show project label at end
		projectSuffix := ""
		if item.inUrgentZone && item.label != "" {
			projectSuffix = "  " + dimText("← "+item.label)
		}
		content := truncateToWidth(item.text, width-30)
		line := fmt.Sprintf("  %s %s %s  %s %s%s", check, indicator, content, item.dateStr, remaining, projectSuffix)
		if isCursor {
			return todoCursorStyle.Render(line)
		}
		return line
	}

	// Undated task
	content := truncateToWidth(item.text, width-10)
	line := fmt.Sprintf("  %s %s", check, content)
	if isCursor {
		return todoCursorStyle.Render(line)
	}
	return line
}

func (dv *DashboardView) renderMonthlyAndActivity(width int) string {
	m := dv.currentMonthly()

	// Row 1 left: hours breakdown
	var leftLines []string
	leftLines = append(leftLines, fmt.Sprintf("  合計: %.1fh (%dd, avg %.1fh)",
		m.TotalHours, m.WorkingDays, m.AvgHours()))

	barWidth := 20

	// Build client name → color index mapping (consistent with monthly breakdown)
	clientColorIdx := make(map[string]int)
	for i, ch := range m.ClientHours {
		clientColorIdx[ch.Client] = i
	}

	if m.TotalHours > 0 {
		// Find max client name width for alignment
		maxNameWidth := 0
		for _, ch := range m.ClientHours {
			if w := lipgloss.Width(ch.Client); w > maxNameWidth {
				maxNameWidth = w
			}
		}
		for i, ch := range m.ClientHours {
			pct := int(math.Round(ch.Hours / m.TotalHours * 100))
			style := clientStyle(i)
			padded := ch.Client + strings.Repeat(" ", maxNameWidth-lipgloss.Width(ch.Client))
			leftLines = append(leftLines, fmt.Sprintf("  %s  %.1fh %s %d%%",
				style.Render(padded),
				ch.Hours,
				RatioBar(ch.Hours, m.TotalHours, barWidth, style),
				pct))
		}
	}

	// Today's status
	todayStr := dv.Data.Date.Format("2006-01-02")
	for _, de := range m.DailyEntries {
		if de.Date.Format("2006-01-02") == todayStr {
			leftLines = append(leftLines, "")
			// Aggregate by client preserving order
			var segments []ClientSegment
			clientSeen := make(map[string]int) // client -> index in segments
			for _, te := range de.TimeEntries {
				idx, ok := clientSeen[te.Client]
				if !ok {
					idx = len(segments)
					clientSeen[te.Client] = idx
					colorIdx := idx
					if ci, found := clientColorIdx[te.Client]; found {
						colorIdx = ci
					}
					segments = append(segments, ClientSegment{ColorIndex: colorIdx})
				}
				segments[idx].Hours += te.Hours
			}
			bar := StackedBar(segments, de.TotalHours, barWidth)
			leftLines = append(leftLines, fmt.Sprintf("  %s  %.1fh %s",
				dimText(dv.Data.Date.Format("01-02")), de.TotalHours, bar))
			break
		}
	}

	leftContent := strings.Join(leftLines, "\n")

	// Row 1 right: activity calendar
	rightContent := dv.renderActivityCalendar()

	// Row 1: side by side (or stacked if narrow)
	var row1 string
	if width >= 70 {
		leftBox := lipgloss.NewStyle().Width(width/2 - 1).Render(leftContent)
		rightBox := lipgloss.NewStyle().Width(width/2 - 1).Render(rightContent)
		row1 = lipgloss.JoinHorizontal(lipgloss.Top, leftBox, rightBox)
	} else {
		row1 = leftContent + "\n\n" + rightContent
	}

	// Row 2: summary text (full width, dim+italic)
	if m.Summary != "" {
		var summaryLines []string
		for _, line := range strings.Split(m.Summary, "\n") {
			line = strings.TrimSpace(line)
			if line != "" {
				summaryLines = append(summaryLines, line)
			}
		}
		if len(summaryLines) > 0 {
			summaryText := summaryStyle.Render("  " + strings.Join(summaryLines, " / "))
			return row1 + "\n\n" + summaryText
		}
	}

	return row1
}

func (dv *DashboardView) renderActivityCalendar() string {
	m := dv.currentMonthly()
	now := dv.Data.Date

	year := now.Year()
	month := now.Month()
	if m.Month != "" {
		t, err := time.Parse("2006-01", strings.ReplaceAll(m.Month, "\u2011", "-"))
		if err == nil {
			year = t.Year()
			month = t.Month()
		}
	}

	dailyHours := make(map[string]float64)
	for _, entry := range m.DailyEntries {
		dailyHours[entry.Date.Format("2006-01-02")] = entry.TotalHours
	}

	// Layout: prefix (5 chars) + 7 cells (2 chars each, no gap)
	// Header: "S " "M " ... (letter + space = 2 chars)
	// Data:   "██" "██" ... (2-char bg block, flush)
	const prefix = "  W  " // 5 chars placeholder for header

	var lines []string

	header := prefix
	for _, d := range []string{"S", "M", "T", "W", "T", "F", "S"} {
		header += d + " "
	}
	lines = append(lines, header)

	firstDay := time.Date(year, month, 1, 0, 0, 0, 0, time.Local)
	start := firstDay
	for start.Weekday() != time.Sunday {
		start = start.AddDate(0, 0, -1)
	}

	day := start
	for w := 0; w < 6; w++ {
		weekHasMonthDay := false
		for d := 0; d < 7; d++ {
			if day.AddDate(0, 0, d).Month() == month {
				weekHasMonthDay = true
				break
			}
		}
		if !weekHasMonthDay {
			break
		}

		row := fmt.Sprintf("  W%-2d", w+1) // 5 chars
		for d := 0; d < 7; d++ {
			if day.Month() != month {
				row += EmptyBlock()
			} else if day.After(now) {
				row += FutureBlock()
			} else {
				row += ActivityBlock(dailyHours[day.Format("2006-01-02")])
			}
			day = day.AddDate(0, 0, 1)
		}
		lines = append(lines, row)
	}

	return strings.Join(lines, "\n")
}

func (dv *DashboardView) monthlyHeader() string {
	m := dv.currentMonthly()
	label := monthLabel(m.Month)
	header := label + " SUMMARY"
	if len(dv.Data.AllMonthly) > 1 {
		left := dimText(" ")
		right := dimText(" ")
		if dv.MonthlyIndex > 0 {
			left = dimText("◀")
		}
		if dv.MonthlyIndex < len(dv.Data.AllMonthly)-1 {
			right = dimText("▶")
		}
		header = left + " " + header + " " + right
	}
	return header
}

func monthLabel(month string) string {
	if month == "" {
		return "Monthly"
	}
	parts := strings.Split(strings.ReplaceAll(month, "\u2011", "-"), "-")
	if len(parts) == 2 {
		return parts[0] + "/" + parts[1] + "月"
	}
	return month
}

// truncateToWidth truncates a string to fit within maxWidth display columns.
func truncateToWidth(s string, maxWidth int) string {
	if lipgloss.Width(s) <= maxWidth {
		return s
	}
	runes := []rune(s)
	for i := len(runes) - 1; i >= 0; i-- {
		candidate := string(runes[:i]) + "…"
		if lipgloss.Width(candidate) <= maxWidth {
			return candidate
		}
	}
	return "…"
}

func dimText(s string) string {
	return lipgloss.NewStyle().Foreground(colorSubtle).Render(s)
}
