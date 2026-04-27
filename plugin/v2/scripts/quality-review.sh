#!/usr/bin/env bash
# Quality Review event recorder & summarizer for /hq:start Phase 6.
# Subcommands:
#   record <event-type> [key=val ...]   append a JSONL event line
#   summary                              print Initial / Round N / Termination breakdown
#
# JSONL path: .hq/tasks/<branch-dir>/quality-review-events.jsonl
#
# Event types (6):
#   initial_review  agent=<name> fb_count=<n> severity=C:n,H:n,M:n,L:n
#   round_start     round=<N> fix_set_size=<n>
#   relaunch        round=<N> agents=<comma-list>      (or skipped=all_low)
#   round_end       round=<N> resolved=<n> persistent=<n> new=<n>
#   cap_exit        low_count=<n> non_low_count=<n>
#   terminated      reason=<fix_set_empty|all_low_skip|cap_exhausted|cap_exit_low_fix>
#
# All key=val pairs become JSON string fields. The schema is append-only —
# unknown keys are preserved in the JSONL but ignored by `summary`.
set -euo pipefail
IFS=$'\n\t'

usage() {
  cat >&2 <<EOF
Usage:
  $(basename "$0") record <event-type> [key=val ...]
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
  echo "${root}/.hq/tasks/${branch_dir}/quality-review-events.jsonl"
}

json_escape() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

[[ $# -ge 1 ]] || usage
cmd="$1"
shift

case "$cmd" in
  record)
    [[ $# -ge 1 ]] || usage
    event="$1"
    shift
    case "$event" in
      initial_review|round_start|relaunch|round_end|cap_exit|terminated) ;;
      *) echo "error: unknown event type '$event'" >&2; exit 2 ;;
    esac
    jsonl=$(resolve_jsonl)
    mkdir -p "$(dirname "$jsonl")"
    ts=$(date +%s)
    line='{"event":"'"$(json_escape "$event")"'","ts":'"$ts"
    for kv in "$@"; do
      key=${kv%%=*}
      val=${kv#*=}
      [[ "$key" == "$kv" ]] && { echo "error: argument '$kv' must be in key=val form" >&2; exit 2; }
      line+=',"'"$(json_escape "$key")"'":"'"$(json_escape "$val")"'"'
    done
    line+='}'
    printf '%s\n' "$line" >> "$jsonl"
    ;;
  summary)
    [[ $# -eq 0 ]] || usage
    jsonl=$(resolve_jsonl)
    if [[ ! -s "$jsonl" ]]; then
      echo "No quality-review events recorded."
      exit 0
    fi
    awk '
      function get(line, key,   v) {
        v = line
        if (match(v, "\"" key "\":\"[^\"]*\"")) {
          v = substr(v, RSTART, RLENGTH)
          sub("\"" key "\":\"", "", v)
          sub("\"$", "", v)
          return v
        }
        if (match(v, "\"" key "\":[0-9]+")) {
          v = substr(v, RSTART, RLENGTH)
          sub("\"" key "\":", "", v)
          return v
        }
        return ""
      }
      function event_of(line,   v) {
        v = line
        if (match(v, "\"event\":\"[^\"]*\"")) {
          v = substr(v, RSTART, RLENGTH)
          sub("\"event\":\"", "", v)
          sub("\"$", "", v)
          return v
        }
        return ""
      }
      function parse_severity(s,    n, sparts, i, kv, k, v, pair) {
        sev_C = 0; sev_H = 0; sev_M = 0; sev_L = 0
        n = split(s, sparts, ",")
        for (i = 1; i <= n; i++) {
          kv = sparts[i]
          if (split(kv, pair, ":") == 2) {
            k = pair[1]; v = pair[2] + 0
            if (k == "C") sev_C = v
            else if (k == "H") sev_H = v
            else if (k == "M") sev_M = v
            else if (k == "L") sev_L = v
          }
        }
      }
      {
        ev = event_of($0)
        if (ev == "initial_review") {
          a = get($0, "agent")
          if (!(a in init_seen_agent)) {
            init_seen_agent[a] = 1
            init_agents[++init_n] = a
          }
          init_sev[a] = get($0, "severity")
          init_fb[a] = get($0, "fb_count")
        } else if (ev == "round_start") {
          rnd = get($0, "round") + 0
          if (rnd > max_round) max_round = rnd
          round_seen[rnd] = 1
          round_fix_set[rnd] = get($0, "fix_set_size")
        } else if (ev == "relaunch") {
          rnd = get($0, "round") + 0
          if (rnd > max_round) max_round = rnd
          round_seen[rnd] = 1
          if (get($0, "skipped") != "") {
            round_relaunch[rnd] = "skipped(" get($0, "skipped") ")"
          } else {
            round_relaunch[rnd] = get($0, "agents")
          }
        } else if (ev == "round_end") {
          rnd = get($0, "round") + 0
          if (rnd > max_round) max_round = rnd
          round_seen[rnd] = 1
          round_resolved[rnd] = get($0, "resolved")
          round_persistent[rnd] = get($0, "persistent")
          round_new[rnd] = get($0, "new")
        } else if (ev == "cap_exit") {
          cap_low = get($0, "low_count")
          cap_non_low = get($0, "non_low_count")
          cap_seen = 1
        } else if (ev == "terminated") {
          term_reason = get($0, "reason")
          term_seen = 1
        }
      }
      END {
        if (init_n > 0) {
          print "Initial:"
          for (i = 1; i <= init_n; i++) {
            a = init_agents[i]
            parse_severity(init_sev[a])
            printf "  %s: C:%d H:%d M:%d L:%d", a, sev_C, sev_H, sev_M, sev_L
            if (init_fb[a] != "") printf " (total=%s)", init_fb[a]
            printf "\n"
          }
          print ""
        }
        for (r = 1; r <= max_round; r++) {
          if (!round_seen[r]) continue
          printf "Round %d:\n", r
          parts_n = 0
          if (round_fix_set[r] != "") parts[++parts_n] = "fix_set=" round_fix_set[r]
          if (round_resolved[r] != "") parts[++parts_n] = "resolved=" round_resolved[r]
          if (round_persistent[r] != "") parts[++parts_n] = "persistent=" round_persistent[r]
          if (round_new[r] != "") parts[++parts_n] = "new=" round_new[r]
          if (round_relaunch[r] != "") parts[++parts_n] = "relaunch=" round_relaunch[r]
          out = ""
          for (i = 1; i <= parts_n; i++) {
            out = out (i == 1 ? "  " : ", ") parts[i]
          }
          if (parts_n > 0) print out
          print ""
        }
        if (term_seen || cap_seen) {
          print "Termination:"
          tn = 0
          if (term_reason != "") tparts[++tn] = "reason=" term_reason
          if (cap_seen) {
            tparts[++tn] = "low_count=" cap_low
            tparts[++tn] = "non_low_count=" cap_non_low
          }
          out = ""
          for (i = 1; i <= tn; i++) {
            out = out (i == 1 ? "  " : ", ") tparts[i]
          }
          if (tn > 0) print out
        }
      }
    ' "$jsonl"
    ;;
  *)
    usage
    ;;
esac
