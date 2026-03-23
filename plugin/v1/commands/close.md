---
description: "Archive task files and clean up branches"
---

Archive task files in `.hq/tasks/` and clean up associated branches. Follow these steps strictly.

## Steps

### 1. List task files

Glob `.hq/tasks/*.md`.

- If no files found: report "No task files found" and stop

### 2. Display summary of each file

Read only the frontmatter of each task file and display the following:

- File name
- status (from frontmatter, or "unknown" if missing)
- description (from frontmatter)

Example:
```
| # | File | Status | Description |
|---|------|--------|-------------|
| 1 | feat-auth.md | in_progress | Add authentication |
| 2 | fix-login.md | done | Fix login bug |
```

### 3. Select files to archive

Use AskUserQuestion to let the user choose which files to archive.

- Options: present each task file as a choice (multiSelect: true)
- Include a "Cancel" option
- If Cancel is selected: report "Cleanup cancelled" and stop

### 4. Set final status

For each selected file whose `status` is not already a final status (`done`, `skipped`, `cancelled`), use AskUserQuestion to let the user choose:

- **done** — completed
- **skipped** — not started, decided not to do
- **cancelled** — started but abandoned

Update the frontmatter `status` field accordingly.

### 5. Check PR status for selected files

For each selected file, derive the branch name (filename without `.md`, replacing `-` back to `/` where it matches a local branch):

1. Run `git branch --list` to get all local branches
2. For each selected task file, find the matching local branch
   - Filename `feat-auth.md` could match branch `feat/auth` or `feat-auth`
   - Check against actual local branches to resolve
3. For each matched branch, run `gh pr list --head <branch> --json state --jq '.[0].state'`
   - If the PR state is `MERGED`: OK
   - If the PR state is `OPEN` or no PR exists: warn the user (e.g., "feat/auth: PR not merged yet") but do NOT block archival

### 6. Archive selected files and delete local branches

1. Detect the base branch from `$GIT_ROOT/.hq/settings.json` (`base_branch` field), falling back to `main`
2. If the current branch is one of the branches to be archived, run `git checkout <base_branch>` first
3. Move selected task files to `$GIT_ROOT/.hq/tasks/done/` (create the directory if it doesn't exist)
4. For each matched local branch, run `git branch -d <branch>`
   - If `-d` fails (unmerged), report the failure but continue with remaining branches

### 7. Update wip.md accordingly

Read `~/.hq/wip.md`.

- Find rows matching the archived task files' branch names
  - Match the filename (without extension) against the Branch column
- Remove matching rows using Edit
- If no matching rows exist, skip

### 8. Report results

Report the following:
- Number and names of archived files (moved to `.hq/tasks/done/`) with their final status
- Number of local branches deleted (and any that failed)
- Number of entries removed from wip.md
