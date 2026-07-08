---
name: worktree-setup
description: Create a new worktree and set up local files
allowed-tools: Bash(bash *scripts/worktree-setup.sh*)
---

## Context

- Main repo root: !`git rev-parse --show-toplevel`
- Existing worktrees: !`git worktree list`
- Default branch: !`git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null || echo "not set"`

## Instructions

Determine the branch name from the user's request and run [scripts/worktree-setup.sh](scripts/worktree-setup.sh).

### Create worktree with a new branch

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/worktree-setup.sh" <base-branch> --branch <new-branch>
```

### Create worktree with an existing branch

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/worktree-setup.sh" <base-branch>
```

### Branch resolution rules

When the user provides only a branch name:
1. Check if the branch exists locally or on the remote
2. Exists → use it as `<base-branch>` (existing branch mode)
3. Does not exist → treat it as a new branch name and ask the user for the base branch (default: remote HEAD branch)

### After script completion

The script symlinks local (gitignored) files back to the main repo — `.claude/settings.local.json`, the `.hq/*.md` overrides + `start-memory.md`, `.hq/retro/`, `.hq/tasks/`, and dev `.env*` — so there is a single source of truth and loop write-back (retro, start-memory, task archive) lands in the main repo. No manual copy step is needed.

Mention to the user only when relevant:
- `.env*` values are shared via symlink. If the worktree needs a *different* dev env (distinct port / DB), replace the symlink with a real file.
- `.envrc` is symlinked but direnv is path-keyed — run `direnv allow` once in the new worktree.

## Error Handling

- **Worktree directory already exists**: script aborts
- **Branch not found locally or on remote**: script aborts
