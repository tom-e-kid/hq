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
- Define **gates** (clear completion criteria) — a taskfile is complete only when all gates pass
- Before checking gates, run `/simplify` to eliminate redundant or unnecessary code

A taskfile _should_ include a `source` line (`source: <source>#<identifier>`) when practical, but the authoritative source is always `memory/focus.md` — not the taskfile itself.

### Focus

**Focus** is a pointer to the taskfile currently driving work. It is stored in `memory/focus.md`.

**Format** (frontmatter YAML — no free-text body):

```
---
taskfile: <path to taskfile>
source: <origin>#<identifier>
---
```

- `taskfile` — **MUST**. Path to the taskfile driving work.
- `source` — **MUST**. Traceability anchor linking this work to its origin (e.g., `docs/milestones.md#M9`, `github-issue#42`, `user#description`). If the taskfile contains a `source:` line, use it. If not, ask the user. Focus cannot be set without a source.

**Lifecycle**:

- **On start**: save `taskfile` and `source` to `memory/focus.md`. Also write the same values to `.hq/tasks/<branch>/context.md` as a persistent backup (branch name: replace `/` with `-`).
- **On status query**: read `memory/focus.md` → read the referenced taskfile → report status.
- **On completion**: when a PR is created or all gates pass, remove `memory/focus.md`. The `context.md` backup is left in place — it travels with the task folder.

### Focus Resolution

When the user gives a vague instruction (e.g., "M9の作業", "the auth task", "issue 42"), resolve the focus by searching in order:

1. **restore from backup** — check `.hq/tasks/<branch>/context.md` for the current branch. If it exists, pre-populate focus from it and confirm with the user: "Restored focus: taskfile=X, source=Y. Correct?" If the user says no, continue to the steps below.
2. **source match** — scan taskfile frontmatter/content for `source:` lines containing the keyword
3. **filename match** — search taskfile names for the keyword (e.g., `m9-auth.md`)
4. **content match** — grep taskfile bodies for the keyword

If exactly one match: set focus automatically. If multiple matches: show candidates and ask the user to choose. If no match: ask the user to specify the taskfile path.

## Verification Pipeline

Run the following checks when validating work on a branch — whether completing a taskfile, preparing a PR, or reviewing ad-hoc changes. Focus is not required; all checks operate on the git diff.

### Step 1: Static Analysis (parallel)

Launch `security-scanner` and `code-reviewer` agents **simultaneously** via the Agent tool. Both run autonomously and return summaries with report/FB file paths.

- **security-scanner** — security alert detection → report file
- **code-reviewer** — quality review → report + FB files

Wait for both agents to complete before proceeding.

### Step 2: Fix FB Issues

Read pending FB files from both agents. Fix issues, run `format` and `build`, then re-run the originating agent to verify. Follow the FB Handling Rules below.

### Step 3: E2E Verification (interactive)

If the project has a web app, run `/e2e-web` as a skill (interactive — requires user input for setup, login, and verification targets).

### Fallback: Interactive Mode

If you need fine-grained control or mid-scan user interaction, use the skills directly instead of agents:

1. `/security-scan` — pauses on credential detection for user confirmation
2. `/code-review` — warns about uncommitted changes

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

**Format** — FB files must follow [feedback.md](feedback.md). Read `source` and `taskfile` values from `memory/focus.md` (fallback: `.hq/tasks/<branch>/context.md`) for the frontmatter fields.

### FB Handling Rules (for the root agent after a skill run)

- Read pending FB files and attempt to fix the issues
- Run `format` and `build` commands after fixes
- Re-run the originating skill to verify the fix
- When an FB item is resolved, move its file to `feedbacks/done/`
- Maximum **2 fix attempts** per FB item — if still failing, report to the user
- Do not modify or delete FB files — only move resolved ones to `done/`
