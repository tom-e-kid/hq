package cmd

import (
	"fmt"
	"os"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/tom-e-kid/hq/tools/hq/internal/config"
	"github.com/tom-e-kid/hq/tools/hq/internal/ui"
)

func runUI(basePath string, cfg config.Settings) int {
	app := ui.NewApp(basePath, cfg)
	p := tea.NewProgram(app, tea.WithAltScreen(), tea.WithMouseCellMotion())
	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		return 1
	}
	return 0
}
