# HQ

A development hub for AI-assisted workflows across multiple projects.

Each project runs Claude Code with the HQ plugin (dev skills & commands), while a shared data store and CLI dashboard provide cross-project visibility. Codex can also act as a reviewer via AGENTS.md. All data is plain Markdown with YAML frontmatter.

![HQ Concept](docs/hq-concept.png)

## Components

### plugin/ — Claude Code Plugin

A Claude Code plugin that provides skills and commands for AI-assisted development workflows. Two versions coexist under `plugin/v1/` and `plugin/v2/`.

#### v2 (active)

Skills, agents, and commands architecture. Skills define pure analysis criteria, agents handle autonomous workflow execution, commands provide user-invoked workflow shortcuts. Core design principle: **GitHub Issue-based traceability** — all work is tracked through GitHub Issues and PRs, with `.hq/tasks/<branch-dir>/context.md` as the branch-local pointer to the active plan.

**Workflow commands** form a five-step pipeline from requirement to closure. See [plugin/v2/docs/workflow.md](plugin/v2/docs/workflow.md) for the full flow and shared concepts.

**Skills** (analysis criteria — invoked via `/skill-name`):

| Skill              | Description                                                                    |
| ------------------ | ------------------------------------------------------------------------------ |
| `bootstrap`        | Initialize a project (see [Bootstrap](#bootstrap-bootstrap) below)             |
| `pr`               | Create a pull request linked to `hq:plan` and `hq:task` issues                |
| `code-review`      | Code review criteria — readability, correctness, performance, security         |
| `security-scan`    | Security scan criteria — credentials, external comms, dynamic code, etc.       |
| `integrity-check`  | End-to-end integrity criteria — downstream references, scope boundary, feature completeness |
| `xcodebuild-config`| Interactive xcodebuild configuration (project, scheme, device, OS)             |
| `e2e-web`          | End-to-end web verification via Playwright CLI                                 |
| `worktree-setup`   | Create a new git worktree with local file setup (.env, .claude, .hq configs)   |
| `worktree-rebase`  | Sync worktree base branch with upstream and rebase working branch              |

**Agents** (autonomous execution — launched via Agent tool):

| Agent                      | Description                                                                    |
| -------------------------- | ------------------------------------------------------------------------------ |
| `code-reviewer`            | Autonomous code review — reads `code-review` skill criteria, outputs report + FB files to `.hq/tasks/` |
| `security-scanner`         | Autonomous security scan — reads `security-scan` skill criteria, outputs report to `.hq/tasks/` (Sonnet model — Haiku silently no-opped on non-trivial diffs) |
| `integrity-checker`        | Reconciles the `hq:plan` `## Context` (especially `**Impact**`) against the diff — detects declared-but-missing and diff-but-undeclared misses. Outputs report + FB files to `.hq/tasks/` |
| `review-comment-analyzer`  | Read-only analysis of a single PR review comment — classifies as Fix/Feedback/Dismiss with evidence. Launched in parallel by `/hq:respond` |

Agents read skill files at runtime for analysis criteria, then handle workflow integration (focus resolution, file output, traceability) independently. They can run **in parallel** and in the **background**.

`/hq:start` Phase 6 (Quality Review) is **diff-kind aware**: `code-reviewer` and `integrity-checker` always run; `security-scanner` skips on doc-only diffs (credential / injection patterns structurally cannot appear there). See [plugin/v2/docs/workflow.md](plugin/v2/docs/workflow.md#hqstart) for the agent launch matrix.

**Commands** (user-invoked workflow shortcuts — invoked via `/hq:command-name`):

| Command            | Description                                                                    |
| ------------------ | ------------------------------------------------------------------------------ |
| `draft`            | Interactive brainstorm → create an `hq:plan` Issue from an `hq:task`                             |
| `start`            | Autonomous: branch → execute → acceptance → quality review → PR from an `hq:plan`                |
| `triage`           | Triage PR body `## Known Issues` — add to plan / leave / escalate to `hq:feedback`    |
| `archive`          | Safely close a merged PR's branch — verify + archive task folder + delete local branch           |
| `respond`          | Respond to external PR review comments (Copilot, reviewers) — fix / escalate / dismiss           |
| `swift-protocol-shadow` | Detect protocol default implementation shadowing in Swift ([flow](plugin/v2/docs/swift-protocol-shadow-flow.md)) |

**Traceability**

All work is tracked through GitHub Issues and PRs. The plugin uses six labels:

| Label | Role | Description |
|-------|------|-------------|
| `hq:task` | Requirement (trigger) | **What** needs to be done. Created by the user; consumed by `/hq:draft`. |
| `hq:plan` | Implementation plan (workflow center) | **How** to do it. Created by `/hq:draft` as a sub-issue of `hq:task`. Drives `/hq:start` execution. |
| `hq:feedback` | Unresolved problem | Carved out from a PR's Known Issues during `/hq:triage`, or from external review comments via `/hq:respond`. |
| `hq:doc` | Informational note | Research findings worth preserving that are not a direct task. Created manually. |
| `hq:pr` | PR marker | Applied automatically by `/hq:start` on PR creation. Marks PRs that belong to this workflow. |
| `hq:wip` | Automation gate / drafting marker | Issue is being drafted; automated `/hq:draft` or `/hq:start` triggers must skip it. In manual use, commands pause and confirm. |

**Issue hierarchy:**

```
Milestone (optional grouping)
  └── hq:task  — requirement
        └── hq:plan  — implementation plan (sub-issue of hq:task)
              ├── ← Closes → PR
              └── hq:feedback(s)  — residual problems (via /hq:triage or /hq:respond, Refs #plan)
```

**How it works:**

1. Create an `hq:task` Issue describing the requirement (e.g., `feat: add user authentication`)
2. Run `/hq:draft <hq:task>` — interactive brainstorm (enumerates `Impact on existing features` in 3 sub-dimensions) → the `hq:plan` Issue is created (sub-issue of `hq:task`) with `## Plan` + `## Acceptance` structure
3. Review / edit the `hq:plan` Issue on GitHub UI (intervention point #1)
4. Run `/hq:start <hq:plan>` — autonomous: branch → execute → acceptance → quality review → PR
5. Review the PR (intervention point #2). Use `/hq:respond` to handle external review comments, `/hq:triage <PR>` to process the PR body's `## Known Issues` section
6. After merge, run `/hq:archive` to clean up the local branch and task folder

**`hq:plan` Issue body structure (required):**

```markdown
Parent: #<hq:task issue number>

## Plan
- [ ] <implementation step 1>
- [ ] <implementation step 2>

## Acceptance
- [ ] [auto] <self-verifiable check — e.g., `pnpm test` passes>
- [ ] [auto] <e.g., `/api/auth/login` returns 200>
- [ ] [manual] <requires user verification — e.g., browser UI check>
```

- `## Plan` — implementation steps. All must be checked before PR creation.
- `## Acceptance` — completion criteria. `[auto]` items are executed by `/hq:start`; `[manual]` items flow to the PR body for user verification.

**Naming conventions (Conventional Commits):**

- `hq:task` title: `<type>: <requirement>`
- `hq:plan` title: `<type>(plan): <implementation approach>`
- PR title: `<type>: <implementation>` (plan title minus `(plan)`)

**Prerequisites:** `gh` CLI must be authenticated (`gh auth status`).

**Key differences from v1:**

- Skills define criteria, agents handle workflow execution, commands provide workflow shortcuts
- GitHub Issue-based traceability replaces local-file-based tracking
- Code review produces FB files instead of direct code modifications
- Per-project overrides via `.hq/<skill>.md` files
- Separate `security-scan` skill (was part of `reviewer` in v1)
- `code-reviewer`, `security-scanner`, and `integrity-checker` agents enable parallel, diff-kind-aware verification

#### Design Philosophy

The plugin is designed to **leave no trace in the target repository**. All plugin-generated files use the `.local.*` naming convention and are gitignored, so the repository stays clean. Running `/bootstrap` restores the full environment at any time.

**Committed to the repo** (exceptions — only if missing):
- `CLAUDE.md` — project overview (created once, then owned by the user)
- `AGENTS.md` — agent instructions (only when explicitly requested via argument)
- `.gitignore` entries — `**/*.local.*` and `.hq/` (one-time append)

**Never committed** (gitignored via `**/*.local.*` or `.hq/`):
- `.claude/settings.local.json` — permissions and attribution config
- `.hq/` — working directory for tasks, feedbacks, and reports

The workflow rule itself lives at `plugin/v2/rules/workflow.md` inside the plugin and is loaded on demand by each `/hq:*` command. Nothing is copied into the consumer project.

#### Bootstrap (`/bootstrap`)

Run once when initializing a new project. Pass `agents.md` as argument to also install AGENTS.md. Safe to re-run — idempotent for committed files, always updates local files to latest.

| Target | Action | Note |
|--------|--------|------|
| `CLAUDE.md` | Create if missing | Fill template with project info |
| `AGENTS.md` | Create if missing | **Only when `agents.md` argument is given** |
| `.claude/settings.local.json` | Deep-merge | Add missing keys from template + auto-detected platform permissions |
| `.gitignore` | Append if missing | Adds `**/*.local.*` and `.hq/` entries |

> **Migration note**: earlier versions of `/hq:bootstrap` also installed a project-local copy of the workflow rule under `.claude/rules/`. The rule now lives at `plugin/v2/rules/workflow.md` inside the plugin and is loaded on demand by each `/hq:*` command, so re-running `/hq:bootstrap` no longer touches the consumer's `.claude/rules/`. If your project has an existing copy under `.claude/rules/` from a prior bootstrap, it is now stale and can be deleted manually — `/hq:*` commands ignore it.

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
