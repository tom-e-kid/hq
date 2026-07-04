#!/usr/bin/env bash
# Append one telemetry event to the central sink: ~/.hq/events.jsonl
# Usage: hq-event.sh <kind> [key=val ...]
#
# Dual-write principle: human-readable records live in the project .hq/;
# this script adds the structured event row for cross-project analytics.
# Event catalog + emission points: commands/loop.md § Telemetry.
#
# NON-BLOCKING CONTRACT: this script NEVER fails the pipeline. Any error
# (unwritable HOME, not a git repo, unknown kind, ...) prints a warning to
# stderr and exits 0. Telemetry is observability, not a gate.
#
# Event line shape:
#   {"ts":"<ISO8601 UTC>","repo":"<owner/repo | local:<dir>>","branch":"<branch>",
#    "run_id":"<from context.md, or <branch-dir>-unknown>","worktree":"<abs path>",
#    "kind":"<kind>","payload":{"k":"v",...}}
set -u
IFS=$'\n\t'

warn_exit() { echo "hq-event: warning: $*" >&2; exit 0; }

KINDS="run_start run_end gate build_result j_decision disposition j8_verdict timing retro"

[[ $# -ge 1 ]] || warn_exit "usage: hq-event.sh <kind> [key=val ...]"
kind="$1"; shift
case " $KINDS " in
  *" $kind "*) ;;
  *) warn_exit "unknown kind '$kind' (closed catalog: $KINDS) — event dropped" ;;
esac

json_escape() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\b'/\\b}
  s=${s//$'\t'/\\t}
  s=${s//$'\n'/\\n}
  s=${s//$'\f'/\\f}
  s=${s//$'\r'/\\r}
  printf '%s' "$s"
}

# --- identity resolution (all failures are warnings) ---
worktree=$(git rev-parse --show-toplevel 2>/dev/null) || warn_exit "not inside a git repository"

branch=$(git branch --show-current 2>/dev/null || true)   # works on unborn branches too
[[ -n "$branch" ]] || branch="detached"
branch_dir=${branch//\//-}

# repo: normalized origin URL -> owner/repo; fallback local:<top-level dir name>
origin=$(git -C "$worktree" remote get-url origin 2>/dev/null || true)
repo=""
if [[ -n "$origin" ]]; then
  r=${origin%.git}
  r=${r%/}
  if [[ "$r" == *"://"* ]]; then          # https://host/owner/repo
    r=${r#*://}; r=${r#*/}                 # -> owner/repo (strip host)
  elif [[ "$r" == *:* ]]; then             # git@host:owner/repo
    r=${r#*:}
  fi
  # keep only the last two path segments (defensive against nested paths)
  seg_b=${r##*/}
  rest=${r%/*}
  seg_a=${rest##*/}
  if [[ -n "$seg_a" && -n "$seg_b" && "$seg_a" != "$r" ]]; then
    repo="${seg_a}/${seg_b}"
  fi
fi
[[ -n "$repo" ]] || repo="local:$(basename "$worktree")"

# run_id: context.md frontmatter, else <branch-dir>-unknown
run_id=""
ctx="$worktree/.hq/tasks/$branch_dir/context.md"
if [[ -f "$ctx" ]]; then
  run_id=$(awk '
    /^---[[:space:]]*$/ { in_fm = !in_fm; next }
    in_fm && /^run_id:[[:space:]]*/ {
      v = $0; sub(/^run_id:[[:space:]]*/, "", v); sub(/[[:space:]]*$/, "", v)
      print v; exit
    }
  ' "$ctx" 2>/dev/null || true)
fi
[[ -n "$run_id" ]] || run_id="${branch_dir}-unknown"

ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# --- payload from key=val args ---
payload="{"
first=1
for kv in "$@"; do
  key=${kv%%=*}
  val=${kv#*=}
  [[ -n "$key" && "$key" != "$kv" ]] || warn_exit "malformed payload arg '$kv' (expected key=val) — event dropped"
  [[ $first -eq 1 ]] || payload+=","
  first=0
  payload+="\"$(json_escape "$key")\":\"$(json_escape "$val")\""
done
payload+="}"

line=$(printf '{"ts":"%s","repo":"%s","branch":"%s","run_id":"%s","worktree":"%s","kind":"%s","payload":%s}' \
  "$(json_escape "$ts")" "$(json_escape "$repo")" "$(json_escape "$branch")" \
  "$(json_escape "$run_id")" "$(json_escape "$worktree")" "$(json_escape "$kind")" "$payload")

sink_dir="${HOME}/.hq"
mkdir -p "$sink_dir" 2>/dev/null || warn_exit "cannot create $sink_dir — event dropped"
printf '%s\n' "$line" >> "$sink_dir/events.jsonl" 2>/dev/null || warn_exit "cannot append to $sink_dir/events.jsonl — event dropped"

exit 0
