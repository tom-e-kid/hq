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

Guide the user regarding `.claude/settings.local.json`:
- If `.claude/settings.local.json` exists in the main repo, check whether similar settings are needed for the new worktree
- Do not auto-copy because it may contain absolute paths. Ask the user to decide

## Error Handling

- **Worktree directory already exists**: script aborts
- **Branch not found locally or on remote**: script aborts
