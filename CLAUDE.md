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

The workflow rule lives in two files:

- **`plugin/v2/skills/bootstrap/templates/workflow.md`** — **source of truth**. Distributed by the `hq:bootstrap` skill to consumer projects. **Edit here only.**
- **`.claude/rules/workflow.local.md`** — a generated copy produced by `hq:bootstrap` running against this repo. **Not a development target** — never edit directly. Treat it as a build artifact.

Workflow-rule PRs touch the template only. The dogfooding copy is refreshed out-of-band by re-running `/hq:bootstrap`; it does not need to be synced per commit, and a diff against the template during active development is expected and acceptable.

## Language Policy

- Agent instructions (CLAUDE.md, rules, skills, commands): English
- User-facing documents: follow the user's language
- Session conversation: follow the user's language
