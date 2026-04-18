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

As a consequence, two copies of the workflow rule file exist and must be kept identical:

- **`plugin/v2/skills/bootstrap/templates/workflow.md`** — **source of truth**. Distributed by the `hq:bootstrap` skill to consumer projects. **Edit here.**
- **`.claude/rules/workflow.local.md`** — this repo's own dogfooding copy, produced by running `hq:bootstrap` against this repo. **Not a development target** — never edit directly; re-sync from the template instead.

When updating workflow rules: edit the template first, then copy to `.claude/rules/workflow.local.md` (or re-run `hq:bootstrap`). Verify `diff` is empty between the two before committing.

## Language Policy

- Agent instructions (CLAUDE.md, rules, skills, commands): English
- User-facing documents: follow the user's language
- Session conversation: follow the user's language
