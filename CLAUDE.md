# HQ

A development hub for AI-assisted workflows across multiple projects.

## Repository Overview

- **.claude-plugin/** — Plugin manifest (`plugin.json`): defines commands, agents, and skills paths
- **plugin/v3/** — Active plugin version (commands, agents, skills)
- **plugin/v2/** — Legacy — frozen, do not modify
- **plugin/v1/** — Legacy — do not modify
- **tools/** — CLI tools (Go binary)

## Building Tools

- `mise run build` — Build `tools/cli` binary to `tools/bin/hq`
- `mise run install` — Build and install to `~/.local/bin/hq`

## Plugin Development

- For plugin structure (plugin.json, commands, agents, skills, hooks), always refer to the official Claude Code documentation: https://docs.anthropic.com/en/docs/claude-code/plugins

## Dogfooding

This repository develops its own plugin and uses that same plugin (the `hq:*` commands, agents, and skills under `plugin/v3/`) to drive its own development workflow. Changes to the workflow are exercised here first.

The workflow rules live under **`plugin/v3/rules/`**: `workflow.md` (cross-cutting source of truth, read by every `/hq:*` command on invocation) plus one `<name>-protocol.md` per major command (`draft` / `start` / `triage` — the full phase specifications; the `commands/*.md` files are thin entry stubs that Read and execute them). There is no copy, no distribution step, and no consumer-side build artifact: editing these files is the change.

## Language Policy

- Agent instructions (CLAUDE.md, rules, skills, commands): English
- User-facing documents: follow the user's language
- Session conversation: follow the user's language
