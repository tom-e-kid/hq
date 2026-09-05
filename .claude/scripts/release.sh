#!/usr/bin/env bash
# release.sh — fast-forward develop into main, create the tag and the GitHub Release (dev tool).
#
# Repo-local tool. Not part of the distributed plugin.
#
# Preconditions (this script does NOT create them): the release-prep commit is on develop.
#   - .claude-plugin/plugin.json "version" is set to <x.y.z>
#   - CHANGELOG.md has a `## [<x.y.z>] - YYYY-MM-DD` section with content
#   The version bump is kept out of this script so that a failed run never
#   needs a remote rollback.
#
# Usage:
#   release.sh <x.y.z> [--dry-run]
#     <x.y.z>     version to release. Tag name is v<x.y.z>.
#     --dry-run   run every precondition check and extract the release notes,
#                 then exit without merging / pushing / tagging / creating a Release.
#
# Version and CHANGELOG are read from `git show develop:<path>`, not the working
# tree (what actually lands on main is the source of truth).
#
# Exit: 0 success / 2 argument, precondition, or safety error / 1 execution failure
#
# shellcheck disable=SC2016

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

REMOTE="origin"
EXPECTED_SLUG="tom-e-kid/hq"
DEV_BRANCH="develop"
REL_BRANCH="main"
PLUGIN_JSON=".claude-plugin/plugin.json"
CHANGELOG="CHANGELOG.md"

die() { echo "release: $1" >&2; exit "${2:-2}"; }
note() { echo "release: $1"; }

# --- arguments ----------------------------------------------------------------
version=""
dry_run=0
while (($#)); do
  case "$1" in
    --dry-run) dry_run=1 ;;
    -h|--help) sed -n '2,23p' "${BASH_SOURCE[0]}"; exit 0 ;;
    -*) die "unknown option: $1" 2 ;;
    *)
      [[ -z "$version" ]] || die "specify exactly one version (second one: $1)" 2
      version="$1"
      ;;
  esac
  shift
done

[[ -n "$version" ]] || die "version missing (Usage: release.sh <x.y.z> [--dry-run])" 2
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]] \
  || die "version is not semver: $version" 2
tag="v$version"

# --- environment --------------------------------------------------------------
command -v git >/dev/null 2>&1 || die "git not found" 2
command -v gh  >/dev/null 2>&1 || die "gh (GitHub CLI) not found" 2

git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || die "not a git repository: $REPO_ROOT" 2

# Repo identity: origin must point at the expected repo (refuse pushing elsewhere)
origin_url="$(git -C "$REPO_ROOT" remote get-url "$REMOTE" 2>/dev/null)" \
  || die "remote '$REMOTE' does not exist" 2
case "$origin_url" in
  *"$EXPECTED_SLUG"|*"$EXPECTED_SLUG".git) : ;;
  *) die "remote '$REMOTE' does not point at the expected repo (refusing). expected=$EXPECTED_SLUG actual=$origin_url" 2 ;;
esac

# --- working tree cleanliness -------------------------------------------------
[[ -z "$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null)" ]] \
  || die "uncommitted changes present. Commit or stash them first" 2
git -C "$REPO_ROOT" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 \
  && die "a merge is in progress" 2
git_dir="$(git -C "$REPO_ROOT" rev-parse --absolute-git-dir 2>/dev/null)" \
  || die "cannot resolve the git directory" 2
[[ ! -d "$git_dir/rebase-merge" && ! -d "$git_dir/rebase-apply" ]] \
  || die "a rebase is in progress" 2

# --- branch existence and remote sync -----------------------------------------
git -C "$REPO_ROOT" fetch --quiet --tags "$REMOTE" \
  || die "fetch from $REMOTE failed (check network / auth)" 2

for b in "$DEV_BRANCH" "$REL_BRANCH"; do
  git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$b" \
    || die "local branch '$b' does not exist" 2
  git -C "$REPO_ROOT" show-ref --verify --quiet "refs/remotes/$REMOTE/$b" \
    || die "remote branch '$REMOTE/$b' does not exist" 2
  local_sha="$(git -C "$REPO_ROOT" rev-parse "refs/heads/$b")"
  remote_sha="$(git -C "$REPO_ROOT" rev-parse "refs/remotes/$REMOTE/$b")"
  [[ "$local_sha" == "$remote_sha" ]] \
    || die "'$b' differs between local and $REMOTE (local=${local_sha:0:7} remote=${remote_sha:0:7}). Sync first" 2
done

dev_sha="$(git -C "$REPO_ROOT" rev-parse "refs/heads/$DEV_BRANCH")"
rel_sha="$(git -C "$REPO_ROOT" rev-parse "refs/heads/$REL_BRANCH")"

# fast-forward must hold (develop is a descendant of main)
git -C "$REPO_ROOT" merge-base --is-ancestor "$rel_sha" "$dev_sha" \
  || die "'$REL_BRANCH' is not an ancestor of '$DEV_BRANCH'; fast-forward impossible. Inspect the history" 2
[[ "$rel_sha" != "$dev_sha" ]] \
  || die "'$REL_BRANCH' is already identical to '$DEV_BRANCH' (nothing to release)" 2

# --- tag duplication ----------------------------------------------------------
git -C "$REPO_ROOT" show-ref --verify --quiet "refs/tags/$tag" \
  && die "tag '$tag' already exists locally" 2
[[ -z "$(git -C "$REPO_ROOT" ls-remote --tags "$REMOTE" "refs/tags/$tag" 2>/dev/null)" ]] \
  || die "tag '$tag' already exists on $REMOTE" 2

# --- version match (read from develop, the source of truth) -------------------
plugin_json_content="$(git -C "$REPO_ROOT" show "$DEV_BRANCH:$PLUGIN_JSON" 2>/dev/null)" \
  || die "$PLUGIN_JSON not found on $DEV_BRANCH" 2
declared="$(printf '%s\n' "$plugin_json_content" \
  | sed -nE 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -1)"
[[ -n "$declared" ]] || die "cannot read version from $PLUGIN_JSON" 2
[[ "$declared" == "$version" ]] \
  || die "version mismatch. argument=$version / $DEV_BRANCH:$PLUGIN_JSON=$declared. Land the release-prep commit first" 2

# marketplace.json plugins[] must not carry a version
# (plugin.json always wins; a version there is silently ignored and confusing)
mp_content="$(git -C "$REPO_ROOT" show "$DEV_BRANCH:.claude-plugin/marketplace.json" 2>/dev/null || true)"
if [[ -n "$mp_content" ]]; then
  if printf '%s\n' "$mp_content" | sed -n '/"plugins"/,$p' | grep -q '"version"'; then
    die "marketplace.json plugins[] carries \"version\". plugin.json always wins — remove it" 2
  fi
fi

# --- extract the CHANGELOG section --------------------------------------------
changelog_content="$(git -C "$REPO_ROOT" show "$DEV_BRANCH:$CHANGELOG" 2>/dev/null)" \
  || die "$CHANGELOG not found on $DEV_BRANCH" 2

# Two stop conditions: the next `##` heading, and the trailing link reference
# definitions (`^[...]: `). Without the latter, releasing the last section would
# leak the link references into the notes.
notes="$(printf '%s\n' "$changelog_content" | awk -v ver="$version" '
  $0 ~ "^## \\[" ver "\\]" { inside = 1; next }
  inside && /^## / { exit }
  inside && /^\[[^]]+\]:[[:space:]]/ { exit }
  inside { print }
')"
# drop leading blank lines (trailing blanks are harmless in notes)
notes="$(printf '%s\n' "$notes" | sed -e '/./,$!d')"
[[ -n "$notes" ]] \
  || die "$CHANGELOG has no content under '## [$version]'. Write the release notes first" 2

# --- gh auth ------------------------------------------------------------------
gh auth status >/dev/null 2>&1 \
  || die "gh is not authenticated (run gh auth login)" 2

# --- validation ends here; mutations begin below ------------------------------
cat <<EOF
--- release plan ---------------------------------------------------------------
repo    : $EXPECTED_SLUG ($origin_url)
version : $version (tag: $tag)
merge   : $REL_BRANCH (${rel_sha:0:7}) <- $DEV_BRANCH (${dev_sha:0:7})  [--ff-only]
commits : $(git -C "$REPO_ROOT" rev-list --count "$rel_sha..$dev_sha")
will run:
  git checkout $REL_BRANCH
  git merge --ff-only $DEV_BRANCH
  git push $REMOTE $REL_BRANCH
  git tag -a $tag -m "$tag" $dev_sha
  git push $REMOTE $tag
  gh release create $tag --title "$tag" --notes-file <CHANGELOG [$version] section>
--- release notes --------------------------------------------------------------
$notes
--------------------------------------------------------------------------------
EOF

if ((dry_run)); then
  note "dry-run: nothing was changed (merge / push / tag / Release not executed)"
  echo "dry_run=1"
  exit 0
fi

# return to the original branch (do not end checked out on main)
orig_branch="$(git -C "$REPO_ROOT" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
restore_branch() {
  if [[ -n "$orig_branch" ]]; then
    git -C "$REPO_ROOT" checkout --quiet "$orig_branch" 2>/dev/null || true
  fi
}
trap restore_branch EXIT

notes_file="$(mktemp "${TMPDIR:-/tmp}/hq-release.XXXXXXXX")" || die "cannot create a temp file" 1
cleanup_notes() { rm -f "$notes_file"; }
trap 'cleanup_notes; restore_branch' EXIT
printf '%s\n' "$notes" > "$notes_file"

git -C "$REPO_ROOT" checkout --quiet "$REL_BRANCH" || die "checkout of $REL_BRANCH failed" 1
git -C "$REPO_ROOT" merge --ff-only "$DEV_BRANCH" >/dev/null \
  || die "fast-forward merge into $REL_BRANCH failed (local should be unchanged)" 1
note "fast-forwarded $REL_BRANCH to ${dev_sha:0:7}"

git -C "$REPO_ROOT" push --quiet "$REMOTE" "$REL_BRANCH" \
  || die "push to $REMOTE/$REL_BRANCH failed (local $REL_BRANCH has advanced)" 1
note "pushed $REMOTE/$REL_BRANCH"

git -C "$REPO_ROOT" tag -a "$tag" -m "$tag" "$dev_sha" \
  || die "creating tag '$tag' failed" 1
git -C "$REPO_ROOT" push --quiet "$REMOTE" "refs/tags/$tag" \
  || die "pushing tag '$tag' failed (local tag exists)" 1
note "created and pushed tag '$tag'"

if ! release_url="$(gh release create "$tag" --repo "$EXPECTED_SLUG" \
    --title "$tag" --notes-file "$notes_file" 2>&1)"; then
  die "gh release create failed (tag and $REL_BRANCH are already pushed): $release_url" 1
fi
release_url_line="$(printf '%s\n' "$release_url" | grep -E '^https?://.*/releases/tag/' | head -1 || true)"
note "created GitHub Release: ${release_url_line:-$release_url}"

echo "released=$tag"
echo "release_url=${release_url_line:-}"
exit 0
