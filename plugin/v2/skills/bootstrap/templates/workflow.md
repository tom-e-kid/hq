# Workflow

## Prerequisites

- **`gh` CLI** must be authenticated: `gh auth status` must succeed
- All issue operations (`gh issue view`, `gh issue create`, `gh issue list`, `gh issue close`) require this

## Branch Rules

- **Never work directly on base branches** (`main`, `develop*`) — always create a feature branch
- **Base branch resolution** (used by all skills): `.hq/settings.json` `base_branch` → `git symbolic-ref refs/remotes/origin/HEAD` → `"main"`
  - Most projects need no config — git remote HEAD detection works automatically
  - Set `.hq/settings.json` `{ "base_branch": "<branch>" }` only when an explicit override is needed (e.g., worktree targeting `develop`)

## Before Commit

1. Run `format` command (see Commands table in CLAUDE.md)
2. Verify `build` command passes

## Terminology

- **`hq:task`** — a GitHub Issue (label: `hq:task`) that describes **what** needs to be done. The requirement.
- **`hq:plan`** — a GitHub Issue (label: `hq:plan`) that describes **how** to do it. The implementation plan. One `hq:task` can have multiple `hq:plan` issues.
- **`hq:feedback`** — a GitHub Issue (label: `hq:feedback`) for unresolved problems found during code review or E2E verification. Escalated from local FB files when they cannot be fixed within the current branch.

These are plugin-specific terms. Always use the `hq:` prefix to distinguish from general "task", "plan", or "feedback".

## Issue Hierarchy

```
Milestone (GitHub built-in, optional)
  └── hq:task Issue  — requirement ("what")
        └── hq:plan Issue  — implementation plan ("how")
              ├── ← Closes → PR
              └── hq:feedback Issue(s)  — unresolved problems (Refs #plan)
```

- `hq:task` and `hq:plan` are separate issues (separation of concerns)
- PR uses `Closes #<hq:plan>` to auto-close the plan issue on merge
- PR uses `Refs #<hq:task>` to maintain a link to the requirement
- Labels are created lazily at first use: `gh label create "hq:plan" --description "HQ implementation plan" 2>/dev/null || true`

## `hq:plan`

An `hq:plan` issue is the implementation plan that drives work on a branch. The issue body replaces what was formerly a local "taskfile".

The `hq:plan` issue body should follow this recommended structure:

```markdown
Parent: #<hq:task issue number>

## Plan
<implementation steps>

## Gates
- [ ] Gate 1
- [ ] Gate 2

## Verification
- [ ] Verification item 1
- [ ] Verification item 2
```

- `## Gates` — completion criteria. Checkboxes show progress in the GitHub UI
- `## Verification` — items for E2E testing. The `e2e-web` skill parses this section
- This structure is **recommended, not enforced**. How you create the plan is up to you — what matters is that it lives in a GitHub Issue labeled `hq:plan`

Every `hq:plan` must:

- Be **self-contained** — it survives session clears (it's on GitHub, not local)
- Define **gates** (clear completion criteria) — an `hq:plan` is complete only when all gates pass
- Before checking gates, run `/simplify` to eliminate redundant or unnecessary code

### Focus

**Focus** is a local pointer to the `hq:plan` issue currently driving work. It is stored in `focus.md` within your Claude Code memory directory.

**Format** (frontmatter YAML — no free-text body):

```
---
plan: <hq:plan issue number>
source: <hq:task issue number>
---
```

- `plan` — **MUST**. The `hq:plan` issue number driving current work.
- `source` — **MUST**. The `hq:task` issue number this plan implements. Focus cannot be set without a source.

**Lifecycle**:

- **On start**: save `plan` and `source` to `focus.md` in your Claude Code memory directory. Also write the same values to `.hq/tasks/<branch>/context.md` as a persistent backup (branch name: replace `/` with `-`).
- **On status query**: read `focus.md` from your Claude Code memory directory → run `gh issue view <plan> --json body --jq '.body'` to fetch the plan → report status.
- **On completion**: when a PR is created or all gates pass, remove `focus.md` from your Claude Code memory directory. The PR's `Closes #<plan>` handles issue closure on merge. The `context.md` backup is left in place — it travels with the task folder.

### Focus Resolution

When the user gives a vague instruction (e.g., "the auth task", "issue 42"), resolve the focus by searching in order:

1. **restore from backup** — check `.hq/tasks/<branch>/context.md` for the current branch. If it exists, pre-populate focus from it and confirm with the user: "Restored focus: plan=#X, source=#Y. Correct?" If the user says no, continue to the steps below.
2. **direct issue number** — if the user provides a number, use it directly with `gh issue view <number>` to verify it exists and has the `hq:plan` label.
3. **search** — run `gh issue list --label hq:plan --state open --json number,title` and match against the user's keyword.

If exactly one match: set focus automatically. If multiple matches: show candidates and ask the user to choose. If no match: ask the user to specify the issue number.

## Verification Pipeline

Run the following checks when validating work on a branch — whether completing an `hq:plan`, preparing a PR, or reviewing ad-hoc changes. Focus is not required; all checks operate on the git diff.

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

**Format** — FB files must follow [feedback.md](feedback.md). Read `plan` and `source` values from `focus.md` in your Claude Code memory directory (fallback: `.hq/tasks/<branch>/context.md`) for the frontmatter fields.

### FB Handling Rules (for the root agent after a skill run)

- Read pending FB files and attempt to fix the issues
- Run `format` and `build` commands after fixes
- Re-run the originating skill to verify the fix
- When an FB item is resolved, move its file to `feedbacks/done/`
- Maximum **2 fix attempts** per FB item — if still failing, report to the user
- Do not modify or delete FB files — only move resolved ones to `done/`

### FB Escalation to `hq:feedback`

When creating a PR (`/pr`) or archiving (`/archive`), check for unresolved FB files in `feedbacks/`. If any exist:

1. Show the list of unresolved FBs to the user
2. Ask whether to escalate them as `hq:feedback` issues on GitHub
3. If yes — for each FB, create a GitHub Issue:
   ```
   gh issue create --title "<FB title>" --body "<FB content>\n\nRefs #<plan>" --label "hq:feedback"
   ```
4. Move the escalated FB files to `feedbacks/done/` (tracking moves to GitHub)
5. If no — FB files remain as-is (archived with the task folder if archiving, or left in place if creating a PR)
