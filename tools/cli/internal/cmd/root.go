package cmd

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/tom-e-kid/hq/tools/cli/internal/config"
)

// Run is the main entry point for the hq CLI.
// It dispatches to the appropriate subcommand.
func Run() int {
	args := os.Args[1:]

	// Extract --path flag from anywhere in args
	basePath, args := extractPathFlag(args)

	cfg := config.Load()

	// Resolve basePath: --path > settings.json > directory walk
	if basePath == "" {
		if dir := cfg.DataDir; dir != "" {
			basePath = dir
		}
	}
	if basePath == "" {
		basePath = findRepoRoot()
	}

	sub := ""
	if len(args) > 0 {
		sub = args[0]
	}

	switch sub {
	case "", "ui":
		return runUI(basePath, cfg)
	case "monthly":
		return runMonthly(basePath, args[1:])
	case "tasks":
		return runTasks(basePath, cfg, args[1:])
	case "notes":
		return runNotes(basePath, cfg, args[1:])
	case "milestones":
		return runMilestones(basePath, args[1:])
	case "help", "--help", "-h":
		printHelp()
		return 0
	default:
		fmt.Fprintf(os.Stderr, "unknown command: %s\n\n", sub)
		printHelp()
		return 1
	}
}

// extractPathFlag extracts --path <dir> from args, returning the path and remaining args.
func extractPathFlag(args []string) (string, []string) {
	var remaining []string
	var path string
	for i := 0; i < len(args); i++ {
		if args[i] == "--path" && i+1 < len(args) {
			path = args[i+1]
			i++ // skip next
		} else {
			remaining = append(remaining, args[i])
		}
	}
	return path, remaining
}

// findRepoRoot walks up from cwd looking for the hq repo root
// (identified by having both logs/ and projects/ directories).
func findRepoRoot() string {
	dir, err := os.Getwd()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
	for {
		if isRepoRoot(dir) {
			return filepath.Join(dir, "db")
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	fmt.Fprintln(os.Stderr, "Error: could not find hq repo root (no db/ found).")
	fmt.Fprintln(os.Stderr, "Run from inside the repo, or use --path.")
	os.Exit(1)
	return ""
}

func isRepoRoot(dir string) bool {
	info, err := os.Stat(filepath.Join(dir, "db"))
	return err == nil && info.IsDir()
}

func printHelp() {
	fmt.Print(`hq - HQ command line tool

Usage:
  hq [command] [options]

Commands:
  ui                    Launch the TUI dashboard (default when no command given)
  monthly [YYYY.MM]     Show monthly time summary (defaults to current month)
  tasks                 List, add, or complete tasks
  notes                 List, view, or add notes
  milestones            List, add, or complete milestones
  help                  Show this help message

Global Options:
  --path <dir>          Path to HQ data directory (overrides ~/.hq/settings.json)

Monthly:
  hq monthly              Current month summary
  hq monthly 2026.02      Specific month summary
  hq monthly --json        Output as JSON

Tasks:
  hq tasks                List open tasks (project auto-detected from cwd)
  hq tasks --all          Include completed tasks
  hq tasks --json         Output as JSON
  hq tasks --inbox        Target inbox tasks
  hq tasks --project <org/project>  Target specific project
  hq tasks --role <role>  Target specific task resource (e.g. backlog)
  hq tasks add <text>     Add a new task
  hq tasks done <line>    Mark task as done (use line number from task list)

  Dated/recurring syntax (use with 'add'):
    YYYY-MM-DD <text>        Task with deadline (e.g. 2026-03-15 Submit report)
    @monthly <day> <text>    Every month on <day> (e.g. @monthly 10 Pay invoice)
    @month-end <text>        Last day of every month
    @yearly <MM-DD> <text>   Every year on MM-DD (e.g. @yearly 03-15 Tax filing)
    @weekly <dow> <text>     Every week on <dow> (mon|tue|wed|thu|fri|sat|sun)

Notes:
  hq notes                List notes (project auto-detected from cwd)
  hq notes --json         Output as JSON
  hq notes --inbox        Target inbox notes
  hq notes --project <org/project>  Target specific project
  hq notes --role <role>  Target specific notes resource (e.g. ideas)
  hq notes view <file>    View a note
  hq notes add --title <t> --body <b> [--tags t1,t2] [--role <role>]

Milestones:
  hq milestones              List open milestones
  hq milestones --all        Include completed milestones
  hq milestones --json       Output as JSON
  hq milestones add <text>   Add a new milestone (optionally prefix with YYYY-MM-DD)
  hq milestones done <line>  Mark milestone as done (use line number from list)

  Recurring syntax (use with 'add'):
    @monthly <day>           Every month on <day> (e.g. @monthly 10)
    @month-end               Last day of every month
    @yearly <MM-DD>          Every year on MM-DD (e.g. @yearly 03-15)
    @weekly <dow>            Every week on <dow> (mon|tue|wed|thu|fri|sat|sun)

Examples:
  hq                         Launch TUI dashboard
  hq monthly 2026.02 --json  February 2026 summary as JSON
  hq tasks                   Show open tasks for current project
  hq tasks --inbox           Show inbox tasks
  hq tasks add "Fix login"   Add task to current project's tasks.md
  hq tasks done 8            Complete task at line 8
  hq notes --inbox           List inbox notes
  hq notes add --title "Idea" --body "Some content" --inbox
  hq tasks --role backlog --inbox  Show inbox backlog tasks
  hq notes --role ideas --inbox    List inbox ideas
`)
}
