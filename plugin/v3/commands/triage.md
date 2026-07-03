---
name: triage
description: Triage PR Known Issues section — add to hq:plan / leave / fix in place / escalate to hq:feedback
allowed-tools: Read, Edit, Write, Glob, Grep, Bash(git:*), Bash(gh:*), Bash(bash:*), TaskCreate, TaskUpdate
---

# TRIAGE — Sort Residual PR Known Issues

Entry point for the **Triage Protocol**. This command file carries only context injection and argument handling; the protocol itself — phases, the ordered gate, the strict-interactive contract — lives in the rule file below and is the single source of truth.

## Context

- Branch: !`git branch --show-current 2>/dev/null || echo "(detached)"`
- Focus: !`bash "${CLAUDE_PLUGIN_ROOT}/plugin/v3/scripts/read-context.sh"`
- Project Overrides (`.hq/triage.md`): !`cat .hq/triage.md 2>/dev/null || echo "none"`

## Arguments

`$ARGUMENTS` — PR number (accept `#1234` or `1234`). Required; if missing, ask once.

## Execute

Read `${CLAUDE_PLUGIN_ROOT}/plugin/v3/rules/triage-protocol.md` with the Read tool and execute it in **interactive mode**, passing:

- the PR number parsed above as the protocol's input,
- the Context block above as the protocol's context acquisition (already injected — do not re-run those commands).

Follow the protocol verbatim — including strict per-item serialization in Phase 3 and the "no disposition applied without an explicit per-item response" invariant.
