---
description: Bootstrap project with foundational rules and settings
---

# Bootstrap

Set up foundational project configuration. Run this once when initializing a new project or when rules are missing.

## Tasks

### 1. Manifest Rule

Place `.claude/rules/manifest.md` in the project root if it doesn't already exist.

**Check**: Does `<project_root>/.claude/rules/manifest.md` exist?

- **If yes**: Skip. Report that manifest already exists.
- **If no**: Copy [templates/manifest.md](templates/manifest.md) to `<project_root>/.claude/rules/manifest.md`.

## Future Tasks

Additional bootstrap tasks will be added here as needed.
