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

## Language Policy

- Agent instructions (CLAUDE.md, rules, skills, commands): English
- User-facing documents: follow the user's language
- Session conversation: follow the user's language
