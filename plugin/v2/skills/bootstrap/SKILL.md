---
description: Bootstrap project with foundational rules and settings
---

# Bootstrap

Set up foundational project configuration. Run this once when initializing a new project or when rules are missing.

## Tasks

### 1. CLAUDE.md

**Target**: `<project_root>/CLAUDE.md`

If it already exists, skip and report. If not, copy [templates/claude-md.md](templates/claude-md.md) and fill in the placeholders based on the project's actual codebase (package.json, go.mod, Makefile, etc.).

### 2. Manifest Rule

**Target**: `<project_root>/.claude/rules/manifest.md`

If it already exists, rename to `manifest.md.bak` (overwrite existing `.bak`), then copy [templates/manifest.md](templates/manifest.md). Report what was backed up.

### 3. Workflow Rule

**Target**: `<project_root>/.claude/rules/workflow.md`

If it already exists, rename to `workflow.md.bak` (overwrite existing `.bak`), then copy [templates/workflow.md](templates/workflow.md). Report what was backed up.

### 4. AGENTS.md

**Target**: `<project_root>/AGENTS.md`

If it already exists, skip and report. If not, copy [templates/agents-md.md](templates/agents-md.md). This provides code review and security scan instructions for non-Claude Code AI agents.
