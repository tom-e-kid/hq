# Workflow

## Branch Rules

- **Never work directly on base branches** (`main`, `develop*`) — always create a feature branch

## Before Commit

1. Run `format` command (see Commands table in CLAUDE.md)
2. Verify `build` command passes

## Taskfile

A **taskfile** is any document that drives implementation — markdown plan files, Claude Code plan mode, or any structured task description. The term is format-agnostic; what matters is the content.

Every taskfile must:

- Be **self-contained** — it survives session clears
- Include a **source** line: `source: <source>#<unique-identifier>`
  - Use frontmatter when the format supports it
  - Examples: `source: docs/milestones.md#M9`, `source: github-issue#42`
- Define **gates** (clear completion criteria) — a taskfile is complete only when all gates pass
- Before checking gates, run `/simplify` to eliminate redundant or unnecessary code

The `source` line is the traceability anchor — it links taskfiles, commits, and PRs back to the originating requirement or issue.

### Active Taskfile

Track the currently active taskfile in project memory (`memory/active_taskfile.md`):

- **On start**: when beginning work on a taskfile, save its path and source to `active_taskfile.md`
- **On status query**: when asked "what am I working on?" or similar, read `active_taskfile.md` → read the taskfile → report status
- **On completion**: when a PR is created or all gates pass, remove `active_taskfile.md`

## Feedback Loop

Skills that perform verification or review may output feedback files (FB) to `.hq/<branch>/feedbacks/`.

### FB Output Rules (for skills that generate FB files)

**Directory** — branch name: replace `/` with `-` (e.g., `feat/m9-wiki` → `feat-m9-wiki`).

```
.hq/<branch>/feedbacks/              # pending — files here need action
.hq/<branch>/feedbacks/done/         # resolved
.hq/<branch>/feedbacks/screenshots/  # evidence (optional)
```

**Numbering** — check existing files in `feedbacks/` and `feedbacks/done/` to determine the next number. Format: `FB001.md`, `FB002.md`, etc. (zero-padded to 3 digits).

**Format** — FB files must follow [feedback.md](feedback.md). Frontmatter with `source` and `taskfile` fields ensures traceability back to the originating requirement.

### FB Handling Rules (for the root agent after a skill run)

- Read pending FB files and attempt to fix the issues
- Run `format` and `build` commands after fixes
- Re-run the originating skill to verify the fix
- When an FB item is resolved, move its file to `feedbacks/done/`
- Maximum **2 fix attempts** per FB item — if still failing, report to the user
- Do not modify or delete FB files — only move resolved ones to `done/`
