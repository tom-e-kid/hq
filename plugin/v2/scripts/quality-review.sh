#!/usr/bin/env bash
# Quality Review event recorder & summarizer for /hq:start Phase 6 (Self-Review) and Phase 7 (Quality Review).
# Subcommands:
#   record <event-type> [key=val ...]   append a JSONL event line
#   summary                              print Self-Review Gate / Agent Selection / Initial breakdown
#
# JSONL path: .hq/tasks/<branch-dir>/quality-review-events.jsonl
#
# Event types (3):
#   self_review_gate  result=<pass|minor_gap|significant_gap>
#   agent_selection   mode=<judgment|full> launched=<comma-list> skipped=<comma-list>
#   initial_review    agent=<name> fb_count=<n> severity=C:n,H:n,M:n,L:n
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
  s=${s//$'\b'/\\b}
  s=${s//$'\t'/\\t}
  s=${s//$'\n'/\\n}
  s=${s//$'\f'/\\f}
  s=${s//$'\r'/\\r}
  s=${s//$'\x01'/\\u0001}
  s=${s//$'\x02'/\\u0002}
  s=${s//$'\x03'/\\u0003}
  s=${s//$'\x04'/\\u0004}
  s=${s//$'\x05'/\\u0005}
  s=${s//$'\x06'/\\u0006}
  s=${s//$'\x07'/\\u0007}
  s=${s//$'\x0b'/\\u000b}
  s=${s//$'\x0e'/\\u000e}
  s=${s//$'\x0f'/\\u000f}
  s=${s//$'\x10'/\\u0010}
  s=${s//$'\x11'/\\u0011}
  s=${s//$'\x12'/\\u0012}
  s=${s//$'\x13'/\\u0013}
  s=${s//$'\x14'/\\u0014}
  s=${s//$'\x15'/\\u0015}
  s=${s//$'\x16'/\\u0016}
  s=${s//$'\x17'/\\u0017}
  s=${s//$'\x18'/\\u0018}
  s=${s//$'\x19'/\\u0019}
  s=${s//$'\x1a'/\\u001a}
  s=${s//$'\x1b'/\\u001b}
  s=${s//$'\x1c'/\\u001c}
  s=${s//$'\x1d'/\\u001d}
  s=${s//$'\x1e'/\\u001e}
  s=${s//$'\x1f'/\\u001f}
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
      self_review_gate|agent_selection|initial_review) ;;
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
        if (match(v, "[{,]\"" key "\":\"[^\"]*\"")) {
          v = substr(v, RSTART + 1, RLENGTH - 1)
          sub("\"" key "\":\"", "", v)
          sub("\"$", "", v)
          return v
        }
        if (match(v, "[{,]\"" key "\":[0-9]+")) {
          v = substr(v, RSTART + 1, RLENGTH - 1)
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
        if (ev == "self_review_gate") {
          gate_result = get($0, "result")
          gate_seen = 1
        } else if (ev == "agent_selection") {
          sel_mode = get($0, "mode")
          sel_launched = get($0, "launched")
          sel_skipped = get($0, "skipped")
          sel_seen = 1
        } else if (ev == "initial_review") {
          a = get($0, "agent")
          if (!(a in init_seen_agent)) {
            init_seen_agent[a] = 1
            init_agents[++init_n] = a
          }
          init_sev[a] = get($0, "severity")
          init_fb[a] = get($0, "fb_count")
        }
      }
      END {
        if (gate_seen) {
          print "Self-Review Gate:"
          printf "  result=%s\n", gate_result
          print ""
        }
        if (sel_seen) {
          print "Agent Selection:"
          printf "  mode=%s", sel_mode
          if (sel_launched != "") printf ", launched=%s", sel_launched
          if (sel_skipped != "") printf ", skipped=%s", sel_skipped
          print ""
          print ""
        }
        if (init_n > 0) {
          print "Initial:"
          for (i = 1; i <= init_n; i++) {
            a = init_agents[i]
            parse_severity(init_sev[a])
            printf "  %s: C:%d H:%d M:%d L:%d", a, sev_C, sev_H, sev_M, sev_L
            if (init_fb[a] != "") printf " (total=%s)", init_fb[a]
            printf "\n"
          }
        }
      }
    ' "$jsonl"
    ;;
  *)
    usage
    ;;
esac
