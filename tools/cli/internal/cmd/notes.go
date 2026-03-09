package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/tom-e-kid/hq/tools/cli/internal/config"
	"github.com/tom-e-kid/hq/tools/cli/internal/parser"
)

func runNotes(basePath string, cfg config.Settings, args []string) int {
	target, args := extractTargetFlags(args)

	if len(args) > 0 {
		switch args[0] {
		case "view":
			return runNotesView(basePath, cfg, target, args[1:])
		case "add":
			return runNotesAdd(basePath, cfg, target, args[1:])
		case "copy":
			return runNotesCopy(basePath, cfg, target, args[1:])
		}
	}
	return runNotesList(basePath, cfg, target, args)
}

func runNotesList(basePath string, cfg config.Settings, target targetFlags, args []string) int {
	jsonOut := false
	for _, a := range args {
		if a == "--json" {
			jsonOut = true
		}
	}

	proj := resolveTarget(basePath, target)

	// Without --role: list all notes resources; with --role: single resource
	var notesDirs []string
	if target.role != "" {
		res := resolveNotesResource(cfg, target.role)
		notesDirs = []string{proj.resourcePath(res)}
	} else {
		notesDirs = proj.resourcePaths(cfg, "notes")
	}

	notes, err := parser.ListNotes(notesDirs)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		return 1
	}

	if jsonOut {
		enc := json.NewEncoder(os.Stdout)
		enc.SetIndent("", "  ")
		if err := enc.Encode(notes); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			return 1
		}
		return 0
	}

	if len(notes) == 0 {
		fmt.Println("No notes found.")
		return 0
	}

	for _, n := range notes {
		title := n.Title
		if title == "" {
			title = n.FileName
		}
		line := fmt.Sprintf("  %s  %s", n.Date, title)
		if n.Summary != "" {
			line += "  — " + n.Summary
		}
		fmt.Println(line)
	}
	return 0
}

func runNotesView(basePath string, cfg config.Settings, target targetFlags, args []string) int {
	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, "usage: hq notes view <file>")
		return 1
	}

	fileName := args[0]

	proj := resolveTarget(basePath, target)

	var notesDirs []string
	if target.role != "" {
		res := resolveNotesResource(cfg, target.role)
		notesDirs = []string{proj.resourcePath(res)}
	} else {
		notesDirs = proj.resourcePaths(cfg, "notes")
	}

	// Search for the file in notes dirs
	for _, dir := range notesDirs {
		path := dir + "/" + fileName
		data, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		fmt.Print(string(data))
		return 0
	}

	fmt.Fprintf(os.Stderr, "note not found: %s\n", fileName)
	return 1
}

func runNotesAdd(basePath string, cfg config.Settings, target targetFlags, args []string) int {
	var title, body string
	var tags []string

	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--title":
			if i+1 < len(args) {
				title = args[i+1]
				i++
			}
		case "--body":
			if i+1 < len(args) {
				body = args[i+1]
				i++
			}
		case "--tags":
			if i+1 < len(args) {
				tags = strings.Split(args[i+1], ",")
				i++
			}
		}
	}

	if title == "" {
		fmt.Fprintln(os.Stderr, "usage: hq notes add --title <title> --body <body> [--tags t1,t2] [--role <role>]")
		return 1
	}

	proj := resolveTarget(basePath, target)
	res := resolveNotesResource(cfg, target.role)
	targetDir := proj.resourcePath(res)

	path, err := parser.CreateNote(targetDir, title, body, tags, time.Now())
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		return 1
	}
	fmt.Printf("Created: %s\n", path)
	return 0
}

func runNotesCopy(basePath string, cfg config.Settings, target targetFlags, args []string) int {
	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, "usage: hq notes copy <file|dir> [--inbox | --project <org/project>] [--role <role>]")
		return 1
	}

	source := args[0]

	// Resolve to absolute path
	if !filepath.IsAbs(source) {
		cwd, err := os.Getwd()
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			return 1
		}
		source = filepath.Join(cwd, source)
	}

	proj := resolveTarget(basePath, target)
	res := resolveNotesResource(cfg, target.role)
	targetDir := proj.resourcePath(res)

	dest, err := parser.CopyNote(targetDir, source)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		return 1
	}
	fmt.Printf("Copied: %s\n", dest)
	return 0
}
