---
description: Bootstrap project with foundational rules and settings
---

# Bootstrap

Set up foundational project configuration. Run this once when initializing a new project.

## Arguments

- `agents.md` — also install AGENTS.md (Task 2). Without this argument, Task 2 is skipped.

## Progress Tracking

Use Claude Code's task UI (`TaskCreate` / `TaskUpdate`) to show progress. At the start of execution, create all tasks:

| Task subject | activeForm |
|---|---|
| Set up CLAUDE.md | Setting up CLAUDE.md |
| Set up AGENTS.md | Setting up AGENTS.md |
| Merge settings.local.json | Merging settings.local.json |
| Update .gitignore | Updating .gitignore |

Set each task to `in_progress` when starting and `completed` when done. If a task is skipped (e.g., AGENTS.md without argument), mark it as `completed` immediately with subject updated to show "skipped".

## Tasks

### 1. CLAUDE.md

**Target**: `<project_root>/CLAUDE.md`

If it already exists, skip and report. If not, copy [templates/claude-md.md](templates/claude-md.md) and fill in the placeholders based on the project's actual codebase (package.json, go.mod, Makefile, etc.).

### 2. AGENTS.md (optional — requires `agents.md` argument)

**Skip this task entirely unless the user passed `agents.md` as an argument.**

**Target**: `<project_root>/AGENTS.md`

If it already exists, skip and report. If not, copy [templates/agents-md.md](templates/agents-md.md). This provides code review and security scan instructions for non-Claude Code AI agents.

### 3. Settings

**Target**: `<project_root>/.claude/settings.local.json`

If it does not exist, copy [templates/settings.json](templates/settings.json) as the starting point.

If it already exists, read the existing file and **deep-merge** — for every key in the template, if the key is missing in the target, add it. For array values (e.g., `permissions.allow`), append missing entries without removing existing ones. Never remove or overwrite existing entries.

After creating or merging, detect the project type and append platform-specific permissions to `permissions.allow` (skip any already present):

| Detection | Permissions to add |
|-----------|-------------------|
| `*.xcodeproj` or `*.xcworkspace` exists | `Bash(swift-format:*)`, `Bash(xcodebuild:*)`, `Bash(xcrun:*)` |
| `package.json` or `tsconfig.json` exists | `Bash(bun:*)` |
| `go.mod` exists | `Bash(go build:*)`, `Bash(go vet:*)` |

Multiple detections can match (e.g., a monorepo with both Go and TypeScript). Add all matching permissions.

### 4. .gitignore

**Target**: `<project_root>/.gitignore`

Ensure the following entries are listed in `.gitignore`. For each entry, append it if missing. If the file doesn't exist, create it.

- `**/*.local.*` — excludes local-only config files (e.g., `settings.local.json`)
- `.hq/` — excludes HQ working directory
