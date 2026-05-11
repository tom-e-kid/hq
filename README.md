# HQ

A Claude Code plugin for AI-assisted development workflows, anchored in GitHub Issues and PRs.

HQ separates a feature from idea to merge into a small set of command-scoped operations, with **two user interventions** as the only mandatory checkpoints — everything else runs autonomously. All work is traceable through GitHub Issues and PRs; the plugin leaves nothing behind in the consumer repo.

## Workflow

```
                 (intervention #1)   (intervention #2)
                  review hq:plan       review hq:pr
                         ↓                   ↓
 hq:task ─/hq:draft─→ hq:plan ─/hq:start─→ hq:pr ──┬─ merge ─/hq:archive─→
                                                   │
                                                   ├─ /hq:triage   (Known Issues from PR body)
                                                   └─ /hq:respond  (external review comments)
```

- **`hq:task`** = trigger (what to build — requirement)
- **`hq:plan`** = center of execution (how to build it — drives execution, verification, PR)
- **`hq:pr`** = the PR that realizes an `hq:plan`; carries `Closes #<plan>` + `Refs #<task>`

The two review points are the workflow's center of gravity. Everything downstream of intervention #2 is **user-directed** — `/hq:triage` and `/hq:respond` compose freely, not in a fixed sequence.

For the full lifecycle, plan body schema, sync model, and per-command phase breakdown, see [plugin/v2/docs/workflow.md](plugin/v2/docs/workflow.md). The authoritative rule specifications live at [plugin/v2/rules/workflow.md](plugin/v2/rules/workflow.md), loaded on demand by each command.

## Components

### Commands (user-invoked workflow shortcuts — `/hq:<name>`)

| Command  | Description |
|----------|-------------|
| `draft`   | Interactive brainstorm → create an `hq:plan` Issue from an `hq:task` |
| `start`   | Autonomous: branch → execute → acceptance → quality review → PR |
| `triage`  | Triage PR body `## Known Issues` — add to plan / leave / escalate to `hq:feedback` |
| `respond` | Respond to external PR review comments — fix / escalate / dismiss |
| `archive` | Safely close a merged PR's branch — verify + archive task folder + delete local branch |
| `swift-protocol-shadow` | Detect protocol default implementation shadowing in Swift ([flow](plugin/v2/docs/swift-protocol-shadow-flow.md)) |

### Skills (analysis criteria)

| Skill | Description |
|-------|-------------|
| `bootstrap`         | Initialize a project (see [Bootstrap](#bootstrap) below) |
| `pr`                | Create a pull request linked to `hq:plan` and `hq:task` |
| `code-review`       | Code review criteria — readability, correctness, performance, security |
| `security-scan`     | Security scan criteria — credentials, external comms, dynamic code |
| `integrity-check`   | End-to-end integrity criteria — downstream references, scope boundary |
| `xcodebuild-config` | Interactive xcodebuild configuration |
| `e2e-web`           | End-to-end web verification via Playwright CLI |
| `worktree-setup`    | Create a new git worktree with local-file setup |
| `worktree-rebase`   | Sync worktree base branch with upstream and rebase |

### Agents (autonomous execution)

| Agent | Description |
|-------|-------------|
| `code-reviewer`           | Reads `code-review` skill criteria; outputs report + FB files to `.hq/tasks/` |
| `security-scanner`        | Reads `security-scan` skill criteria (Sonnet); outputs report to `.hq/tasks/` |
| `integrity-checker`       | Reconciles `hq:plan` `## Editable surface` + `## Plan` against the diff (external grep: `[削除]` residuals, unmatched consumers) |
| `review-comment-analyzer` | Read-only classification of PR review comments — Fix / Feedback / Dismiss |

`/hq:start` splits review into **Phase 6 (Self-Review)** — the orchestrator's pre-Quality-Review self-assessment across 3 axes (Plan alignment / Out-of-scope impact / Tunnel vision) — and **Phase 7 (Quality Review)** — pure review with **judgment-mode agent selection** by default (the orchestrator picks the agent subset as a third-party senior engineer; `full` mode applies the Diff Classification matrix as a fallback). Phase 7 FBs flow directly to `## Known Issues` without auto-fix.

## Issue Labels

| Label | Role | Description |
|-------|------|-------------|
| `hq:task`     | Requirement (trigger)      | **What** needs to be done. Created by the user; consumed by `/hq:draft`. |
| `hq:plan`     | Implementation plan        | **How** to do it. Created by `/hq:draft` as a sub-issue of `hq:task`. Drives `/hq:start`. |
| `hq:pr`       | PR marker                  | Applied automatically by `/hq:start` on PR creation. |
| `hq:feedback` | Unresolved problem         | Carved out by `/hq:triage` (PR Known Issues) or `/hq:respond` (external comments). |
| `hq:doc`      | Informational note         | Research findings worth preserving. Created manually. |
| `hq:wip`      | Drafting / automation gate | Issue is being drafted; automation skips, manual commands pause and confirm. |

**Issue hierarchy:**

```
Milestone (optional)
  └── hq:task  — requirement
        └── hq:plan  — implementation plan (sub-issue of hq:task)
              ├── ← Closes → PR (hq:pr)
              └── hq:feedback(s)  — residual problems
```

Prerequisite: `gh` CLI authenticated (`gh auth status`).

## Bootstrap

Run `/hq:bootstrap` once when initializing a new project. Pass `agents.md` as argument to also install `AGENTS.md`. Idempotent — safe to re-run.

| Target | Action | Note |
|--------|--------|------|
| `CLAUDE.md` | Create if missing | Filled from template with project info |
| `AGENTS.md` | Create if missing | **Only when `agents.md` argument is given** |
| `.claude/settings.local.json` | Deep-merge | Adds template keys + auto-detected platform permissions |
| `.gitignore` | Append if missing | Adds `**/*.local.*` and `.hq/` |

**Platform detection** for permissions:

| Project type | Permissions added |
|--------------|-------------------|
| Xcode (`*.xcodeproj` / `*.xcworkspace`) | `swift-format`, `xcodebuild`, `xcrun` |
| TypeScript (`package.json` / `tsconfig.json`) | `bun` |
| Go (`go.mod`) | `go build`, `go vet` |

## Design Philosophy

The plugin is designed to **leave no trace in the target repository**:

- **Committed** (only when missing): `CLAUDE.md`, `AGENTS.md` (opt-in), `.gitignore` entries (`**/*.local.*`, `.hq/`).
- **Never committed** (gitignored): `.claude/settings.local.json`, `.hq/` (tasks, feedbacks, reports).

The workflow rule itself lives at `plugin/v2/rules/workflow.md` inside the plugin and is loaded on demand by each `/hq:*` command. Nothing is copied into the consumer project — editing that one file is the change.

Per-project guidance can be layered via `.hq/<command>.md` overrides (e.g. `.hq/draft.md`, `.hq/start.md`). Overrides **augment**, never **replace**, the workflow contract.

## Repository Layout

| Path | Role |
|------|------|
| `.claude-plugin/plugin.json` | Plugin manifest |
| `plugin/v2/` | Active plugin — commands, agents, skills, rules, scripts, docs |
| `plugin/v1/` | Legacy — frozen, do not modify |
| `CLAUDE.md` | Project instructions for Claude Code |
| `AGENTS.md` | Pointer to `CLAUDE.md` for OpenAI Codex |

## Companion

The HQ CLI / TUI dashboard (Go binary that reads a Markdown `db/` directory for tasks, notes, milestones, and monthly logs) was split out to a sibling repo: [tom-e-kid/hqdb](https://github.com/tom-e-kid/hqdb). It is independent of this plugin — install it separately if you want the cross-project dashboard.
