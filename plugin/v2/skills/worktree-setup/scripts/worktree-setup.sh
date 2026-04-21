#!/bin/bash
set -euo pipefail

# Create a new worktree and set up local files.
#
# Usage:
#   worktree-setup.sh <base-branch> [--branch <new-branch>] [--from <source-dir>]
#
# Prerequisite: run from inside a git repository (main repo or a worktree).

# === Parse arguments ===

usage() {
  echo "Usage: $(basename "$0") <base-branch> [--branch <new-branch>] [--from <source-dir>]"
  echo ""
  echo "  <base-branch>          Base branch for the worktree (the part after @ in the directory name)"
  echo "  --branch <name>        Name of the new branch to derive from the base"
  echo "  --from <path>          Source directory to copy files from (default: main repo)"
  exit 1
}

if [[ $# -lt 1 ]]; then
  usage
fi

base_branch="$1"
shift

new_branch=""
source_dir=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch)
      new_branch="$2"
      shift 2
      ;;
    --from)
      source_dir="$2"
      shift 2
      ;;
    *)
      echo "ERROR: unknown option: $1"
      usage
      ;;
  esac
done

# === Identify the main repo ===

git_common_dir=$(cd "$(git rev-parse --git-common-dir)" && pwd)

# For .git/worktrees/xxx, the main repo is the parent of .git
if [[ "$git_common_dir" == */.git ]]; then
  main_repo=$(dirname "$git_common_dir")
else
  # The main repo's .git directory itself
  main_repo=$(dirname "$git_common_dir")
fi

repo_name=$(basename "$main_repo")
parent_dir=$(dirname "$main_repo")

# === Resolve default for source_dir ===

if [[ -z "$source_dir" ]]; then
  source_dir="$main_repo"
fi

if [[ ! -d "$source_dir" ]]; then
  echo "ERROR: source directory does not exist: $source_dir"
  exit 1
fi

# === Determine the worktree directory name ===

if [[ -n "$new_branch" ]]; then
  worktree_dir="${parent_dir}/${repo_name}@${new_branch}"
else
  worktree_dir="${parent_dir}/${repo_name}@${base_branch}"
fi

echo "=== Worktree Setup ==="
echo "Main repo:     $main_repo"
echo "Base branch:   $base_branch"
if [[ -n "$new_branch" ]]; then
  echo "New branch:    $new_branch"
fi
echo "Source:        $source_dir"
echo "Target:        $worktree_dir"
echo ""

# === Pre-flight checks ===

if [[ -d "$worktree_dir" ]]; then
  echo "ERROR: directory already exists: $worktree_dir"
  exit 1
fi

# === Verify branch existence and create the worktree ===

if [[ -n "$new_branch" ]]; then
  # New-branch mode
  # If the base branch is missing locally, fetch it from the remote
  if ! git show-ref --verify --quiet "refs/heads/$base_branch"; then
    echo ">> branch not found locally, fetching from remote..."
    if git ls-remote --exit-code --heads origin "$base_branch" >/dev/null 2>&1; then
      git fetch origin "$base_branch"
      git branch "$base_branch" "origin/$base_branch"
    else
      echo "ERROR: branch '$base_branch' not found locally or on the remote"
      exit 1
    fi
  fi
  echo ">> creating worktree (new branch: $new_branch from $base_branch)..."
  git worktree add -b "$new_branch" "$worktree_dir" "$base_branch"
else
  # Existing-branch mode
  if git show-ref --verify --quiet "refs/heads/$base_branch"; then
    echo ">> creating worktree (local branch: $base_branch)..."
    git worktree add "$worktree_dir" "$base_branch"
  elif git ls-remote --exit-code --heads origin "$base_branch" >/dev/null 2>&1; then
    echo ">> creating worktree from the remote branch..."
    git fetch origin "$base_branch"
    git worktree add --track -b "$base_branch" "$worktree_dir" "origin/$base_branch"
  else
    echo "ERROR: branch '$base_branch' not found locally or on the remote"
    exit 1
  fi
fi

# === Copy files ===

echo ""
echo ">> copying configuration files..."
copied_files=()

# .claude/settings.json
if [[ -f "$source_dir/.claude/settings.json" ]]; then
  mkdir -p "$worktree_dir/.claude"
  cp "$source_dir/.claude/settings.json" "$worktree_dir/.claude/settings.json"
  copied_files+=(".claude/settings.json")
fi

# .claude/rules/ (any project-local rules dropped here by the user)
if [[ -d "$source_dir/.claude/rules" ]]; then
  mkdir -p "$worktree_dir/.claude"
  cp -R "$source_dir/.claude/rules" "$worktree_dir/.claude/rules"
  copied_files+=(".claude/rules/")
fi

# .hq/ project override files
for hq_override in pr.md code-review.md xcodebuild-config.md; do
  if [[ -f "$source_dir/.hq/$hq_override" ]]; then
    mkdir -p "$worktree_dir/.hq"
    cp "$source_dir/.hq/$hq_override" "$worktree_dir/.hq/$hq_override"
    copied_files+=(".hq/$hq_override")
  fi
done

# .env* (monorepo-aware: search every level and preserve directory structure)
while IFS= read -r -d '' env_file; do
  # ./path/.envrc → path/.envrc
  rel_path="${env_file#./}"
  target_dir=$(dirname "$worktree_dir/$rel_path")
  mkdir -p "$target_dir"
  cp "$source_dir/$rel_path" "$worktree_dir/$rel_path"
  copied_files+=("$rel_path")
done < <(cd "$source_dir" && find . -name '.env*' \
  -not -path '*node_modules*' \
  -not -path '*/.git/*' \
  -not -path '*/.hq/*' \
  -not -path '*/vendor/*' \
  -not -path '*/build/*' \
  -not -name '.env.production*' \
  -not -name '.env.staging*' \
  -print0 2>/dev/null || true)

# === Generate .hq/settings.json ===

default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo "")
if [[ -n "$default_branch" && "$base_branch" != "$default_branch" ]]; then
  mkdir -p "$worktree_dir/.hq"
  # Merge into an existing .hq/settings.json, or create a new one
  if [[ -f "$worktree_dir/.hq/settings.json" ]]; then
    # Already copied: append base_branch
    tmp=$(mktemp)
    # Strip trailing } → drop trailing blank lines → add trailing comma to the last line
    sed -e '$d' "$worktree_dir/.hq/settings.json" \
      | sed -e '/^[[:space:]]*$/d' -e '$s/$/,/' > "$tmp"
    echo "  \"base_branch\": \"$base_branch\"" >> "$tmp"
    echo "}" >> "$tmp"
    mv "$tmp" "$worktree_dir/.hq/settings.json"
  else
    echo "{\"base_branch\": \"$base_branch\"}" > "$worktree_dir/.hq/settings.json"
  fi
  copied_files+=(".hq/settings.json (base_branch: $base_branch)")
fi

# === Completion report ===

echo ""
echo "=== Setup complete ==="
echo "Worktree: $worktree_dir"
echo ""

if [[ ${#copied_files[@]} -gt 0 ]]; then
  echo "Copied/generated files:"
  for f in "${copied_files[@]}"; do
    echo "  $f"
  done
  echo ""
fi

echo "Next steps:"
echo "  cd $worktree_dir"
echo "  claude  # launch Claude Code"
