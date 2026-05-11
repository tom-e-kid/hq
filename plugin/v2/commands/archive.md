---
name: archive
description: Safely close the current work branch — verify PR merged + no pending FBs, then archive and clean up
allowed-tools: Read, Glob, Bash(git:*), Bash(gh:*), Bash(bash:*), Bash(ls:*), Bash(mv:*), Bash(mkdir:*), TaskCreate, TaskUpdate
---

# ARCHIVE — Safe Branch Closure

This command closes out a completed work branch by:

1. Verifying the PR is merged
2. Verifying no pending FB files remain
3. Moving `.hq/tasks/<branch-dir>/` to `.hq/tasks/done/<branch-dir>/`
4. Switching to the base branch
5. Deleting the local feature branch
6. Clearing the focus memory entry

If the pre-checks fail, the command **stops** and reports what remains. There is no interactive confirmation for the archive itself — if safety checks pass, the archive proceeds unconditionally.

**Security**: This command deletes a local branch. It never pushes, never force-pushes, and never touches remote branches.

**`hq:workflow`** — shorthand for `${CLAUDE_PLUGIN_ROOT}/plugin/v2/rules/workflow.md` (plugin-internal source of truth). Read it with the Read tool when this command starts so all phases have Focus, FB Lifecycle, etc. available. All `hq:workflow § <name>` citations refer to sections of that file.

## Progress Tracking

Use Claude Code's task UI (`TaskCreate` / `TaskUpdate`). Create all phases as tasks at the start:

| Task subject | activeForm |
|---|---|
| Resolve focus | Resolving focus |
| Pre-check: PR merged | Checking PR merge state |
| Pre-check: pending FBs | Checking pending FBs |
| Archive task folder | Archiving task folder |
| Clean up branch | Cleaning up branch |
| Report results | Reporting results |

Set each to `in_progress` when starting and `completed` when done. If a pre-check aborts the command, mark remaining phases as `completed` with a brief note and stop.

## Context

- Branch: !`git branch --show-current 2>/dev/null || echo "(detached)"`
- Focus: !`bash "${CLAUDE_PLUGIN_ROOT}/plugin/v2/scripts/read-context.sh"`

## Phase 1: Resolve Focus

Read `.hq/tasks/<branch-dir>/context.md` for the **current branch** (branch-dir = branch name with `/` → `-`). Extract:

- `plan` — `hq:plan` Issue number
- `source` — `hq:task` Issue number
- `branch` — original branch name (should match current branch)
- `base_branch` — the branch this feature branch was created from (captured at `/hq:start` Phase 3 — see `hq:workflow § Focus`). **Hold this in conversation state** — Phase 4 archives `context.md` away, and Phase 5 needs the base to check out of the feature branch.

If `context.md` is not found, ABORT with a message explaining that no `.hq/tasks/` entry matches the current branch and that `/hq:archive` closes out the current branch's task folder — the user can switch to the correct branch and retry.

## Phase 2: Pre-check — PR Merged?

Find the PR associated with this branch:

```bash
gh pr list --head "<current-branch>" --state all --json number,state,url --limit 5
```

- If **no PR exists**, ABORT with a message saying the PR has not been created yet and the user should complete `/hq:start` to create it.
- If **PR state is OPEN**, ABORT with a message saying PR #<n> is still open and the command should be retried after review/merge completes (include the URL).
- If **PR state is CLOSED** (not merged), ABORT with a message saying PR #<n> was closed without merging and the user must decide how to proceed (reopen / manual cleanup), including the URL.
- If **PR state is MERGED**, proceed.

## Phase 3: Pre-check — Pending FBs?

Check `.hq/tasks/<branch-dir>/feedbacks/` for any non-`done/` files:

```bash
find .hq/tasks/<branch-dir>/feedbacks -maxdepth 1 -type f -name 'FB*.md' 2>/dev/null
```

- If **no pending FBs**, proceed.
- If **pending FBs exist**, ABORT with the list:
  ```
  Cannot archive — pending FB files:
    - FB003.md
    - FB005.md
  → These should have been moved to feedbacks/done/ during /hq:start PR creation.
    Resolve or move them manually, then retry.
  ```

This is a defensive check — in a normal `/hq:start` → PR flow, all FBs are moved to `done/` when the PR is created. Pending files here indicate an abnormal state.

## Phase 4: Archive Task Folder

Ensure the archive destination exists:

```bash
mkdir -p .hq/tasks/done
```

Move the task folder:

```bash
src=".hq/tasks/<branch-dir>"
dst=".hq/tasks/done/<branch-dir>"

# If destination already exists, append a timestamp suffix
if [[ -e "$dst" ]]; then
  dst=".hq/tasks/done/<branch-dir>-$(date +%Y%m%d-%H%M%S)"
fi

mv "$src" "$dst"
```

## Phase 5: Clean Up Branch

1. Use the `base_branch` value captured from `context.md` in Phase 1. If that field was absent (legacy `context.md` from before the field was introduced), fall back to the rest of the resolution chain per `hq:workflow § Branch Rules`: `.hq/settings.json` `base_branch` → `git symbolic-ref --short refs/remotes/origin/HEAD` → `main`. The `context.md` path itself is no longer available at this point — Phase 4 archived the file.
2. Switch to base:
   ```bash
   git checkout <base>
   ```
3. Delete the local feature branch:
   ```bash
   git branch -d <feature-branch>
   ```
   - If `-d` refuses (branch not fully merged from git's local POV, e.g., squash-merged on GitHub), retry with `-D`:
     ```bash
     git branch -D <feature-branch>
     ```
     This is safe because we already confirmed the PR was merged in Phase 2.

## Phase 6: Update Memory

Clear the focus entry in your memory. The `hq:plan` Issue is already closed by GitHub on PR merge (via the `Closes #<plan>` link), so no `gh issue close` call is needed here.

## Phase 7: Report

Summarize:

- **Archived**: `.hq/tasks/<branch-dir>/` → `.hq/tasks/done/<branch-dir>[-timestamp]/`
- **Branch deleted**: `<feature-branch>`
- **Now on**: `<base-branch>`
- **hq:plan**: #<plan> (closed on PR merge)
- **PR**: #<pr> (merged, <url>)

## Rules

- **Stop on pre-check failure** — never force-archive. The user must resolve prerequisites themselves.
- **No interactive confirmation for archival** — when pre-checks pass, move and clean up unconditionally.
- **No `hq:feedback` creation** — this command does NOT escalate anything. Escalation happens via `/hq:triage` during PR review, before merge.
- **Never push / force-push** — all operations are local.
- **Never use `git branch -D` on the base branch** — always switch off the feature branch first.
- **Never use `--no-verify`** — not applicable here, but the general hook-bypass prohibition stands.
- **Timestamp collisions** — if `.hq/tasks/done/<branch-dir>/` already exists, append a timestamp suffix rather than overwriting.
