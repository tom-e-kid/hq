package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/tom-e-kid/hq/tools/hq/internal/config"
	"github.com/tom-e-kid/hq/tools/hq/internal/parser"
)

func runTasks(basePath string, cfg config.Settings, args []string) int {
	// Extract target flags before dispatching
	target, args := extractTargetFlags(args)

	if len(args) > 0 {
		switch args[0] {
		case "add":
			return runTasksAdd(basePath, cfg, target, args[1:])
		case "done":
			return runTasksDone(basePath, cfg, target, args[1:])
		}
	}
	return runTasksList(basePath, cfg, target, args)
}

func runTasksList(basePath string, cfg config.Settings, target targetFlags, args []string) int {
	showAll := false
	jsonOut := false
	for _, a := range args {
		switch a {
		case "--all":
			showAll = true
		case "--json":
			jsonOut = true
		}
	}

	proj := resolveTarget(basePath, target)
	res := resolveTaskResource(cfg, target.role)
	tasksPath := proj.resourcePath(res)

	data, err := os.ReadFile(tasksPath)
	if err != nil {
		if os.IsNotExist(err) {
			if jsonOut {
				fmt.Println("[]")
			} else {
				fmt.Println("No tasks found.")
			}
			return 0
		}
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		return 1
	}

	tasks := parser.ParseTasks(string(data), tasksPath, time.Now())

	if !showAll {
		filtered := tasks[:0]
		for _, t := range tasks {
			if !t.Checked {
				filtered = append(filtered, t)
			}
		}
		tasks = filtered
	}

	if jsonOut {
		enc := json.NewEncoder(os.Stdout)
		enc.SetIndent("", "  ")
		if err := enc.Encode(tasks); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			return 1
		}
		return 0
	}

	// Text output
	label := proj.project
	if proj.org != "" && proj.org != "_" {
		label = proj.org + "/" + proj.project
	}

	openCount := 0
	for _, t := range tasks {
		if !t.Checked {
			openCount++
		}
	}

	if len(tasks) == 0 {
		fmt.Printf("%s (no tasks)\n", label)
		return 0
	}

	fmt.Printf("%s (%d open)\n", label, openCount)
	for _, t := range tasks {
		mark := " "
		if t.Checked {
			mark = "x"
		}
		prefix := ""
		if t.Recurring {
			prefix = t.RecurringRule + " "
		}
		dateStr := ""
		if t.HasDate {
			dateStr = t.Date.Format("2006-01-02") + " "
			if !t.Checked {
				dateStr += fmt.Sprintf("(%dd) ", t.RemainingDays)
			}
		}
		fmt.Printf("  %3d. [%s] %s%s%s\n", t.Line, mark, prefix, dateStr, t.Text)
	}
	return 0
}

func runTasksAdd(basePath string, cfg config.Settings, target targetFlags, args []string) int {
	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, "usage: hq tasks add <text>")
		return 1
	}
	text := strings.Join(args, " ")

	proj := resolveTarget(basePath, target)
	res := resolveTaskResource(cfg, target.role)
	tasksPath := proj.resourcePath(res)

	if err := parser.AddTask(tasksPath, text); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		return 1
	}
	fmt.Printf("Added: %s\n", text)
	return 0
}

func runTasksDone(basePath string, cfg config.Settings, target targetFlags, args []string) int {
	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, "usage: hq tasks done <line>")
		return 1
	}
	lineNum, err := strconv.Atoi(args[0])
	if err != nil {
		fmt.Fprintf(os.Stderr, "invalid line number: %s\n", args[0])
		return 1
	}

	proj := resolveTarget(basePath, target)
	res := resolveTaskResource(cfg, target.role)
	tasksPath := proj.resourcePath(res)

	// Read the task text before toggling for the confirmation message
	data, err := os.ReadFile(tasksPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		return 1
	}
	tasks := parser.ParseTasks(string(data), tasksPath, time.Now())
	var taskText string
	for _, t := range tasks {
		if t.Line == lineNum {
			taskText = t.Text
			break
		}
	}

	if err := parser.ToggleTask(tasksPath, lineNum); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		return 1
	}

	if taskText != "" {
		fmt.Printf("Done: %s\n", taskText)
	} else {
		fmt.Printf("Toggled line %d\n", lineNum)
	}
	return 0
}

// targetFlags holds --project, --inbox, and --role flag values.
type targetFlags struct {
	project string // "org/project" format
	inbox   bool
	role    string
}

// extractTargetFlags extracts --project, --inbox, and --role from args.
func extractTargetFlags(args []string) (targetFlags, []string) {
	var tf targetFlags
	var remaining []string
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--inbox":
			tf.inbox = true
		case "--project":
			if i+1 < len(args) {
				tf.project = args[i+1]
				i++
			}
		case "--role":
			if i+1 < len(args) {
				tf.role = args[i+1]
				i++
			}
		default:
			remaining = append(remaining, args[i])
		}
	}
	return tf, remaining
}

// resolveTaskResource returns the task resource matching the given role, or the default.
func resolveTaskResource(cfg config.Settings, role string) config.Resource {
	if role != "" {
		if r := cfg.ResourceByRole(role); r != nil && r.Type == "tasks" {
			return *r
		}
		fmt.Fprintf(os.Stderr, "unknown task role: %s\n", role)
		os.Exit(1)
	}
	return cfg.DefaultTaskResource()
}

// resolveNotesResource returns the notes resource matching the given role, or the default.
func resolveNotesResource(cfg config.Settings, role string) config.Resource {
	if role != "" {
		if r := cfg.ResourceByRole(role); r != nil && r.Type == "notes" {
			return *r
		}
		fmt.Fprintf(os.Stderr, "unknown notes role: %s\n", role)
		os.Exit(1)
	}
	return cfg.DefaultNotesResource()
}

// resolveTarget resolves the target project based on flags.
func resolveTarget(basePath string, tf targetFlags) resolvedProject {
	if tf.inbox {
		return inboxFallback(basePath)
	}
	if tf.project != "" {
		return resolveByName(basePath, tf.project)
	}
	return resolveProject(basePath)
}

// resolveByName resolves a project by its "org/project" name.
func resolveByName(basePath, name string) resolvedProject {
	parts := strings.SplitN(name, "/", 2)
	if len(parts) != 2 {
		fmt.Fprintf(os.Stderr, "invalid project name: %s (expected org/project)\n", name)
		os.Exit(1)
	}
	dir := filepath.Join(basePath, "projects", parts[0], parts[1])
	if _, err := os.Stat(dir); os.IsNotExist(err) {
		fmt.Fprintf(os.Stderr, "project not found: %s\n", name)
		os.Exit(1)
	}
	return resolvedProject{
		org:        parts[0],
		project:    parts[1],
		projectDir: dir,
	}
}
