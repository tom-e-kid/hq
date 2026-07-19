---
name: archive
description: Safely close the current work branch — done mode (PR merged → tasks/done/) or cancel mode (PR closed without merge → tasks/canceled/)
allowed-tools: Read, Glob, Bash(git:*), Bash(gh:*), Bash(bash:*), Bash(ls:*), Bash(mv:*), Bash(mkdir:*), TaskCreate, TaskUpdate
---

# ARCHIVE — Safe Branch Closure

This command closes out the current work branch in one of two modes:

| Mode | Trigger | Precondition | Folder destination | PR close |
|---|---|---|---|---|
| **done** (default) | `/hq:archive` | PR is `MERGED` | `.hq/tasks/done/<branch-dir>/` | n/a (already merged) |
| **cancel** | `/hq:archive cancel` | PR is `OPEN` / `CLOSED` / absent (anything except `MERGED`) | `.hq/tasks/canceled/<branch-dir>/` | `gh pr close` (when still open) |

The table above is the authoritative mode reference. The plan is a local file that travels with the archived folder — there is no plan Issue to close in either mode.

**Invoked two ways in the loop-centric V3 world**: (a) directly by the user as `/hq:archive [cancel]`, and (b) as the loop's J8 safe-cancel subroutine — `/hq:loop` Stage 4 reads `commands/archive.md` and executes its **cancel mode** when the user aborts a diverging run (it tolerates the no-PR case). Both paths run the same phases below.

**Security**: This command deletes the local branch and (in cancel mode) closes the PR on GitHub. It never pushes, never force-pushes, never deletes remote branches, and never touches branches other than the current feature branch.

**`hq:workflow`** — shorthand for `${CLAUDE_PLUGIN_ROOT}/plugin/v3/rules/workflow.md` (plugin-internal source of truth). Read it with the Read tool when this command starts so all phases have Focus, FB Lifecycle, etc. available. All `hq:workflow § <name>` citations refer to sections of that file.

## Argument Parsing

Parse `$ARGUMENTS`:

- Empty → **done mode**
- `cancel` (case-insensitive, trimmed) → **cancel mode**
- Anything else → ABORT with usage: `Usage: /hq:archive [cancel]`

Hold the resolved mode in conversation state — every subsequent phase branches on it.

## Progress Tracking

Use Claude Code's task UI (`TaskCreate` / `TaskUpdate`). Create all phases as tasks at the start:

| Task subject | activeForm |
|---|---|
| Resolve focus | Resolving focus |
| Pre-check: PR state | Checking PR state |
| Pre-check: pending FBs | Checking pending FBs |
| Close PR (cancel only) | Closing PR |
| Archive task folder | Archiving task folder |
| Clean up branch | Cleaning up branch |
| Report results | Reporting results |

Set each to `in_progress` when starting and `completed` when done. If a pre-check aborts the command, mark remaining phases as `completed` with a brief note and stop. The "Close PR" task is `completed` with note `n/a (done mode)` when running in done mode.

## Context

- Branch: !`git branch --show-current 2>/dev/null || echo "(detached)"`
- Focus: !`bash "${CLAUDE_PLUGIN_ROOT}/plugin/v3/scripts/read-context.sh"`

## Phase 1: Resolve Focus

Read `.hq/tasks/<branch-dir>/context.md` for the **current branch** (branch-dir = branch name with `/` → `-`). Extract:

- `source` — `hq:task` Issue number (may be absent — plans without a parent task)
- `branch` — original branch name (should match current branch)
- `base_branch` — the branch this feature branch was created from (captured at execute-protocol Phase 3 — see `hq:workflow § Focus`). **Hold this in conversation state** — Phase 5 archives `context.md` away, and Phase 6 needs the base to check out of the feature branch.

If `context.md` is not found, ABORT with a message explaining that no `.hq/tasks/` entry matches the current branch and that `/hq:archive` closes out the current branch's task folder — the user can switch to the correct branch and retry.

## Phase 2: Pre-check — PR State

Find the PR associated with this branch:

```bash
gh pr list --head "<current-branch>" --state all --json number,state,url --limit 5
```

Hold the PR number, state, and URL in conversation state — later phases (and the report) reference them.

**Done mode** acceptance:

- No PR → ABORT (`PR not created — complete the /hq:loop run first.`)
- `OPEN` → ABORT (`PR #<n> is still open. Retry after merge: <url>`)
- `CLOSED` (not merged) → ABORT (`PR #<n> was closed without merging. To archive as canceled, run: /hq:archive cancel — URL: <url>`)
- `MERGED` → proceed

**Cancel mode** acceptance:

- No PR → proceed (note: no PR to close)
- `OPEN` → proceed (Phase 4 will close it)
- `CLOSED` (not merged) → proceed (note: PR already closed)
- `MERGED` → ABORT (`PR #<n> was merged — cancel mode is for un-merged closes. Use /hq:archive (without 'cancel') instead. URL: <url>`)

## Phase 3: Pre-check — Pending FBs

Check `.hq/tasks/<branch-dir>/feedbacks/` for any non-`done/` files:

```bash
find .hq/tasks/<branch-dir>/feedbacks -maxdepth 1 -type f -name 'FB*.md' 2>/dev/null
```

**Done mode**:

- No pending FBs → proceed.
- Pending FBs exist → ABORT with the list:
  ```
  Cannot archive — pending FB files:
    - FB003.md
    - FB005.md
  → These should have been triaged to feedbacks/done/ at /hq:loop Stage 4.
    Resolve or move them manually, then retry.
  ```
  This is defensive — in a normal loop run, every FB is moved to `done/` with a disposition at Stage 4 (before the PR exists). Pending files here indicate an abnormal state.

**Cancel mode**:

- No pending FBs → proceed silently.
- Pending FBs exist → **do not abort**. Record the list and include it in the Phase 7 report. Rationale: when the work is being canceled, unresolved FBs are part of the abandoned state — they will travel with the folder to `canceled/` for the audit trail. The user has already signaled cancel intent via the explicit argument.

## Phase 4: Close PR (cancel mode only)

**Skip this phase entirely in done mode.** Mark its task `completed` with note `n/a (done mode)` and move to Phase 5.

In cancel mode, perform the GitHub-side close operation **before** moving local files. If it fails, abort with the failure — the workspace stays consistent with GitHub state.

If Phase 2 recorded PR state `OPEN`:

```bash
gh pr close <pr-number> --comment "Closed via /hq:archive cancel — work canceled without merging."
```

Do **not** pass `--delete-branch`. Remote branch lifecycle is left to repo settings / manual cleanup, symmetric with done mode (which never deletes remote branches either).

If the PR was already `CLOSED` or absent, skip the close (nothing to do on GitHub).

The plan is a local file — there is no plan Issue to close; the abandoned `plan.md` travels with the folder to `canceled/` in Phase 5. The parent `hq:task` Issue is **not** touched — task-level requirements may still be valid; only this particular plan attempt is canceled. The user can manually close the task later if appropriate.

## Phase 5: Archive Task Folder

### Worktree salvage check (linked worktrees only)

`worktree-setup.sh` symlinks `.hq/tasks/` and `.hq/retro/` back to the main repo, so archives from a skill-created worktree land main-side automatically. A worktree created **without** the skill holds these as plain local directories — archiving into them orphans the run's artifacts (FBs, decision records, retro, distilled learnings) the moment the worktree is removed. This has happened in practice; the salvage below is the defense.

Detect before moving:

```bash
main_repo=$(dirname "$(cd "$(git rev-parse --git-common-dir)" && pwd)")
toplevel=$(git rev-parse --show-toplevel)
```

When `toplevel` ≠ `main_repo` (this is a linked worktree) **and** `.hq/tasks` is not a symlink (`[[ -L .hq/tasks ]]` false), redirect the archive:

1. Use `"$main_repo/.hq/tasks/<done|canceled>"` as the `archive_root` below (create it with `mkdir -p`).
2. After the move, salvage retro artifacts: if `.hq/retro` is a real local directory, copy `.hq/retro/<branch-dir>*` (file or directory, if present) to `"$main_repo/.hq/retro/"` — skip entries that already exist main-side.
3. Salvage distilled learnings: if `.hq/start-memory.md` is a real local file and differs from `"$main_repo/.hq/start-memory.md"`, merge the learnings the main copy lacks into the main copy within its char budget — a judgment merge, not a blind overwrite (the main copy may have advanced through other runs).
4. Note the redirection (and what was salvaged) in the Phase 8 report.

When the check does not fire (main repo, or a symlinked worktree), proceed unchanged.

### Move

Pick the archive root based on mode:

- done mode → `.hq/tasks/done`
- cancel mode → `.hq/tasks/canceled`

Ensure the destination exists and move:

```bash
archive_root=".hq/tasks/<done|canceled>"   # selected by mode
mkdir -p "$archive_root"

src=".hq/tasks/<branch-dir>"
dst="$archive_root/<branch-dir>"

# If destination already exists, append a timestamp suffix
if [[ -e "$dst" ]]; then
  dst="$archive_root/<branch-dir>-$(date +%Y%m%d-%H%M%S)"
fi

mv "$src" "$dst"
```

Hold the final `dst` path in conversation state for the report.

## Phase 6: Clean Up Branch

1. Use the `base_branch` value captured from `context.md` in Phase 1. If that field was absent (legacy `context.md` from before the field was introduced), fall back to the rest of the resolution chain per `hq:workflow § Branch Rules`: `.hq/settings.json` `base_branch` → `git symbolic-ref --short refs/remotes/origin/HEAD` → `main`. The `context.md` path itself is no longer available at this point — Phase 5 archived the file.
2. Switch to base:
   ```bash
   git checkout <base>
   ```
3. Delete the local feature branch:
   - **Done mode**:
     ```bash
     git branch -d <feature-branch>
     ```
     If `-d` refuses (branch not fully merged from git's local POV, e.g., squash-merged on GitHub), retry with `-D`:
     ```bash
     git branch -D <feature-branch>
     ```
     This is safe because we already confirmed the PR was merged in Phase 2.
   - **Cancel mode**:
     ```bash
     git branch -D <feature-branch>
     ```
     Use `-D` directly — by definition the branch is not merged into base, so `-d` would always refuse. The explicit `cancel` argument is the user's authorization to drop the unmerged commits.

## Phase 7: Update Memory

Clear the focus entry in your memory. In both modes, the parent `hq:task` Issue (if any) is left untouched.

## Phase 8: Report

Mode-aware summary.

**Done mode**:

- **Mode**: `done`
- **Archived**: `.hq/tasks/<branch-dir>/` → `.hq/tasks/done/<branch-dir>[-timestamp]/`
- **Branch deleted**: `<feature-branch>`
- **Now on**: `<base-branch>`
- **PR**: #<pr> (merged, <url>)

**Cancel mode**:

- **Mode**: `cancel`
- **Archived**: `.hq/tasks/<branch-dir>/` → `.hq/tasks/canceled/<branch-dir>[-timestamp]/`
- **Branch force-deleted**: `<feature-branch>`
- **Now on**: `<base-branch>`
- **PR**: #<pr> (closed without merging, <url>) — or `(no PR was created)` if Phase 2 found none
- **Pending FBs at cancel time** (if any): list filenames from Phase 3 with a note that they live under `.hq/tasks/canceled/<branch-dir>/feedbacks/` for the audit trail.

## Rules

Invariants not already stated by the phases above or the Security note:

- **Stop on pre-check failure** — never force-archive. The user must resolve prerequisites themselves.
- **Explicit `cancel` argument is the confirmation** — no extra interactive prompt. Mistyping is handled by the strict argument parser (only empty or `cancel` accepted).
- **Mode is set once at argument parsing (`## Argument Parsing`) and never changes** — every phase branches on the same mode value.
- **No `hq:feedback` creation** — this command does NOT escalate anything. Escalation happens at `/hq:loop` Stage 7 (user-confirmed) or via `/hq:respond`.
- **Never use `git branch -D` on the base branch** — always switch off the feature branch first.
- **Never use `--no-verify`** — not applicable here, but the general hook-bypass prohibition stands.
