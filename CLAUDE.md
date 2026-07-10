# HQ

A development hub for AI-assisted workflows across multiple projects.

## Repository Overview

- **.claude-plugin/** — Plugin manifest (`plugin.json`): defines commands, agents, and skills paths
- **plugin/v3/** — Active plugin version (commands, agents, skills)
- **plugin/v2/** — Legacy — frozen, do not modify
- **plugin/v1/** — Legacy — do not modify

CLI tools formerly under `tools/` were split out to [github.com/tom-e-kid/hqdb](https://github.com/tom-e-kid/hqdb) (commit `7ab6454`). This repository has no build step — it is plugin (markdown) only.

## Plugin Development

- For plugin structure (plugin.json, commands, agents, skills, hooks), always refer to the official Claude Code documentation: https://docs.anthropic.com/en/docs/claude-code/plugins

## Dogfooding

This repository develops its own plugin and uses that same plugin (the `hq:*` commands, agents, and skills under `plugin/v3/`) to drive its own development workflow. Changes to the workflow are exercised here first.

The workflow rules live under **`plugin/v3/rules/`**: `workflow.md` (cross-cutting source of truth, read on every invocation) plus the stage protocols `draft-protocol.md` / `execute-protocol.md` (full phase specifications, Read-and-followed by the loop and its agents). The pipeline has a single entry command — `commands/loop.md` (`/hq:loop`, Stages 0–7 + root judgments J1–J8) — with `/hq:respond` and `/hq:archive` as post-PR tools. There is no copy, no distribution step, and no consumer-side build artifact: editing these files is the change.

## Language Policy

- Agent instructions (CLAUDE.md, rules, skills, commands): English
- User-facing documents: follow the user's language
- Session conversation: follow the user's language
