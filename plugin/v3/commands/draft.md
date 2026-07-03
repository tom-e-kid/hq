---
name: draft
description: Exploration-led brainstorm + Simplicity gatekeeper → create an hq:plan file (optionally from an hq:task)
allowed-tools: Read, Write, Glob, Grep, Bash(git:*), Bash(gh:*), Bash(bash:*), Bash(mkdir:*), TaskCreate, TaskUpdate
---

# DRAFT — Brainstorm & Create `hq:plan`

Entry point for the **Draft Protocol**. This command file carries only context injection and argument handling; the protocol itself — phases, gates, rules — lives in the rule file below and is the single source of truth.

## Context

- Branch: !`git branch --show-current 2>/dev/null || echo "(detached)"`
- Focus: !`bash "${CLAUDE_PLUGIN_ROOT}/plugin/v3/scripts/read-context.sh"`
- Project Overrides (`.hq/draft.md`): !`cat .hq/draft.md 2>/dev/null || echo "none"`

## Arguments

`$ARGUMENTS` — optional `hq:task` Issue number (accept `#1234` or `1234`), optionally followed by supplementary context text. May be empty.

## Execute

Read `${CLAUDE_PLUGIN_ROOT}/plugin/v3/rules/draft-protocol.md` with the Read tool and execute it, passing:

- the argument parsed above as the protocol's `hq:task` input,
- the Context block above as the protocol's context acquisition (already injected — do not re-run those commands).

Follow the protocol verbatim — including its interactive Phase 2 brainstorm, the Phase 3 commit-or-pushback gate, and all of its Rules.
