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
- **`hq:wip`** — a GitHub Issue modifier label indicating the issue is still being drafted or adjusted. When encountered, pause and confirm with the user before proceeding.

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
- `hq:plan` is created as a **sub-issue** of its parent `hq:task` (GitHub sub-issues API)
- PR uses `Closes #<hq:plan>` to auto-close the plan issue on merge
- PR uses `Refs #<hq:task>` to maintain a link to the requirement
- **Traceability inheritance** — if the source `hq:task` has a milestone or project(s), all generated items (`hq:plan`, PR, `hq:feedback`) must inherit them via `--milestone` / `--project` flags. Exception: `hq:feedback` issues do NOT inherit milestones.
- Labels are created lazily at first use:
  - `gh label create "hq:task" --description "HQ requirement (what to do)" --color "39FF14" 2>/dev/null || true`
  - `gh label create "hq:plan" --description "HQ implementation plan (how to do it)" --color "00D4FF" 2>/dev/null || true`
  - `gh label create "hq:feedback" --description "HQ unresolved feedback" --color "FF073A" 2>/dev/null || true`
  - `gh label create "hq:wip" --description "HQ work in progress — issue still being drafted" --color "FFA500" 2>/dev/null || true`

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

After creating an `hq:plan` issue, register it as a sub-issue of the parent `hq:task`:

```bash
PLAN_ID=$(gh api /repos/{owner}/{repo}/issues/<plan> --jq '.id')
gh api --method POST /repos/{owner}/{repo}/issues/<task>/sub_issues --field sub_issue_id="$PLAN_ID"
```

Every `hq:plan` must:

- Be **self-contained** — it survives session clears (it's on GitHub, not local)
- Define **gates** (clear completion criteria) — an `hq:plan` is complete only when all gates pass
- Before checking gates, run `/simplify` to eliminate redundant or unnecessary code

### Focus

**Focus** is a pointer to the `hq:plan` issue currently driving work. It is stored in two places:

1. **`.hq/tasks/<branch>/context.md`** — deterministic file (branch name: `/` → `-`). Agents and skills resolve focus from this file.
2. **Memory** — a project-type memory entry for cross-session awareness. Lets new sessions know what was in progress.

**context.md format** (frontmatter YAML — no free-text body):

```yaml
---
plan: <hq:plan issue number>
source: <hq:task issue number>
gh:
  task: .hq/tasks/<branch>/gh/task.json
  plan: .hq/tasks/<branch>/gh/plan.md
---
```

- `plan` — **MUST**. The `hq:plan` issue number driving current work.
- `source` — **MUST**. The `hq:task` issue number this plan implements. Focus cannot be set without a source.
- `gh` — paths to the local GitHub issue cache (see Issue Cache section below).

**Lifecycle**:

- **On start**: write `.hq/tasks/<branch>/context.md`. Save focus info to your memory (project type) — include the branch name, plan number, and source number. Do NOT prescribe a specific file name — let the memory system handle storage.
- **On status query**: read `.hq/tasks/<branch>/context.md` → read the plan body from `.hq/tasks/<branch>/gh/plan.md`. If cache not found, fall back to `gh issue view <plan> --json body --jq '.body'` → report status.
- **On completion**: when a PR is created or all gates pass, update your memory to indicate no active task. The PR's `Closes #<plan>` handles issue closure on merge. The `context.md` file is left in place — it travels with the task folder.

### Focus Resolution

When the user gives a vague instruction (e.g., "the auth task", "issue 42"), resolve the focus by searching in order:

1. **context.md** — check `.hq/tasks/<branch>/context.md` for the current branch. If it exists, use it and confirm with the user: "Restored focus: plan=#X, source=#Y. Correct?" If the user says no, continue to the steps below.
2. **memory** — check your memory for active focus info.
3. **direct issue number** — if the user provides a number, check `.hq/tasks/<branch>/gh/` for cached data first. If not cached, use `gh issue view <number>` to verify it exists and has the `hq:plan` label.
4. **search** — run `gh issue list --label hq:plan --state open --json number,title` and match against the user's keyword.

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

**Format** — FB files must follow [feedback.md](feedback.md). Read `plan` and `source` values from `.hq/tasks/<branch>/context.md` (branch path: `/` → `-`) for the frontmatter fields.

### FB Handling Rules (for the root agent after a skill run)

- Read pending FB files and assess each: fix only those that are clearly actionable (bugs, typos, logic errors). Leave design-level or scope-ambiguous FBs as-is for user judgment.
- Run `format` and `build` commands after fixes
- Re-run the originating skill (full review) to verify fixes and catch regressions
- When an FB item is resolved, move its file to `feedbacks/done/`
- Maximum **2 rounds** of the fix → re-verify cycle. After 2 rounds, report all remaining FBs to the user.
- Do not modify or delete FB files — only move resolved ones to `done/`

### FB Escalation to `hq:feedback`

When creating a PR (`/pr`) or archiving (`/archive`), check for unresolved FB files in `feedbacks/`. If any exist:

1. Show the list of unresolved FBs to the user
2. Ask whether to escalate them as `hq:feedback` issues on GitHub
3. If yes — for each FB, create a GitHub Issue:
   ```
   gh issue create --title "<FB title>" --body "<FB content>\n\nRefs #<plan>" --label "hq:feedback" [--project "<project>"]
   ```
4. Move the escalated FB files to `feedbacks/done/` (tracking moves to GitHub)
5. If no — FB files remain as-is (archived with the task folder if archiving, or left in place if creating a PR)
