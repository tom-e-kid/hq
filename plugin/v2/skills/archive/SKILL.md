---
name: archive
description: >
  Archive completed task artifacts. Moves task folders to done/ or deletes them,
  and clears focus from memory.
allowed-tools: Read, Glob, Bash(mv *), Bash(rm *), Bash(ls *), Bash(mkdir *), Write(memory/*)
---

## Context

- Project root: !`git rev-parse --show-toplevel`
- Focus: !`cat memory/focus.md 2>/dev/null || echo "none"`
- Task folders: !`ls -1 .hq/tasks/ 2>/dev/null | grep -v '^done$' || echo "none"`
- Archived folders: !`ls -1 .hq/tasks/done/ 2>/dev/null || echo "none"`

## Instructions

### Case 1: Focus exists

If `memory/focus.md` exists:

1. Read `memory/focus.md` frontmatter and show the `taskfile` and `source` fields
2. Determine the corresponding task folder in `.hq/tasks/` from the branch name
3. Ask the user:
   - **"Archive"** — move `.hq/tasks/<branch>/` to `.hq/tasks/done/<branch>/`
   - **"Delete"** — remove `.hq/tasks/<branch>/` entirely
   - **"Cancel"** — do nothing
4. Execute the chosen action
5. Remove `memory/focus.md`
6. Report what was done

### Case 2: No focus, but task folders exist

If `memory/focus.md` does not exist but `.hq/tasks/` contains folders (excluding `done/`):

1. List all task folders with their contents summary (number of FB files, reports, etc.)
2. Ask the user to select one or more folders
3. For each selected folder, ask:
   - **"Archive"** — move to `.hq/tasks/done/`
   - **"Delete"** — remove entirely
4. Execute and report

### Case 3: Nothing to archive

If no focus and no task folders: report "Nothing to archive" and stop.

## Rules

- Always ask before moving or deleting — never auto-archive
- When moving to `done/`, create `.hq/tasks/done/` if it doesn't exist
- If a folder with the same name already exists in `done/`, append a timestamp suffix (e.g., `feat-auth-20260323-1430`)
- Only remove `memory/focus.md` if the user chose Archive or Delete (not Cancel)
