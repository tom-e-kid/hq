# Workflow

## Branch Rules

- **Never work directly on base branches** (`main`, `develop*`) — always create a feature branch
- **Base branch resolution** (used by all skills): `.hq/settings.json` `base_branch` → `git symbolic-ref refs/remotes/origin/HEAD` → `"main"`
  - Most projects need no config — git remote HEAD detection works automatically
  - Set `.hq/settings.json` `{ "base_branch": "<branch>" }` only when an explicit override is needed (e.g., worktree targeting `develop`)

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

### Focus

**Focus** is a pointer to the taskfile currently driving work. It is stored in `memory/focus.md` and contains the taskfile path and source — not the task content itself.

- **On start**: save the taskfile path and source to `memory/focus.md`
- **On status query**: read `memory/focus.md` → read the referenced taskfile → report status
- **On completion**: when a PR is created or all gates pass, remove `memory/focus.md`

### Focus Resolution

When the user gives a vague instruction (e.g., "M9の作業", "the auth task", "issue 42"), resolve the focus by searching in order:

1. **source match** — scan taskfile frontmatter/content for `source:` lines containing the keyword
2. **filename match** — search taskfile names for the keyword (e.g., `m9-auth.md`)
3. **content match** — grep taskfile bodies for the keyword

If exactly one match: set focus automatically. If multiple matches: show candidates and ask the user to choose. If no match: ask the user to specify the taskfile path.

## Verification Pipeline

Run the following skills when validating work on a branch — whether completing a taskfile, preparing a PR, or reviewing ad-hoc changes. Focus is not required; all skills operate on the git diff.

1. `/security-scan` — security alert check → report to user, get confirmation (fast, fail-fast)
2. `/code-review` — quality review → fix FB issues
3. `/e2e-web` — end-to-end verification (if the project has a web app)

If any step produces unresolved issues, do not skip ahead. Fix or get user confirmation before continuing.

## Feedback Loop

Skills that perform verification or review may output feedback files (FB) to `.hq/tasks/<branch>/feedbacks/`.

### FB Output Rules (for skills that generate FB files)

**Directory** — branch name: replace `/` with `-` (e.g., `feat/m9-wiki` → `feat-m9-wiki`).

```
.hq/tasks/<branch>/feedbacks/              # pending — files here need action
.hq/tasks/<branch>/feedbacks/done/         # resolved
.hq/tasks/<branch>/feedbacks/screenshots/  # evidence (optional)
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
