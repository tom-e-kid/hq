#!/bin/bash
set -euo pipefail

# Rebase the worktree branch onto the main branch (origin/HEAD), and
# rebase any working branch on top of it.
# After rebasing, if the worktree branch's remote has diverged, push with --force-with-lease.
#
# Prerequisite: the worktree directory name follows the <repo>@<branch> convention.

worktree_dir=$(basename "$(git rev-parse --show-toplevel)")

if [[ "$worktree_dir" != *@* ]]; then
  echo "ERROR: not inside a worktree (directory name does not contain @)"
  exit 1
fi

worktree_branch="${worktree_dir#*@}"
current_branch=$(git rev-parse --abbrev-ref HEAD)

# Derive the main branch from origin/HEAD
main_ref=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null || echo "")
if [[ -z "$main_ref" ]]; then
  echo "ERROR: origin/HEAD is not set"
  echo "  Set it with: git remote set-head origin --auto"
  exit 1
fi
main_branch="${main_ref#refs/remotes/origin/}"

echo "=== Rebase Worktree ==="
echo "Main branch:       $main_branch"
echo "Worktree branch:   $worktree_branch"
echo "Working branch:    $current_branch"
echo ""

# Stash uncommitted changes if any
stashed=false
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo ">> stashing uncommitted changes..."
  git stash
  stashed=true
fi

# Fetch
echo ">> fetching origin..."
git fetch origin

# Rebase the worktree branch onto the main branch
if [[ "$current_branch" == "$worktree_branch" ]]; then
  # On the worktree branch: rebase in place
  echo ">> rebasing $worktree_branch onto origin/$main_branch..."
  if ! git rebase "origin/$main_branch"; then
    echo ""
    echo "ERROR: rebase conflict"
    echo "  git rebase --continue  (after resolving conflicts)"
    echo "  git rebase --abort     (to abort)"
    [[ "$stashed" == true ]] && echo "  NOTE: stash present; run git stash pop after resolving"
    exit 1
  fi
else
  # On a working branch: update the worktree branch first, then rebase onto it
  echo ">> updating $worktree_branch onto origin/$main_branch..."

  # Rebase the worktree branch via a detached checkout
  prev_worktree=$(git rev-parse "$worktree_branch")
  git checkout --quiet "$worktree_branch"
  if ! git rebase "origin/$main_branch"; then
    echo ""
    echo "ERROR: rebase conflict on $worktree_branch"
    echo "  git rebase --continue  (after resolving conflicts)"
    echo "  git rebase --abort     (to abort)"
    echo "  NOTE: originally on branch: $current_branch"
    [[ "$stashed" == true ]] && echo "  NOTE: stash present; run git stash pop after resolving"
    exit 1
  fi

  git checkout --quiet "$current_branch"

  # Rebase the working branch onto the worktree branch
  echo ">> rebasing $current_branch onto $worktree_branch..."
  if ! git rebase "$worktree_branch"; then
    echo ""
    echo "ERROR: rebase conflict on $current_branch"
    echo "  git rebase --continue  (after resolving conflicts)"
    echo "  git rebase --abort     (to abort)"
    [[ "$stashed" == true ]] && echo "  NOTE: stash present; run git stash pop after resolving"
    exit 1
  fi
fi

# Sync the worktree branch's remote
worktree_upstream=$(git rev-parse --abbrev-ref "${worktree_branch}@{upstream}" 2>/dev/null || echo "")
if [[ -n "$worktree_upstream" ]]; then
  local_hash=$(git rev-parse "$worktree_branch")
  remote_hash=$(git rev-parse "$worktree_upstream" 2>/dev/null || echo "")
  if [[ "$local_hash" != "$remote_hash" ]]; then
    echo ">> pushing $worktree_branch to $worktree_upstream with --force-with-lease..."
    if ! git push --force-with-lease origin "$worktree_branch"; then
      echo ""
      echo "ERROR: push rejected because the remote has new commits"
      echo "  Someone else may have pushed"
      echo "  Run: git fetch origin && git log origin/$worktree_branch"
      exit 1
    fi
  fi
fi

# Restore stash
if [[ "$stashed" == true ]]; then
  echo ">> restoring stash..."
  if ! git stash pop; then
    echo ""
    echo "WARNING: stash pop produced a conflict. Resolve manually."
    exit 1
  fi
fi

echo ""
echo "=== Done ==="
