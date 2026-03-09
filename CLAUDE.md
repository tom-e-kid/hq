# HQ

Centralized management of monthly logs, project info, and knowledge base — designed for AI agent collaboration.

## Repository Overview

- **db/** — Data directory (monthly logs, project info, knowledge base, inbox). Not included in this repo; location is configured via `~/.hq/settings.json` (`data_dir`)
- **plugin/** — Claude Code plugin (skills, commands)
- **tools/** — CLI tools (Go binary)

## .hq Directory

Two levels of `.hq` exist:

- **`~/.hq/`** — Global HQ config (shared across all projects)
  - `settings.json` — Global settings (e.g., `data_dir`)
  - `wip.md` — Cross-project WIP tracker
  - `memory.md` — Global memory log (cross-project lessons learned)
- **`<project>/.hq/`** — Per-project HQ data
  - `settings.json` — Project-specific settings (e.g., `base_branch`)
  - `tasks/` — Task tracking files
  - `memory.md` — Memory log (lessons learned, rules to follow)

## Path Conventions

- `SRCROOT`: Three levels up from this repo (`../../../`). Locally `~/dev/src/`
- Combine each project's README.md frontmatter `repo` field to resolve the actual path
- Example: `repo: "github.com/tom-e-kid/project_a"` → `SRCROOT/github.com/tom-e-kid/project_a/`

## Building Tools

- `mise run build` — Build `tools/cli` binary to `tools/bin/hq`
- `mise run install` — Build and install to `~/.local/bin/hq`

## Language Policy

- Agent instructions (CLAUDE.md, rules, skills, commands): English
- User-facing documents (db/ contents): Japanese
- Session conversation: match the user's language

## Operational Rules

- Always invoke the `/hq:dev` skill before starting any implementation work. Do not skip this even when the user provides a ready-made plan
- Anonymize sensitive information (real client names, personal names, tokens, etc.). Never commit real names
- Time entries in db/logs/ follow the format `Project:Category: hours`
- See `.claude/rules/` for detailed rules
