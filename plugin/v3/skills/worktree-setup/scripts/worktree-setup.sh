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
  echo "  --from <path>          Source directory to link files from (default: main repo)"
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

# --git-common-dir points at the shared .git (the main repo's .git, even when run
# from a worktree). The main repo is its parent directory in both cases.
git_common_dir=$(cd "$(git rev-parse --git-common-dir)" && pwd)
main_repo=$(dirname "$git_common_dir")

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

# === Link local files ===
#
# Local (gitignored) files are symlinked back to $source_dir rather than copied, so
# there is a single source of truth and loop write-back (retro, start-memory, task
# archive) reaches the main repo instead of being orphaned when the worktree is
# removed. Tracked files (e.g. .claude/settings.json) are NOT handled here — they
# already arrive via the branch checkout.

echo ""
echo ">> linking local files..."
linked_files=()

# link_into_worktree <relative-path>: symlink $source_dir/<rel> → worktree, no-op if absent.
link_into_worktree() {
  local rel="$1"
  local src="$source_dir/$rel"
  [[ -e "$src" ]] || return 0
  local dest="$worktree_dir/$rel"
  mkdir -p "$(dirname "$dest")"
  ln -s "$src" "$dest"
  linked_files+=("$rel")
}

# Per-machine Claude permissions — so the worktree inherits the allow-list under
# auto mode. main-repo-pinned absolute paths simply don't match in the worktree
# (harmless); generic patterns still apply.
link_into_worktree ".claude/settings.local.json"

# .hq top-level *.md — override files (draft.md, start.md, …) + start-memory.md.
# Globbed, not a fixed list, so new override names need no change here.
# memory.md is legacy (unreferenced by v3) and deliberately skipped.
while IFS= read -r -d '' md; do
  name=$(basename "$md")
  [[ "$name" == "memory.md" ]] && continue
  link_into_worktree ".hq/$name"
done < <(cd "$source_dir" && find .hq -maxdepth 1 -name '*.md' -print0 2>/dev/null || true)

# .hq accumulate-state directories — retro history and task/plan archive stay
# main-anchored so nothing is lost when the worktree is removed.
link_into_worktree ".hq/retro"
link_into_worktree ".hq/tasks"

# .env* — development env only (production/staging excluded), monorepo-aware.
# Symlinked, preserving directory structure. NOTE: .envrc is linked but direnv is
# path-keyed — run `direnv allow` once in the new worktree.
while IFS= read -r -d '' env_file; do
  rel_path="${env_file#./}"
  link_into_worktree "$rel_path"
done < <(cd "$source_dir" && find . -name '.env*' \
  -not -path '*node_modules*' \
  -not -path '*/.git/*' \
  -not -path '*/.hq/*' \
  -not -path '*/vendor/*' \
  -not -path '*/build/*' \
  -not -name '.env.production*' \
  -not -name '.env.staging*' \
  -print0 2>/dev/null || true)

# === Write .hq/settings.json (per-worktree — copied, not symlinked) ===
#
# base_branch is worktree-specific, so this file cannot be shared with $source_dir.
# It is copied (other keys preserved) with base_branch overridden to the branch this
# worktree has checked out: any branch cut inside the worktree diverges from that
# branch, and execute-protocol Phase 3 runs `git checkout <base>` — pointing it at
# the source's base would fail, since that branch is checked out elsewhere.

worktree_branch="${new_branch:-$base_branch}"
src_settings="$source_dir/.hq/settings.json"

mkdir -p "$worktree_dir/.hq"
if [[ -f "$src_settings" ]] && command -v jq >/dev/null 2>&1; then
  jq --arg b "$worktree_branch" '.base_branch = $b' "$src_settings" \
    > "$worktree_dir/.hq/settings.json"
  linked_files+=(".hq/settings.json (copied, base_branch: $worktree_branch)")
else
  if [[ -f "$src_settings" ]]; then
    echo "WARNING: jq not found — writing a minimal .hq/settings.json; other keys in"
    echo "         $src_settings are NOT carried over."
  fi
  cat > "$worktree_dir/.hq/settings.json" <<EOF
{
  "base_branch": "$worktree_branch"
}
EOF
  linked_files+=(".hq/settings.json (generated, base_branch: $worktree_branch)")
fi

# === Completion report ===

echo ""
echo "=== Setup complete ==="
echo "Worktree: $worktree_dir"
echo ""

if [[ ${#linked_files[@]} -gt 0 ]]; then
  echo "Linked/generated files:"
  for f in "${linked_files[@]}"; do
    echo "  $f"
  done
  echo ""
fi

echo "Next steps:"
echo "  cd $worktree_dir"
echo "  claude  # launch Claude Code"
