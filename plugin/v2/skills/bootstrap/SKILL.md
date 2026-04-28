---
description: Bootstrap project with foundational rules and settings
---

# Bootstrap

Set up foundational project configuration. Safe to re-run — the HQ section of CLAUDE.md is managed by this skill, but every other change is confirmed with the user before applying.

## Principle

**Never silently skip and never silently overwrite.** When a target file already exists or already has the right content, report it and ask before changing anything. When proposing an overwrite, state the reason.

The only exception is the HQ block in CLAUDE.md, which is explicitly marked as bootstrap-managed — but even then, surface a one-line summary of what is changing and confirm with the user before writing.

## Progress Tracking

Use Claude Code's task UI (`TaskCreate` / `TaskUpdate`) to show progress. At the start of execution, create all tasks:

| Task subject | activeForm |
|---|---|
| Gather build & test config | Gathering build & test config |
| Set up CLAUDE.md | Setting up CLAUDE.md |
| Ensure attribution in settings.local.json | Ensuring attribution |
| Update .gitignore | Updating .gitignore |

Set each task to `in_progress` when starting and `completed` when done.

## Tasks

### 1. Gather build & test config

Goal: collect the information needed to fill CLAUDE.md `## Commands` and the HQ section.

**Detect project type** (multiple may match — handle all that match):

| Detection | Type |
|-----------|------|
| `*.xcodeproj` or `*.xcworkspace` exists | Xcode |
| `Package.swift` exists (without `*.xcodeproj`) | SwiftPM |
| `package.json` exists | Node/TS |
| `go.mod` exists | Go |

**Gather commands per type:**

- **Xcode** — invoke the `hq:xcodebuild-config` skill. It produces `.hq/xcodebuild-config.md` interactively. Use the resulting Build Command and Run Command for CLAUDE.md (build / dev rows).
- **Node/TS** — read `package.json` `scripts` and the `packageManager` field. Confirm with the user which scripts map to install / dev / build / test / lint / format. Default the package manager from `packageManager`; otherwise ask.
- **Go** — propose standard commands (`go build ./...`, `go test ./...`). Ask about lint/format tools (e.g. `golangci-lint run`, `gofmt -w .`).
- **SwiftPM** — propose `swift build`, `swift test`. Confirm with the user.
- **Other / unknown** — ask the user directly for each Commands row.

**Test strategy:**

Use `AskUserQuestion` to ask:

> How should this project be tested by Claude when verifying a change?
>
> 1. **Unit** — Claude runs the test command automatically before claiming a change is done.
> 2. **E2E** — Claude runs end-to-end checks (Playwright, hq:e2e-web, etc.) before claiming a change is done.
> 3. **Manual** — A human runs tests; Claude reports what changed and waits for confirmation.

Record the choice (and the resolved test command, if applicable) for use in Task 2's HQ section.

**Output**: hold the gathered info in conversation context — Task 2 reads it.

### 2. CLAUDE.md

**Target**: `<project_root>/CLAUDE.md`

The HQ section is delimited by `<!-- BEGIN HQ -->` ... `<!-- END HQ -->` and is owned by `hq:bootstrap`.

#### Branch A — file missing

- Copy [templates/claude-md.md](templates/claude-md.md), fill in:
  - `{{project_name}}` and the one-line description (from `package.json` / `go.mod` / `Package.swift`).
  - `## Commands` rows from Task 1 findings.
  - `{{build_pointer}}` and `{{test_strategy}}` in the HQ section (see **Resolved values** below).
- Save. Report the path.

#### Branch B — file exists, HQ markers present

1. Read the file. Compute the new HQ block from Task 1.
2. Show the user a one-line summary of what changes (e.g. "test strategy: Manual → Unit (`bun test`)"). If the new block is identical to the existing one, report "no change needed" and skip.
3. Use `AskUserQuestion`:
   - **Title**: `Overwrite HQ section in CLAUDE.md?`
   - **Reason**: "the HQ section is bootstrap-managed; re-running keeps it in sync with the latest workflow."
   - **Options**: `Overwrite` / `Skip`.
4. If approved, replace only the marked block. Do not touch any other section (Commands, Notes, etc. are user territory once the file exists).

#### Branch C — file exists, HQ markers absent

1. Compute the new HQ block from Task 1.
2. Use `AskUserQuestion`:
   - **Title**: `Append HQ section to CLAUDE.md?`
   - **Reason**: "no HQ markers found; the HQ workflow expects a `## HQ` block (Verification / Build / Test Strategy). Bootstrap appends it at the end of the file."
   - **Options**: `Append` / `Skip`.
3. If approved, append the block. Do not modify the rest.

#### Resolved values

- `{{build_pointer}}`:
  - Xcode → `See [.hq/xcodebuild-config.md](.hq/xcodebuild-config.md) for the canonical build / run commands.`
  - Other → `See \`## Commands\` above.`
  - Mixed (Xcode + other) → `Xcode: see [.hq/xcodebuild-config.md](.hq/xcodebuild-config.md). Other targets: see \`## Commands\` above.`
- `{{test_strategy}}`:
  - Unit → `Unit — run \`<test command>\` before claiming a change is done.`
  - E2E → `E2E — run end-to-end checks (e.g. Playwright, hq:e2e-web) before claiming a change is done.`
  - Manual → `Manual — tests are run by a human. Report what was changed; do not claim "verified" without human confirmation.`

### 3. settings.local.json

**Target**: `<project_root>/.claude/settings.local.json`

The template carries only the `attribution` block. Empty strings suppress Claude Code's default footer in commits and PRs.

```json
{ "attribution": { "commit": "", "pr": "" } }
```

#### Branch A — file missing

- Copy [templates/settings.json](templates/settings.json). Report the path.

#### Branch B — file exists, has `attribution`

- Report "attribution already set" and skip. No prompt needed.

#### Branch C — file exists, no `attribution`

- Use `AskUserQuestion`:
  - **Title**: `Add attribution block to settings.local.json?`
  - **Reason**: "adds `attribution: { commit: '', pr: '' }` so commits and PRs from this project don't carry the default Claude Code footer. Existing values in the file are not modified."
  - **Options**: `Add` / `Skip`.
- If approved, deep-merge the template (existing values are never overwritten).

Note: detection-based permission entries are no longer added. Auto mode covers most prompts; users can extend `permissions.allow` themselves with `/update-config`.

### 4. .gitignore

**Target**: `<project_root>/.gitignore`

#### Branch A — file missing

- Create with a single line: `.hq/`. Report the path.

#### Branch B — file exists, contains `.hq/`

- Report "`.hq/` already ignored" and skip.

#### Branch C — file exists, no `.hq/` entry

- Use `AskUserQuestion`:
  - **Title**: `Append \`.hq/\` to .gitignore?`
  - **Reason**: "`.hq/` is the HQ working directory (task context, FB files, scan reports). It is local-only and should not be committed."
  - **Options**: `Append` / `Skip`.
- If approved, append `.hq/` to the file.
