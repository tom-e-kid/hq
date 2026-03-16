---
description: "Start development (branch management, platform setup, planning)"
argument-hint: "[platform (optional: ios, etc. Auto-detected if omitted)]"
---

Start the development workflow.

## Arguments

- `$ARGUMENTS`: Platform name (optional). Auto-detected if omitted.

## Steps

### 1. Load core rules

Read `${CLAUDE_PLUGIN_ROOT}/plugin/skills/dev-core/SKILL.md` using the Read tool.
Follow its contents throughout the entire workflow.

### 2. Load platform skill

**If an argument is provided**:
- Read `${CLAUDE_PLUGIN_ROOT}/plugin/skills/dev-$ARGUMENTS/SKILL.md` using the Read tool
- If the file does not exist, report an error and stop

**If no argument (auto-detect)**:
Check the following conditions in order; load the first matching platform skill:

| Detection condition | Skill file |
|---|---|
| `*.xcworkspace` or `*.xcodeproj` exists | `dev-ios/SKILL.md` |

If no platform matches → continue without a platform skill.

### 3. Start workflow

Follow the "MANDATORY: Before Implementation" section of the dev-core skill, starting from Step 1.

### 4. Update WIP tracking

After the taskfile is created and approved (dev-core Step 4):

1. Read `~/.hq/wip.md` (create if missing with frontmatter only)
2. Get the current branch via `git branch --show-current`
3. If the branch already has an entry, skip
4. Otherwise append a new line:
   ```
   - <project>: <description> (branch: <branch>)
   ```
