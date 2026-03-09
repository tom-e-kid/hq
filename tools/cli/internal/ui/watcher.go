package ui

import (
	"os"
	"path/filepath"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/fsnotify/fsnotify"
	"github.com/tom-e-kid/hq/tools/cli/internal/config"
)

// WatchFiles watches markdown files for changes and sends fileChangedMsg.
// Each invocation creates a watcher that fires once after debounce, then closes.
func WatchFiles(basePath string) tea.Cmd {
	return func() tea.Msg {
		watcher, err := fsnotify.NewWatcher()
		if err != nil {
			return nil
		}

		// Watch directories that contain our data sources
		dirs := []string{
			filepath.Join(basePath, "logs"),
			filepath.Join(basePath, "projects"),
		}

		// Also watch ~/.hq/ for wip.md changes
		if hqDir := config.HQDir(); hqDir != "" {
			dirs = append(dirs, hqDir)
		}

		for _, dir := range dirs {
			addDirRecursive(watcher, dir)
		}

		// Debounce: collect events, fire once after 300ms of quiet
		var debounceTimer *time.Timer
		var debounceC <-chan time.Time

		for {
			select {
			case event, ok := <-watcher.Events:
				if !ok {
					watcher.Close()
					return nil
				}
				if !strings.HasSuffix(event.Name, ".md") {
					continue
				}
				if event.Op&(fsnotify.Write|fsnotify.Create) == 0 {
					continue
				}

				if debounceTimer != nil {
					debounceTimer.Stop()
				}
				debounceTimer = time.NewTimer(300 * time.Millisecond)
				debounceC = debounceTimer.C

			case <-debounceC:
				watcher.Close()
				return fileChangedMsg{}

			case _, ok := <-watcher.Errors:
				if !ok {
					watcher.Close()
					return nil
				}
			}
		}
	}
}

func addDirRecursive(watcher *fsnotify.Watcher, dir string) {
	filepath.Walk(dir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return nil
		}
		if info.IsDir() {
			watcher.Add(path)
		}
		return nil
	})
}
