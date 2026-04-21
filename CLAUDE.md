# HQ

A development hub for AI-assisted workflows across multiple projects.

## Repository Overview

- **.claude-plugin/** — Plugin manifest (`plugin.json`): defines commands, agents, and skills paths
- **plugin/v2/** — Active plugin version (commands, agents, skills)
- **plugin/v1/** — Legacy — do not modify
- **tools/** — CLI tools (Go binary)

## Building Tools

- `mise run build` — Build `tools/cli` binary to `tools/bin/hq`
- `mise run install` — Build and install to `~/.local/bin/hq`

## Plugin Development

- For plugin structure (plugin.json, commands, agents, skills, hooks), always refer to the official Claude Code documentation: https://docs.anthropic.com/en/docs/claude-code/plugins

## Dogfooding

This repository develops its own plugin and uses that same plugin (the `hq:*` commands, agents, and skills under `plugin/v2/`) to drive its own development workflow. Changes to the workflow are exercised here first.

The workflow rule is a single file: **`plugin/v2/rules/workflow.md`**. This is the plugin-internal source of truth — each `/hq:*` command reads it on invocation. There is no copy, no distribution step, and no consumer-side build artifact: editing this file is the change.

## Language Policy

- Agent instructions (CLAUDE.md, rules, skills, commands): English
- User-facing documents: follow the user's language
- Session conversation: follow the user's language
