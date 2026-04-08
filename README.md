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
| `start`            | Full workflow — plan, execute, verify, and PR from an `hq:task`                |
| `review-triage`    | Triage and respond to PR review comments autonomously (see [flow](#review-triage-flow) below) |
| `swift-protocol-shadow` | Detect protocol default implementation shadowing in Swift (see [flow](#swift-protocol-shadow-flow) below) |

#### Start Flow

`/start` runs the complete hq workflow — from planning through PR creation — for a given `hq:task` issue.

```
Phase 1: Check Current State
│  Active work? (focus exists / feature branch with changes)
│  → Continue existing task → skip to Phase 5
│  → Interrupt → commit/stash, optionally /archive, switch to base
│  → No active work → proceed
│
Phase 2: Input Source
│  $ARGUMENTS → parse issue number + supplementary context
│  (no argument → ask user)
│
Phase 3: Planning (mandatory — no code before approval)
│  ┌─ 3a: Brainstorming ────────────────────────┐
│  │  Review hq:task, discuss with user,          │
│  │  investigate codebase, align on scope        │
│  └─────────────────────────────────────────────┘
│  ┌─ 3b: Plan Generation ──────────────────────┐
│  │  Launch Plan subagent → structured plan      │
│  │  (steps, gates, verification items)          │
│  └─────────────────────────────────────────────┘
│  ┌─ 3c: Review & Approval ────────────────────┐
│  │  Present plan → user feedback → wait for     │
│  │  explicit approval before proceeding         │
│  └─────────────────────────────────────────────┘
│
Phase 4: Execution Prep
│  Create hq:plan issue (sub-issue of hq:task)
│  Create work branch
│  Set focus (focus.md + .hq/tasks/<branch>/context.md)
│  Read workflow rules
│
Phase 5: Execute
│  Work through plan step by step
│  Format & build after each unit
│  Check off hq:plan checklist items
│
Phase 6: Simplify
│  /simplify → review full changeset
│  Format & build
│
Phase 7: Verification (parallel)
│  ┌────────────────────────────────────────────┐
│  │  code-reviewer    ║    security-scanner     │
│  │  (background)     ║    (background)         │
│  └──────────┬────────╨────────┬───────────────┘
│             ▼                 ▼
│  Fix FB issues (max 2 rounds)
│  E2E verification (if applicable)
│
Phase 8: PR Creation
│  Check unresolved FBs → escalate to hq:feedback?
│  /pr → create pull request
│
Phase 9: Report
   Task, plan, branch, changes, verification, PR link
```

Key design decisions:
- **Planning is mandatory** — no production code before user-approved plan. Brainstorming is interactive and takes as many turns as needed.
- **GitHub Issue traceability** — `hq:plan` is a sub-issue of `hq:task`. PR uses `Closes #plan` + `Refs #task`.
- **Parallel verification** — `code-reviewer` and `security-scanner` agents run simultaneously in the background.
- **Simplify before verify** — Phase 6 catches cross-cutting improvements (deduplication, unnecessary abstractions) that per-step reviews miss.
- **Resumable** — if active work is detected, the user can continue from Phase 5 without re-planning.

#### Review-Triage Flow

`/review-triage` checks the current PR for unaddressed review comments (Copilot, human reviewers, etc.), analyzes each one, and autonomously takes the appropriate action.

```
Phase 1: Preconditions
│  PR exists? open?
│
Phase 2: Fetch
│  gh api → line-level review comments
│  Filter: top-level & no reply from PR author
│  (no unaddressed comments → done)
│
Phase 3: Deep Analysis (parallel)
│  ┌─────────────────────────────────────────────┐
│  │  review-comment-analyzer (per comment)       │
│  │  Read code → assess validity → classify      │
│  │  → self-validate → return structured result  │
│  └──┬──────────────┬──────────────┬─────────────┘
│     │              │              │
│   Fix          Feedback       Dismiss
│
Phase 4: Execute
│  ┌─ Fix (sequential) ──────────────────────────┐
│  │  Edit code → format → build → test           │
│  │  (no tests? → code-level verification)       │
│  │  Commit → push → reply with SHA              │
│  └──────────────────────────────────────────────┘
│  ┌─ Feedback + Dismiss (parallel) ─────────────┐
│  │  Feedback: create hq:feedback issue → reply  │
│  │  Dismiss: reply with evidence-based reason   │
│  └──────────────────────────────────────────────┘
│
Phase 5: Report
   Summary: Fix count + SHAs, Feedback issues, Dismiss count
```

Key design decisions:
- **Fully autonomous** — no user approval gates. All decisions are self-validated with evidence. The user reviews the results in the PR itself.
- **Conservative on Fix** — when uncertain about safety, escalates to `hq:feedback` rather than risking a regression.
- **Regression gate** — Fix changes must pass format, build, and test before commit. When no tests exist, code-level verification is documented in the commit message.
- **Evidence-based replies** — every reply (Fix, Feedback, Dismiss) cites specific code references, commits, or documentation.

#### Swift-Protocol-Shadow Flow

`/swift-protocol-shadow <directory>` statically analyzes Swift source code to detect **protocol default implementation shadowing** — where a conforming type's method has a subtly different signature from the protocol default, causing the default to silently win at runtime.

```
Step 0: Initialization
│  Clean .hq/protocol-shadow/
│  Create protocols/, conformances/, findings/
│
Step 1: Protocol Collection (Collector Agents — parallel)
│  ┌─────────────────────────────────────────────┐
│  │  Scan Swift files for protocol declarations  │
│  │  Extract requirements + default impls        │
│  │  Write protocols/<ProtocolName>.md           │
│  │  (only protocols with default impls)         │
│  └─────────────────────────────────────────────┘
│
Step 2-3: Conforming Type Discovery + Comparison (Analyzer Agents — parallel, max 3)
│  ┌─────────────────────────────────────────────┐
│  │  One agent per protocol                      │
│  │  Find all conforming types (direct,          │
│  │    inherited, extension)                     │
│  │  Compare signatures against defaults         │
│  │  → conformances/<Protocol>.md                │
│  │  → findings/<NNN>.md (mismatches only)       │
│  └─────────────────────────────────────────────┘
│
Step 4: Self-Review (Reviewer Agent)
│  ┌─────────────────────────────────────────────┐
│  │  Coverage: grep count vs collected count     │
│  │  Findings verification: read actual files    │
│  │  Spot checks: verify "no mismatch" types     │
│  │  Inheritance chain: parent protocol defaults  │
│  │  → review.md                                 │
│  └─────────────────────────────────────────────┘
│
Step 5: Final Report
   Compile findings + review → report.md
   Report to user
```

Key design decisions:
- **Fully autonomous** — no user confirmation between steps. Runs all 6 steps end-to-end and reports the final result. Only asks the user if the directory argument is missing.
- **Heuristic analysis** — text-based static analysis without the compiler. False positives/negatives are possible and noted in the report.
- **Multi-agent pipeline** — Collector → Analyzer → Reviewer stages with parallelism within each stage (max 3 concurrent agents).
- **Self-review** — a dedicated Reviewer Agent verifies coverage, validates findings against actual source, and performs spot checks to catch missed detections.
- **Signature-exact comparison** — `@MainActor`, `@Sendable`, `@escaping`, `Optional` differences are all checked. `typealias` expansions are resolved before comparison.
- **Swift 6 migration focus** — particularly targets shadowing introduced by `@MainActor @Sendable` annotation changes.

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

Command-driven workflow with orchestration layer. Do not modify.

The `/hq:dev` command acts as an orchestration layer, composing independent skills:

```
/hq:dev [platform]              ← command (orchestration)
    ├── dev-core/SKILL.md       ← always loaded (branch management, planning, commit conventions)
    └── dev-<platform>/SKILL.md ← loaded by platform detection or argument
```

- **Command** (`dev.md`): Explicitly reads both skills via the Read tool and delegates to the dev-core workflow
- **dev-core**: Platform-agnostic workflow. Does not assume any platform skill exists (works standalone)
- **dev-\<platform\>**: Platform-specific setup and build rules. Does not reference dev-core

No direct references exist between skills — adding or removing a platform skill only requires updating the detection table in the command.

**Skills:**

| Skill      | Description                                                                           |
| ---------- | ------------------------------------------------------------------------------------- |
| `dev-core` | Platform-agnostic development workflow — branch management, task tracking, conventions |
| `dev-ios`  | iOS/Xcode build, run, and environment configuration                                   |
| `reviewer` | Code review standards — review criteria, security alerts, reporting format            |
| `ops`      | HQ operations — TODO and notes CRUD via `hq` CLI                                      |

**Commands:**

| Command             | Description                                                                       |
| ------------------- | --------------------------------------------------------------------------------- |
| `/hq:dev`           | Start development (loads dev-core + platform skill)                               |
| `/hq:pr`            | Create or update a GitHub Pull Request                                            |
| `/hq:code-review`   | Review code changes on the current branch (includes security alert scan)          |
| `/hq:accept-review` | Evaluate code review results, commit accepted fixes, and extract follow-up issues |
| `/hq:estimate`      | Collect requirements and organize work item estimates with risks and blockers     |
| `/hq:close`         | Archive task files to `.hq/tasks/done/` and clean up branches                    |

### tools/ — HQ CLI

A Go-based CLI and TUI dashboard. See [tools/README.md](tools/README.md) for details.

### AGENTS.md — Codex Reviewer Demo

`AGENTS.md` is a demo configuration for using [OpenAI Codex](https://openai.com/index/openai-codex/) as an automated code reviewer. It inlines review criteria and policies so that it works standalone in any project. The canonical source for review standards is `plugin/skills/reviewer/SKILL.md`; AGENTS.md is kept in sync manually.
