---
name: start
description: Autonomous workflow — branch → execute → acceptance → quality review → PR from an hq:plan
allowed-tools: Read, Edit, Write, Glob, Grep, Bash(git:*), Bash(gh:*), Bash(bash:*), Bash(mkdir:*), Bash(mv:*), Bash(rm:*), Agent, TaskCreate, TaskUpdate
---

# START — Autonomous: hq:plan → PR

Entry point for the **Start Protocol**. This command file carries only context injection and argument handling; the protocol itself — phases, gates, settings, stop policy — lives in the rule file below and is the single source of truth.

## Context

- Branch: !`git branch --show-current 2>/dev/null || echo "(detached)"`
- Focus: !`bash "${CLAUDE_PLUGIN_ROOT}/plugin/v3/scripts/read-context.sh"`
- Project Overrides (`.hq/start.md`): !`cat .hq/start.md 2>/dev/null || echo "none"`

## Arguments

`$ARGUMENTS` — optional plan query: a branch name or unique substring (resolved via `find-plan.sh`). Empty = the current branch's plan.

## Execute

Read `${CLAUDE_PLUGIN_ROOT}/plugin/v3/rules/start-protocol.md` with the Read tool and execute it in **standalone mode**, passing:

- the plan query parsed above as the protocol's input,
- the Context block above as the protocol's context acquisition (already injected — do not re-run those commands).

Follow the protocol verbatim — including its Settings, Commit Policy, Phase Timing stamps, and Stop Policy.
