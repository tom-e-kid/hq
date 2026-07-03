---
name: worktree-rebase
description: Rebase worktree branch against main branch (origin/HEAD) and sync remote
allowed-tools: Bash(bash *scripts/worktree-rebase.sh*)
---

## Context

- Worktree root: !`git rev-parse --show-toplevel`
- Current branch: !`git rev-parse --abbrev-ref HEAD`
- Git status: !`git status --short`

## Instructions

Run [scripts/worktree-rebase.sh](scripts/worktree-rebase.sh):

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/worktree-rebase.sh"
```

The script automatically performs:

1. Detect main branch from `origin/HEAD` (e.g., `develop`)
2. Detect worktree branch from the `@` suffix in directory name (e.g., `develop_design_editor`)
3. Stash uncommitted changes if any
4. Rebase worktree branch onto main branch
5. Force-push with `--force-with-lease` if worktree branch remote has diverged
6. If the current branch differs from worktree branch, rebase it onto the updated worktree branch
7. Restore stash if one was created

## Error Handling

- **Rebase conflict**: script aborts with a message. Inform the user and guide them through manual resolution
- **Stash pop conflict**: same as above
- **`origin/HEAD` not set**: suggest running `git remote set-head origin --auto`
