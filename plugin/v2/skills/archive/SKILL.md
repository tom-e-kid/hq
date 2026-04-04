---
name: archive
description: >
  Archive completed task artifacts. Moves task folders to done/ or deletes them,
  closes the hq:plan issue, escalates unresolved FB files, and clears focus from memory.
allowed-tools: Read, Glob, Bash(ls *), Bash(mv .hq/tasks/*), Bash(rm -rf .hq/tasks/*), Bash(mkdir -p .hq/tasks/*), Bash(gh *), Write
---

## Context

- Project root: !`git rev-parse --show-toplevel`
- Focus: !`bash "${CLAUDE_PLUGIN_ROOT}/plugin/v2/scripts/read-context.sh"`
- Task folders: !`ls -1 .hq/tasks/ 2>/dev/null | grep -v '^done$' || echo "none"`
- Archived folders: !`ls -1 .hq/tasks/done/ 2>/dev/null || echo "none"`

## Instructions

### Case 1: Focus exists

If `focus.md` exists in your Claude Code memory directory:

1. Read `focus.md` from Claude Code memory directory. Extract `plan` and `source` (GitHub issue numbers).
2. Show the `hq:plan` issue info: `gh issue view <plan> --json title,state --jq '"#" + (.number|tostring) + " " + .title + " (" + .state + ")"'`
3. Determine the corresponding task folder in `.hq/tasks/` from the branch name (branch path: `/` → `-`)
4. **Escalate unresolved FB** — check `feedbacks/` for pending FB files:
   - If unresolved FBs exist, show the list to the user
   - Ask whether to create `hq:feedback` issues on GitHub for each
   - If yes — for each FB: `gh issue create --title "<FB title>" --body "<FB content>\n\nRefs #<plan>" --label "hq:feedback"`, then move to `feedbacks/done/`
5. Ask the user:
   - **"Archive"** — move `.hq/tasks/<branch>/` to `.hq/tasks/done/<branch>/`
   - **"Delete"** — remove `.hq/tasks/<branch>/` entirely
   - **"Cancel"** — do nothing
6. Execute the chosen action
7. Close the `hq:plan` issue: `gh issue close <plan>`
8. Remove `focus.md` from your Claude Code memory directory
9. Report what was done

### Case 2: No focus, but task folders exist

If `focus.md` does not exist in Claude Code memory but `.hq/tasks/` contains folders (excluding `done/`):

1. List all task folders with their contents summary (number of FB files, reports, etc.)
2. Ask the user to select one or more folders
3. For each selected folder, check for unresolved FB files and offer `hq:feedback` escalation (same as Case 1 step 4)
4. For each selected folder, ask:
   - **"Archive"** — move to `.hq/tasks/done/`
   - **"Delete"** — remove entirely
5. Execute and report

### Case 3: Nothing to archive

If no focus and no task folders: report "Nothing to archive" and stop.

## Rules

- Always ask before moving or deleting — never auto-archive
- When moving to `done/`, create `.hq/tasks/done/` if it doesn't exist
- If a folder with the same name already exists in `done/`, append a timestamp suffix (e.g., `feat-auth-20260323-1430`)
- Only remove `focus.md` from Claude Code memory if the user chose Archive or Delete (not Cancel)
