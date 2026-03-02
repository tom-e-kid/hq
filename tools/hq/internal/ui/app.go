package ui

import (
	"fmt"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/textinput"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/charmbracelet/x/ansi"
	"github.com/tom-e-kid/hq/tools/hq/internal/config"
	"github.com/tom-e-kid/hq/tools/hq/internal/model"
	"github.com/tom-e-kid/hq/tools/hq/internal/parser"
)

// App is the main Bubble Tea model.
type App struct {
	basePath        string
	cfg             config.Settings
	taskFiles       []parser.TaskFileRole
	dashboard       *DashboardView
	viewport        viewport.Model
	ready           bool
	width           int
	height          int
	wordIndex       int
	monthlyIndex    int
	todoCursor      int
	milestoneCursor int
	focusSection    Section
	addingItem      bool
	addItemSection  Section // which section is in adding mode
	addItemFile     string
	textInput       textinput.Model
	err             error
}

// NewApp creates a new App model.
func NewApp(basePath string, cfg config.Settings) App {
	var taskFiles []parser.TaskFileRole
	for _, r := range cfg.TaskResources() {
		taskFiles = append(taskFiles, parser.TaskFileRole{Name: r.Name, Role: r.Role})
	}
	return App{
		basePath:     basePath,
		cfg:          cfg,
		taskFiles:    taskFiles,
		width:        80,
		height:       24,
		monthlyIndex: -1,
	}
}

type dataLoadedMsg struct {
	data model.DashboardData
	err  error
}

type fileChangedMsg struct{}

type todoToggledMsg struct {
	err error
}

func toggleTodoCmd(filePath string, line int) tea.Cmd {
	return func() tea.Msg {
		err := parser.ToggleTask(filePath, line)
		return todoToggledMsg{err: err}
	}
}

type todoAddedMsg struct {
	err error
}

func addTodoCmd(filePath string, text string) tea.Cmd {
	return func() tea.Msg {
		err := parser.AddTask(filePath, text)
		return todoAddedMsg{err: err}
	}
}

type wordTickMsg struct{}

func loadDataCmd(basePath string, taskFiles []parser.TaskFileRole) tea.Cmd {
	return func() tea.Msg {
		data, err := parser.LoadAll(basePath, time.Now(), taskFiles)
		return dataLoadedMsg{data: data, err: err}
	}
}

func wordTickCmd() tea.Cmd {
	return tea.Tick(10*time.Second, func(time.Time) tea.Msg {
		return wordTickMsg{}
	})
}

var (
	helpStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("#666666"))

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

func (a App) Init() tea.Cmd {
	return tea.Batch(
		loadDataCmd(a.basePath, a.taskFiles),
		tea.WindowSize(),
		WatchFiles(a.basePath),
		wordTickCmd(),
	)
}

func (a App) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	// Text input mode: intercept all key events
	if a.addingItem {
		if keyMsg, ok := msg.(tea.KeyMsg); ok {
			switch keyMsg.String() {
			case "enter":
				text := strings.TrimSpace(a.textInput.Value())
				a.addingItem = false
				if text != "" {
					return a, addTodoCmd(a.addItemFile, text)
				}
				return a, nil
			case "esc":
				a.addingItem = false
				return a, nil
			case "ctrl+c":
				return a, tea.Quit
			default:
				var cmd tea.Cmd
				a.textInput, cmd = a.textInput.Update(msg)
				return a, cmd
			}
		}
		// Non-key messages (cursor blink, etc.): update textinput, then fall through
		var tiCmd tea.Cmd
		a.textInput, tiCmd = a.textInput.Update(msg)
		// For system messages (resize, data load), continue to normal handling below
		switch msg.(type) {
		case tea.WindowSizeMsg, dataLoadedMsg, fileChangedMsg:
			// fall through
		default:
			return a, tiCmd
		}
	}

	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "q", "ctrl+c":
			return a, tea.Quit
		case "r":
			return a, loadDataCmd(a.basePath, a.taskFiles)
		case "tab":
			if a.dashboard != nil {
				a.dashboard.NextSection()
				a.updateViewport()
			}
		case "shift+tab":
			if a.dashboard != nil {
				a.dashboard.PrevSection()
				a.updateViewport()
			}
		case "j", "down":
			if a.dashboard != nil {
				a.dashboard.ScrollDown()
				a.updateViewport()
			}
			return a, nil
		case "k", "up":
			if a.dashboard != nil {
				a.dashboard.ScrollUp()
				a.updateViewport()
			}
			return a, nil
		case "left", "h":
			if a.dashboard != nil && a.dashboard.MonthlyPrev() {
				a.monthlyIndex = a.dashboard.MonthlyIndex
				a.updateViewport()
			}
			return a, nil
		case "right", "l":
			if a.dashboard != nil && a.dashboard.MonthlyNext() {
				a.monthlyIndex = a.dashboard.MonthlyIndex
				a.updateViewport()
			}
			return a, nil
		case " ":
			if a.dashboard == nil {
				return a, nil
			}
			switch a.dashboard.FocusSection {
			case SectionTodo:
				if item, ok := a.dashboard.currentTodoItem(); ok {
					if item.isSeparator {
						return a, nil
					}
					if item.isLabel {
						// Start adding a new todo
						a.addingItem = true
						a.addItemSection = SectionTodo
						a.addItemFile = item.filePath
						a.textInput = textinput.New()
						a.textInput.Prompt = "+ "
						a.textInput.PromptStyle = lipgloss.NewStyle().Foreground(colorGreen)
						a.textInput.Placeholder = "new task..."
						a.textInput.CharLimit = 200
						a.textInput.Width = a.modalInputWidth() - 4
						cmd := a.textInput.Focus()
						return a, cmd
					}
					// Block toggle for recurring tasks
					if item.recurring {
						return a, nil
					}
					// Toggle existing task
					if item.filePath != "" && item.line > 0 {
						a.todoCursor = a.dashboard.TodoCursor
						a.focusSection = a.dashboard.FocusSection
						return a, toggleTodoCmd(item.filePath, item.line)
					}
				}
			case SectionMilestones:
				if item, ok := a.dashboard.currentMilestoneItem(); ok {
					if item.isAddRow {
						// Start adding a new milestone
						a.addingItem = true
						a.addItemSection = SectionMilestones
						a.addItemFile = item.filePath
						a.textInput = textinput.New()
						a.textInput.Prompt = "+ "
						a.textInput.PromptStyle = lipgloss.NewStyle().Foreground(colorGreen)
						a.textInput.Placeholder = "YYYY-MM-DD description..."
						a.textInput.CharLimit = 200
						a.textInput.Width = a.modalInputWidth() - 4
						cmd := a.textInput.Focus()
						return a, cmd
					}
					// Block toggle for recurring milestones
					if item.milestoneIdx >= 0 && item.milestoneIdx < len(a.dashboard.Data.Milestones) {
						ms := a.dashboard.Data.Milestones[item.milestoneIdx]
						if ms.Recurring {
							return a, nil
						}
					}
					// Toggle existing milestone
					if item.filePath != "" && item.line > 0 {
						a.milestoneCursor = a.dashboard.MilestoneCursor
						a.focusSection = a.dashboard.FocusSection
						return a, toggleTodoCmd(item.filePath, item.line)
					}
				}
			}
			return a, nil
		}

	case tea.WindowSizeMsg:
		a.width = msg.Width
		a.height = msg.Height
		footerH := 1
		if !a.ready {
			a.viewport = viewport.New(msg.Width, msg.Height-footerH)
			a.ready = true
		} else {
			a.viewport.Width = msg.Width
			a.viewport.Height = msg.Height - footerH
		}
		if a.addingItem {
			a.textInput.Width = a.modalInputWidth() - 4
		}
		if a.dashboard != nil {
			a.dashboard.Width = msg.Width
			a.dashboard.Height = msg.Height - footerH
			a.updateViewport()
		}

	case dataLoadedMsg:
		if msg.err != nil {
			a.err = msg.err
			return a, nil
		}
		a.err = nil
		h := a.height
		if h > 1 {
			h -= 1 // footer
		}
		a.dashboard = NewDashboardView(msg.data, a.width, h)
		a.dashboard.WordIndex = a.wordIndex
		if a.monthlyIndex < 0 {
			a.monthlyIndex = defaultMonthlyIndex(msg.data.AllMonthly, time.Now())
		} else if len(msg.data.AllMonthly) > 0 && a.monthlyIndex >= len(msg.data.AllMonthly) {
			a.monthlyIndex = len(msg.data.AllMonthly) - 1
		}
		a.dashboard.MonthlyIndex = a.monthlyIndex
		a.dashboard.TodoCursor = a.todoCursor
		a.dashboard.MilestoneCursor = a.milestoneCursor
		a.dashboard.FocusSection = a.focusSection
		a.updateViewport()

	case wordTickMsg:
		if a.dashboard != nil && len(a.dashboard.Data.Words) > 0 {
			a.wordIndex = (a.wordIndex + 1) % len(a.dashboard.Data.Words)
			a.dashboard.WordIndex = a.wordIndex
			a.updateViewport()
		}
		return a, wordTickCmd()

	case todoToggledMsg:
		if msg.err != nil {
			a.err = msg.err
			return a, nil
		}
		return a, loadDataCmd(a.basePath, a.taskFiles)

	case todoAddedMsg:
		if msg.err != nil {
			a.err = msg.err
			return a, nil
		}
		return a, loadDataCmd(a.basePath, a.taskFiles)

	case fileChangedMsg:
		return a, tea.Batch(loadDataCmd(a.basePath, a.taskFiles), WatchFiles(a.basePath))

	case tea.MouseMsg:
		if msg.Button == tea.MouseButtonLeft && msg.Action == tea.MouseActionPress {
			if a.dashboard != nil {
				// Translate screen Y to content Y (account for viewport scroll)
				contentY := msg.Y + a.viewport.YOffset
				if sec := a.dashboard.SectionAtY(contentY); sec >= 0 {
					a.dashboard.FocusSection = sec
					a.focusSection = sec
					a.updateViewport()
				}
			}
		}
		return a, nil
	}

	var cmd tea.Cmd
	a.viewport, cmd = a.viewport.Update(msg)
	return a, cmd
}

func (a *App) updateViewport() {
	if a.dashboard != nil {
		a.viewport.SetContent(a.dashboard.Render())
		a.todoCursor = a.dashboard.TodoCursor
		a.milestoneCursor = a.dashboard.MilestoneCursor
		a.focusSection = a.dashboard.FocusSection
	}
}

func (a App) View() string {
	if a.err != nil {
		return "Error: " + a.err.Error() + "\n\nPress q to quit."
	}
	if !a.ready || a.dashboard == nil {
		return "Loading..."
	}
	footer := helpStyle.Render(" q:quit  r:refresh  Tab:section  j/k:scroll  ←/→:month  ␣:toggle/add")
	bg := a.viewport.View() + "\n" + footer
	if a.addingItem {
		return overlayCenter(bg, a.renderModal(), a.width, a.height)
	}
	return bg
}

// modalInputWidth calculates the text input width for the modal dialog.
func (a App) modalInputWidth() int {
	w := a.width * 55 / 100
	if w < 40 {
		w = 40
	}
	if w > 80 {
		w = 80
	}
	return w
}

// renderModal builds a bordered modal box with title, text input, and help text.
func (a App) renderModal() string {
	w := a.modalInputWidth()

	title := "New Task"
	if a.addItemSection == SectionMilestones {
		title = "New Milestone"
	}

	content := modalTitleStyle.Render(title) + "\n\n" +
		a.textInput.View() + "\n\n" +
		modalHelpStyle.Render("Enter: confirm  Esc: cancel")

	return modalBorderStyle.Width(w).Render(content)
}

// overlayCenter composites fg (modal) centered on top of bg (dashboard).
// Each affected line is split into left/right background parts with the modal
// in the middle, preserving ANSI escape sequences.
func overlayCenter(bg, fg string, width, height int) string {
	bgLines := strings.Split(bg, "\n")
	fgLines := strings.Split(fg, "\n")

	for len(bgLines) < height {
		bgLines = append(bgLines, "")
	}
	if len(bgLines) > height {
		bgLines = bgLines[:height]
	}

	// Use ansi.StringWidth consistently with Truncate/TruncateLeft
	fgWidth := 0
	for _, l := range fgLines {
		if w := ansi.StringWidth(l); w > fgWidth {
			fgWidth = w
		}
	}

	startY := (height - len(fgLines)) / 2
	if startY < 0 {
		startY = 0
	}
	startX := (width - fgWidth) / 2
	if startX < 0 {
		startX = 0
	}

	for i, fgLine := range fgLines {
		y := startY + i
		if y >= 0 && y < len(bgLines) {
			bgLine := bgLines[y]
			fgW := ansi.StringWidth(fgLine)

			// Left: truncate bg to startX, pad if bg is shorter
			left := ansi.Truncate(bgLine, startX, "")
			if lw := ansi.StringWidth(left); lw < startX {
				left += strings.Repeat(" ", startX-lw)
			}

			// Right: skip past the modal area
			right := ansi.TruncateLeft(bgLine, startX+fgW, "")

			bgLines[y] = left + fgLine + right
		}
	}

	return strings.Join(bgLines, "\n")
}

func defaultMonthlyIndex(months []model.MonthlyData, now time.Time) int {
	if len(months) == 0 {
		return 0
	}
	current := fmt.Sprintf("%d-%02d", now.Year(), int(now.Month()))
	for i, m := range months {
		normalized := strings.ReplaceAll(m.Month, "\u2011", "-")
		if normalized == current {
			return i
		}
	}
	return len(months) - 1
}
