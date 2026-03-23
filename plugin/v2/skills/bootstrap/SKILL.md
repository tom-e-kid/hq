---
description: Bootstrap project with foundational rules and settings
---

# Bootstrap

Set up foundational project configuration. Run this once when initializing a new project or when rules are missing.

## Tasks

For each task, check if the target file already exists. If yes, skip and report. If no, create it from the template.

### 1. CLAUDE.md

**Target**: `<project_root>/CLAUDE.md`

Copy [templates/claude-md.md](templates/claude-md.md) and fill in the placeholders based on the project's actual codebase (package.json, go.mod, Makefile, etc.).

### 2. Manifest Rule

**Target**: `<project_root>/.claude/rules/manifest.md`

Copy [templates/manifest.md](templates/manifest.md) as-is.

### 3. Workflow Rule

**Target**: `<project_root>/.claude/rules/workflow.md`

Copy [templates/workflow.md](templates/workflow.md) as-is.
