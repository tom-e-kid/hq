---
description: Bootstrap project with foundational rules and settings
---

# Bootstrap

Set up foundational project configuration. Run this once when initializing a new project or when rules are missing.

## Arguments

- `agents.md` — also install AGENTS.md (Task 4). Without this argument, Task 4 is skipped.

## Tasks

### 1. CLAUDE.md

**Target**: `<project_root>/CLAUDE.md`

If it already exists, skip and report. If not, copy [templates/claude-md.md](templates/claude-md.md) and fill in the placeholders based on the project's actual codebase (package.json, go.mod, Makefile, etc.).

### 2. Workflow Rule

**Target**: `<project_root>/.claude/rules/workflow.md`

If it already exists, rename to `workflow.md.bak` (overwrite existing `.bak`), then copy [templates/workflow.md](templates/workflow.md). Report what was backed up.

### 3. Settings

**Target**: `<project_root>/.claude/settings.json`

If it already exists, skip and report. If not:

1. Copy [templates/settings.json](templates/settings.json)
2. Detect the project type and append platform-specific permissions to `permissions.allow`:

| Detection | Permissions to add |
|-----------|-------------------|
| `*.xcodeproj` or `*.xcworkspace` exists | `Bash(swift-format:*)`, `Bash(xcodebuild:*)`, `Bash(xcrun:*)` |
| `package.json` or `tsconfig.json` exists | `Bash(bun:*)` |
| `go.mod` exists | `Bash(go build:*)`, `Bash(go vet:*)` |

Multiple detections can match (e.g., a monorepo with both Go and TypeScript). Add all matching permissions.

### 4. AGENTS.md (optional — requires `agents.md` argument)

**Skip this task entirely unless the user passed `agents.md` as an argument.**

**Target**: `<project_root>/AGENTS.md`

If it already exists, skip and report. If not, copy [templates/agents-md.md](templates/agents-md.md). This provides code review and security scan instructions for non-Claude Code AI agents.

### 5. .gitignore

**Target**: `<project_root>/.gitignore`

Ensure `.hq/` is listed in `.gitignore`. If the file doesn't exist, create it. If it exists but doesn't contain `.hq/`, append it. If already present, skip and report.

### 6. GitHub Labels

**Prerequisites**: `gh auth status` must succeed. If it fails, warn the user and skip this step.

Create the following labels if they don't already exist:

```bash
gh label create "hq:task" --description "HQ requirement (what to do)" --color "39FF14" 2>/dev/null || true
gh label create "hq:plan" --description "HQ implementation plan (how to do it)" --color "00D4FF" 2>/dev/null || true
gh label create "hq:feedback" --description "HQ unresolved feedback from review/verification" --color "FF073A" 2>/dev/null || true
```

Report which labels were created and which already existed.
