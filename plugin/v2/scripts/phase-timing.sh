#!/usr/bin/env bash
# Phase timing helper for /hq:start.
# Subcommands:
#   stamp <phase> <event>   append a timing event to the branch-local JSONL
#   summary                 print wall-clock duration per phase + total
#
# JSONL path: .hq/tasks/<branch-dir>/phase-timings.jsonl
# Event format: {"phase":"<N>","event":"<start|end>","ts":<unix_secs>}
#
# Scope: Phase 4-9 only. Phase 1-3 are structurally unmeasurable on the feature
# branch's JSONL (fresh start: Phase 1/2 stamps land in caller branch's JSONL,
# Phase 3 stamp pair is split across the Phase 3 step 2 branch switch; auto-resume:
# Phase 1's start lands in caller, end in feature, and Phase 2/3 are skipped).
# Phase 10 (Report) emits the summary itself, so it does not self-stamp either.
#
# Durations are wall-clock and include any idle / interrupted time between
# a `start` stamp and its matching `end` stamp across auto-resume sessions.
set -euo pipefail
IFS=$'\n\t'

usage() {
  cat >&2 <<EOF
Usage:
  $(basename "$0") stamp <phase> <event>
  $(basename "$0") summary
EOF
  exit 2
}

resolve_jsonl() {
  local root branch_raw
  root=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "error: not inside a git repository" >&2; exit 1
  }
  branch_raw=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  if [[ -z "$branch_raw" || "$branch_raw" == "HEAD" ]]; then
    echo "error: not on a named branch (detached HEAD)" >&2
    exit 1
  fi
  local branch_dir=${branch_raw//\//-}
  echo "${root}/.hq/tasks/${branch_dir}/phase-timings.jsonl"
}

[[ $# -ge 1 ]] || usage
cmd="$1"
shift

case "$cmd" in
  stamp)
    [[ $# -eq 2 ]] || usage
    phase="$1"
    event="$2"
    [[ "$phase" =~ ^[4-9]$ ]] || { echo "error: <phase> must be 4-9 (Phase 1-3 / 10 are not measured — see file header)" >&2; exit 2; }
    [[ "$event" == "start" || "$event" == "end" ]] || { echo "error: <event> must be 'start' or 'end'" >&2; exit 2; }
    jsonl=$(resolve_jsonl)
    mkdir -p "$(dirname "$jsonl")"
    ts=$(date +%s)
    printf '{"phase":"%s","event":"%s","ts":%s}\n' "$phase" "$event" "$ts" >> "$jsonl"
    ;;
  summary)
    [[ $# -eq 0 ]] || usage
    jsonl=$(resolve_jsonl)
    if [[ ! -s "$jsonl" ]]; then
      echo "No timing data recorded."
      exit 0
    fi
    awk '
      {
        # Skip lines that are not complete timing records (e.g., truncated writes).
        if ($0 !~ /"phase":"[4-9]".*"event":"(start|end)".*"ts":[0-9]+/) next

        ph = $0
        sub(/.*"phase":"/, "", ph); sub(/".*/, "", ph)
        ev = $0
        sub(/.*"event":"/, "", ev); sub(/".*/, "", ev)
        ts = $0
        sub(/.*"ts":/, "", ts); sub(/[^0-9].*/, "", ts)
        ts = ts + 0

        phase_seen[ph] = 1

        if (ev == "start") {
          n_starts[ph]++
          starts[ph, n_starts[ph]] = ts
        } else if (ev == "end") {
          for (i = 1; i <= n_starts[ph]; i++) {
            if (!used[ph, i]) {
              used[ph, i] = 1
              dur = ts - starts[ph, i]
              if (dur < 0) dur = 0
              phase_dur[ph] += dur
              total += dur
              break
            }
          }
        }
      }
      END {
        for (i = 4; i <= 9; i++) {
          ph = i ""
          if (phase_seen[ph]) {
            printf "Phase %s: %s\n", ph, fmt(phase_dur[ph] + 0)
          } else {
            printf "Phase %s: (no data)\n", ph
          }
        }
        print ""
        printf "Total: %s\n", fmt(total + 0)
      }
      function fmt(s,   h, m, r) {
        if (s <= 0) return "0s"
        h = int(s / 3600)
        m = int((s % 3600) / 60)
        r = s % 60
        if (h > 0) return sprintf("%dh %dm %ds", h, m, r)
        if (m > 0) return sprintf("%dm %ds", m, r)
        return sprintf("%ds", r)
      }
    ' "$jsonl"
    ;;
  *)
    usage
    ;;
esac
