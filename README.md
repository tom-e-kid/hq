# HQ

A development hub for AI-assisted workflows across multiple projects.

Each project runs Claude Code with the HQ plugin (dev skills & commands), while a shared data store and CLI dashboard provide cross-project visibility. Codex can also act as a reviewer via AGENTS.md. All data is plain Markdown with YAML frontmatter.

![HQ Concept](docs/hq-concept.png)

## Components

### plugin/ — Claude Code Plugin

A Claude Code plugin that provides skills and commands for AI-assisted development workflows. Two versions coexist under `plugin/v1/` and `plugin/v2/`.

#### v2 (active)

Skills, agents, and commands architecture. Skills define pure analysis criteria, agents handle autonomous workflow execution, commands provide user-invoked workflow shortcuts. Core design principle: **GitHub Issue-based traceability** — all work is tracked through GitHub Issues and PRs, with `focus.md` in Claude Code memory as a local pointer to the active plan.

**Skills** (analysis criteria — invoked via `/skill-name`):

| Skill              | Description                                                                    |
| ------------------ | ------------------------------------------------------------------------------ |
| `bootstrap`        | Initialize a project (see [Bootstrap](#bootstrap-bootstrap) below)             |
| `pr`               | Create a pull request linked to `hq:plan` and `hq:task` issues                |
| `code-review`      | Code review criteria — readability, correctness, performance, security         |
| `security-scan`    | Security scan criteria — credentials, external comms, dynamic code, etc.       |
| `archive`          | Archive task artifacts, close `hq:plan`, escalate unresolved FB to `hq:feedback` |
| `xcodebuild-config`| Interactive xcodebuild configuration (project, scheme, device, OS)             |
| `e2e-web`          | End-to-end web verification via Playwright CLI                                 |
| `worktree-setup`   | Create a new git worktree with local file setup (.env, .claude, .hq configs)   |
| `worktree-rebase`  | Sync worktree base branch with upstream and rebase working branch              |

**Agents** (autonomous execution — launched via Agent tool):

| Agent                      | Description                                                                    |
| -------------------------- | ------------------------------------------------------------------------------ |
| `code-reviewer`            | Autonomous code review — reads `code-review` skill criteria, outputs report + FB files to `.hq/tasks/` |
| `security-scanner`         | Autonomous security scan — reads `security-scan` skill criteria, outputs report to `.hq/tasks/` |
| `review-comment-analyzer`  | Read-only analysis of a single PR review comment — classifies as Fix/Feedback/Dismiss with evidence. Launched in parallel by `/review-triage` |

Agents read skill files at runtime for analysis criteria, then handle workflow integration (focus resolution, file output, traceability) independently. Both agents can run **in parallel** and in the **background**.

**Commands** (user-invoked workflow shortcuts — invoked via `/hq:command-name`):

| Command            | Description                                                                    |
| ------------------ | ------------------------------------------------------------------------------ |
| `start`            | Full workflow — plan, execute, verify, and PR from an `hq:task` ([flow](plugin/v2/docs/start-flow.md)) |
| `review-triage`    | Triage and respond to PR review comments autonomously ([flow](plugin/v2/docs/review-triage-flow.md)) |
| `swift-protocol-shadow` | Detect protocol default implementation shadowing in Swift ([flow](plugin/v2/docs/swift-protocol-shadow-flow.md)) |

**Traceability**

All work is tracked through GitHub Issues and PRs. The plugin uses three issue types as semi-proper nouns:

| Label | Role | Description |
|-------|------|-------------|
| `hq:task` | Requirement | **What** needs to be done. Contains the task checklist, notes, and references. |
| `hq:plan` | Implementation plan | **How** to do it. Created per branch/PR. One `hq:task` can have multiple `hq:plan` issues. |
| `hq:feedback` | Unresolved problem | Issues found during code review or E2E that couldn't be fixed in the current branch. |
| `hq:wip` | Work in progress | Issue is still being drafted or adjusted. Commands pause and confirm before proceeding. |

**Issue hierarchy:**

```
Milestone (optional grouping)
  └── hq:task  — requirement
        └── hq:plan  — implementation plan (sub-issue of hq:task)
              ├── ← Closes → PR
              └── hq:feedback(s)  — unresolved problems (standalone, Refs #plan)
```

**How it works:**

1. Create an `hq:task` issue describing the requirement
2. Create an `hq:plan` issue with the implementation plan, then register it as a **sub-issue** of the parent `hq:task` (GitHub sub-issues API)
3. Work on a feature branch. `focus.md` in Claude Code memory points to the active `hq:plan` issue number
4. PR uses `Closes #<hq:plan>` (auto-closes on merge) and `Refs #<hq:task>` (cross-reference)
5. Unresolved review findings can be escalated to `hq:feedback` issues (standalone issues with `Refs #<plan>` for traceability)

**Recommended `hq:plan` issue body structure:**

```markdown
Parent: #<hq:task issue number>

## Plan
<implementation steps>

## Gates
- [ ] Completion criteria (shown as progress bar in GitHub UI)

## Verification
- [ ] E2E test items (parsed by the e2e-web skill)
```

**Prerequisites:** `gh` CLI must be authenticated (`gh auth status`).

**Key differences from v1:**

- Skills define criteria, agents handle workflow execution, commands provide workflow shortcuts
- GitHub Issue-based traceability replaces local-file-based tracking
- Code review produces FB files instead of direct code modifications
- Per-project overrides via `.hq/<skill>.md` files
- Separate `security-scan` skill (was part of `reviewer` in v1)
- `code-reviewer` and `security-scanner` agents enable parallel verification

#### Design Philosophy

The plugin is designed to **leave no trace in the target repository**. All plugin-generated files use the `.local.*` naming convention and are gitignored, so the repository stays clean. Running `/bootstrap` restores the full environment at any time.

**Committed to the repo** (exceptions — only if missing):
- `CLAUDE.md` — project overview (created once, then owned by the user)
- `AGENTS.md` — agent instructions (only when explicitly requested via argument)
- `.gitignore` entries — `**/*.local.*` and `.hq/` (one-time append)

**Never committed** (gitignored via `**/*.local.*` or `.hq/`):
- `.claude/settings.local.json` — permissions and attribution config
- `.claude/rules/workflow.local.md` — workflow rules (auto-loaded by Claude Code as a rule, but not tracked in git)
- `.hq/` — working directory for tasks, feedbacks, and reports

#### Bootstrap (`/bootstrap`)

Run once when initializing a new project. Pass `agents.md` as argument to also install AGENTS.md. Safe to re-run — idempotent for committed files, always updates local files to latest.

| Target | Action | Note |
|--------|--------|------|
| `CLAUDE.md` | Create if missing | Fill template with project info |
| `AGENTS.md` | Create if missing | **Only when `agents.md` argument is given** |
| `.claude/settings.local.json` | Deep-merge | Add missing keys from template + auto-detected platform permissions |
| `.claude/rules/workflow.local.md` | Always overwrite | Template is source of truth — updates expected |
| `.gitignore` | Append if missing | Adds `**/*.local.*` and `.hq/` entries |

**Platform detection for settings.local.json:**

| Project type | Permissions added |
|-------------|-------------------|
| Xcode (`*.xcodeproj` / `*.xcworkspace`) | `swift-format`, `xcodebuild`, `xcrun` |
| TypeScript (`package.json` / `tsconfig.json`) | `bun` |
| Go (`go.mod`) | `go build`, `go vet` |

#### v1 (legacy — frozen)

See [plugin/v1/README.md](plugin/v1/README.md). Do not modify.

### tools/ — HQ CLI

A Go-based CLI and TUI dashboard. See [tools/README.md](tools/README.md) for details.

### AGENTS.md — Codex Reviewer Demo

`AGENTS.md` is a demo configuration for using [OpenAI Codex](https://openai.com/index/openai-codex/) as an automated code reviewer. It inlines review criteria and policies so that it works standalone in any project. The canonical source for review standards is `plugin/skills/reviewer/SKILL.md`; AGENTS.md is kept in sync manually.
