---
name: dev
description: >
  This skill should be used when the user asks to "implement a feature",
  "fix a bug", "start development", "plan implementation", or begins
  non-trivial development work that requires branch management, task
  tracking, or multi-step implementation.
---

## Terminology

- **taskfile** — The plan/tracking file at `.hq/tasks/<branch>.md`. One per work branch.
- **memory** — Lessons learned from past mistakes. Project-specific (`.hq/memory.md`) or global (`~/.hq/memory.md`).

## MANDATORY: Before Implementation

Complete ALL steps below before writing any implementation code. No exceptions.

### Step 0: Load Memory

Read and internalize past lessons before starting work.

1. If `~/.hq/memory.md` exists → read it (global rules across all projects)
2. If `.hq/memory.md` exists → read it (project-specific lessons)
3. Keep these lessons in mind throughout the session — they represent mistakes already made and rules to prevent recurrence

### Step 1: Work Branch & Base Branch

1. Run `git branch --show-current` to check the current branch
2. Detect the base branch (see Base Branch Detection below)
3. If on the base branch → **MUST NOT start implementation**
   - Derive a branch name from the task (e.g., `feat/xxx`, `fix/xxx`, `refactor/xxx`)
   - Propose the name to the user and wait for confirmation
   - Create the branch: `git checkout -b <branch>`
4. If already on a work branch → proceed to Step 2

### Step 2: Platform Setup

- If `.xcworkspace` or `.xcodeproj` exists → run `/hq:ios-dev` to prepare `.hq/build/config.sh`
- If `.hq/build/config.sh` already exists → skip

### Step 3: Plan → Taskfile

**NEVER write implementation code without the taskfile existing.**

Choose one path:

**A) Using plan mode** (non-trivial tasks with 3+ steps or architectural decisions):
- Enter plan mode and write the plan to `.claude/plans/` (system constraint)
- **Immediately after exiting plan mode**, before any implementation code:
  1. Copy the plan to the taskfile — follow the Taskfile Template below
  2. Update WIP tracking

**B) Without plan mode** (smaller but still tracked tasks):
- Write the plan directly to the taskfile — follow the Taskfile Template below
- Update WIP tracking

**STOP** — check: Does the taskfile exist? If not, create it NOW.

### Step 4: User Approval Gate

- Present the taskfile contents to the user
- **MUST NOT begin implementation until the user approves the plan**
- If the user requests changes, update the taskfile and re-confirm

## Workflow Guidelines

### Subagent Strategy

- Use subagents liberally to keep main context window clean
- Offload research, exploration, and parallel analysis to subagents
- For complex problems, throw more compute at it via subagents
- One task per subagent for focused execution

### Pre-Commit: Format

Before every commit, detect the project type and format **changed files only**.

1. Get changed files: `git diff --name-only --diff-filter=AM`
2. Detect project type (check in order, first match wins):

| Indicator | Platform | Command |
|---|---|---|
| `go.mod` | Go | `gofmt -w <changed .go files>` |
| `package.json` | Web | Run `format` script if defined (detect pkg manager from lock file: `bun.lockb` → bun, `pnpm-lock.yaml` → pnpm, `yarn.lock` → yarn, else npm) |
| `.xcworkspace` / `.xcodeproj` | iOS | `swift-format -i <changed .swift files>` (skip if not installed) |

3. If no formatter detected, skip silently
4. Stage any formatting changes before committing

### Post-Implementation Commands

- `/hq:code-review` — Self-review changes before creating a PR
- `/hq:pr` — Create or update a GitHub PR for the current branch
- `/hq:close` — Clean up completed taskfiles after merge
- `/hq:memory` — Record a lesson from user feedback to memory

### Execution Principles

- **Demand elegance**: For non-trivial changes, pause and ask "is there a more elegant way?" Skip for simple, obvious fixes
- **Autonomous bug fixing**: Given a bug report, just fix it — point at logs, errors, failing tests, then resolve them. Zero context switching from the user
- **Resilient execution**: If something goes sideways, STOP and re-plan immediately — don't keep pushing

## Taskfile Reference

### Naming Convention

- Taskfiles live at `.hq/tasks/<branch>.md` (branch-name based)
- Get the branch name via `git branch --show-current`
- Replace `/` with `-` in branch names (e.g., `feat/task-tracking` → `feat-task-tracking.md`)

### Taskfile Template

Every taskfile MUST follow this structure:

```markdown
---
status: in_progress
description: <one-line summary>
---

# <Title>

## Plan
<background, goals, and approach — copy from plan mode output if applicable>

## Changes

- [ ] Step 1: ...
- [ ] Step 2: ...
- [ ] Step 3: ...

## Verification

### How to verify
- <what to check and how — plan this BEFORE implementation>

### Results
- <filled in after verification — do NOT mark status: done without this>
```

**Required sections**:
- **Plan**: Background, goals, and implementation approach. When using plan mode (path A), copy the plan here.
- **Changes**: Each step as a `- [ ]` checkbox. Mark `- [x]` as completed.
- **Verification**: "How to verify" (planned before implementation) and "Results" (filled after execution). Never mark `status: done` with an empty Results section.

### WIP Tracking

When creating or updating a taskfile:

1. Read `~/.hq/wip.md` (create if missing with frontmatter only)
2. Get the current branch via `git branch --show-current`
3. If the branch already has an entry, skip
4. Otherwise append a new line:
   ```
   - <project>: <description> (branch: <branch>)
   ```

## Base Branch Detection

Detect the base branch for diffs, PRs, and reviews. Run at Step 1 or when the taskfile is first created.

1. Read `$GIT_ROOT/.hq/settings.json` — if `base_branch` is set, use it and **skip remaining steps**
2. Auto-detect:
   - Run `git branch -a` — if `develop` exists, candidate is `develop`
   - Otherwise run `gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name'`
   - If all fail, fall back to `main`
3. Save the result:
   - If `main` → silently write to `.hq/settings.json`
   - Otherwise → confirm with the user before saving

## Memory

- **`.hq/memory.md`** — Project-specific lessons (default save target)
- **`~/.hq/memory.md`** — Global lessons (save when user says "global" or "cross-project")

When the user corrects a mistake or points out a better approach:

1. Fix the immediate issue first
2. **Before moving on**, run `/hq:memory` to record the lesson
3. Do NOT skip step 2 — this is as important as the fix itself
