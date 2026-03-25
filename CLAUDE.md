# HQ

A development hub for AI-assisted workflows across multiple projects.

## Repository Overview

- **db/** — Data directory (monthly logs, project info, knowledge base, inbox). Not included in this repo; location is configured via `~/.hq/settings.json` (`data_dir`)
- **plugin/** — Claude Code plugin (skills, commands)
- **tools/** — CLI tools (Go binary)

## Building Tools

- `mise run build` — Build `tools/cli` binary to `tools/bin/hq`
- `mise run install` — Build and install to `~/.local/bin/hq`

## Plugin Development

- Active version: **v2** (`plugin/v2/`)
- `plugin/v1/` is legacy — do not modify
- Core principle: **source traceability** — every artifact (taskfile, FB, PR) must trace back to its origin via a `source` field. Work without a traceable source is not allowed.
- **Focus** (`memory/focus.md`) is the single authority for "what I'm working on and why." All skills read from here. This ensures traceability survives session clears.

## Language Policy

- Agent instructions (CLAUDE.md, rules, skills, commands): English
- User-facing documents (db/ contents): Japanese
- Session conversation: match the user's language
