# HQ

A Claude Code plugin for AI-assisted development workflows, anchored in GitHub Issues and PRs.

HQ runs a feature from idea to merge through a single pipeline command — **`/hq:loop`**. The model running it (the **root agent**) orchestrates the stages and makes the pipeline's semantic judgments (J1–J8, each with a written decision record); subagents gather evidence and execute. The human's attention is reserved for three checkpoints: approving the plan, answering rare consults, and confirming which residual findings become Issues. The PR is created **last**, after triage — it is the final proposal, written for the human reviewer.

## Pipeline

```
/hq:loop <input>                          root agent = orchestrator + judge
│
├─ Stage 0 RESUME   (root, J1)   artifacts → entry stage (plan? built? triaged? shipped?)
├─ Stage 1 PLAN     (root+user)  survey → brainstorm (J2) → go/stop gate → plan.md   ← user ①
├─ Stage 2 BUILD    (executor)   branch → implement plan items → acceptance sweep
├─ Stage 3 REVIEW   (root+agents) J3 build review → J4 selection → reviewers in parallel → FBs
├─ Stage 4 TRIAGE   (root)       J5 per-FB disposition → J8 convergence at exit:
│                                  converged → micro-fix + integrity re-check + spot-check record → Stage 5
│                                  continue  → Stage 2 (budget-bounded)
│                                  diverging → plan-revision consult / safe cancel   ← user ②
├─ Stage 5 SHIP     (root, J6)   PR = final proposal (narrative body via pr skill)
├─ Stage 6 RETRO    (distiller)  retrospective + start-memory distillation
└─ Stage 7 REPORT   (root+user)  judgment audit trail + feedback confirmation (J7)  ← user ③

Post-PR tools: /hq:copilot / /hq:copilot-loop (external review comments) · /hq:archive (done / cancel)
```

- **`hq:task`** (GitHub Issue, optional) = trigger — what to build.
- **`hq:plan`** (local file `.hq/tasks/<branch-dir>/plan.md`) = how to build it — the loop's internal work log. Never embedded in the PR; its motivation / approach reach the reviewer through the PR narrative.
- **`hq:pr`** = the PR that ships a plan: narrative (Summary / Approach incl. build-time deviations / Changes) + `## Manual Verification` + post-triage `## Known Issues` + `Refs #<task>`.

For the orientation map see [plugin/v3/docs/workflow.md](plugin/v3/docs/workflow.md) and the visual flow at [plugin/v3/docs/hq-loop-flow.html](plugin/v3/docs/hq-loop-flow.html). Authoritative specs: [plugin/v3/commands/loop.md](plugin/v3/commands/loop.md) (stages + judgments) and [plugin/v3/rules/](plugin/v3/rules/) (cross-cutting rules + stage protocols).

## Components

### Commands (`/hq:<name>`)

| Command  | Description |
|----------|-------------|
| `loop`    | The pipeline — plan → build → review → triage → ship → retro, orchestrated by the root agent |
| `copilot` | Respond to external PR review comments in one pass — fix / escalate / dismiss |
| `copilot-loop` | Iterate `copilot` over Copilot re-review rounds — respond → push → re-request Copilot → wait → repeat (bounded by `max_rounds`, default 5) |
| `archive` | Safely close the current branch — **done** (PR merged → `tasks/done/`) or **cancel** (`archive cancel`: closes PR without merging → `tasks/canceled/`) |
| `swift-protocol-shadow` | Detect protocol default implementation shadowing in Swift ([flow](plugin/v3/docs/swift-protocol-shadow-flow.md)) |

### Stage protocols (`plugin/v3/rules/`)

| Protocol | Consumed by | Description |
|----------|-------------|-------------|
| `draft-protocol.md`   | loop Stage 1 (root, inline) | Intake + wide-impact survey → exploration-led brainstorm with the Simplicity gatekeeper → commit-or-pushback gate (`go` / `stop`) → plan file |
| `execute-protocol.md` | `executor` agent | Branch → one commit per plan item → acceptance sweep (retry-capped); modes `fresh` / `fix-directive`; returns results + `self_notes` |
| `copilot-protocol.md` | `/hq:copilot`, `/hq:copilot-loop` | One round over external PR review threads — fetch → analyze → judge → execute → reply; plus the Escalation Gate and Round Result contract |
| `workflow.md`         | everything | Cross-cutting source of truth — terminology, plan body schema, FB lifecycle, PR body structure, retrospective schema |

### Skills (criteria & utilities)

| Skill | Description |
|-------|-------------|
| `bootstrap`         | Initialize a project (see [Bootstrap](#bootstrap) below) |
| `pr`                | Create the pull request — reviewer-focused narrative + workflow sections |
| `code-review`       | Code review criteria — readability, correctness, performance, security |
| `security-scan`     | Security scan criteria — credentials, external comms, dynamic code |
| `integrity-check`   | External integrity criteria — `[削除]` residuals, unmatched consumers, scope boundary |
| `xcodebuild-config` | Interactive xcodebuild configuration |
| `e2e-web`           | End-to-end web verification via Playwright CLI |
| `worktree-setup`    | Create a new git worktree with local-file setup |
| `worktree-rebase`   | Sync worktree base branch with upstream and rebase |

### Agents (autonomous execution — never final judges)

| Agent | Model | Description |
|-------|-------|-------------|
| `executor`                | inherit | Runs the execute protocol: implement + verify. Build only — no review, no PR, no retro |
| `code-reviewer`           | inherit | Pure review; outputs FB files to `.hq/tasks/` |
| `security-scanner`        | sonnet  | Pure detection; outputs a scan report |
| `integrity-checker`       | inherit | External grep — `[削除]` residuals + unmatched consumers; also re-runs scoped to the J8 micro-fix diff |
| `retro-distiller`         | sonnet  | Writes the retrospective (incl. hindsight on the root's judgments) and re-distills `.hq/start-memory.md` |
| `review-comment-analyzer` | sonnet  | Read-only analysis of PR review threads — returns evidence + recommendation; the copilot protocol root judges the disposition |

### Root-agent judgments (J1–J8)

Semantic decisions the root agent makes, each with a decision record under `.hq/tasks/<branch-dir>/reports/`: **J1** ambiguous-state entry · **J2** design gates during the brainstorm · **J3** build acceptance review (plan alignment / out-of-scope / tunnel vision — structurally third-party, the executor wrote the code) · **J4** reviewer selection (credential hard-floor stays deterministic) · **J5** per-FB triage disposition (fix / plan / accept / escalate-candidate) · **J6** PR narrative · **J7** report composition · **J8** convergence (converged / continue / diverging — the real loop control; `loop_max_iterations` is only a runaway backstop).

## Issue Labels

| Label | Role | Description |
|-------|------|-------------|
| `hq:task`     | Requirement (trigger)      | **What** needs to be done. Created by the user; consumed by loop Stage 1. Optional. |
| `hq:pr`       | PR marker                  | Applied automatically at PR creation (Stage 5). |
| `hq:manual`   | Reviewer verification      | Applied alongside `hq:pr` when the plan has `## Manual Verification` items — the reviewer completes them before merge. |
| `hq:feedback` | Escalated residual         | Created only with explicit user confirmation — loop Stage 7, or `/hq:copilot` / `/hq:copilot-loop`. |
| `hq:doc`      | Informational note         | Research findings worth preserving. Created manually. |
| `hq:wip`      | Drafting / automation gate | The `hq:task` is still being drafted; automation skips, interactive runs pause and confirm. |

**Hierarchy:**

```
Milestone (optional)
  └── hq:task Issue — requirement
        └── hq:plan file — .hq/tasks/<branch-dir>/plan.md (local, gitignored)
              └── PR (hq:pr; Refs #task; final proposal — created after triage)
                    └── hq:feedback Issue(s) — user-confirmed escalations (Refs #PR)
```

Prerequisite: `gh` CLI authenticated (`gh auth status`).

## Bootstrap

Run `/hq:bootstrap` once when initializing a new project. The skill **never silently skips or overwrites** — every change is confirmed with the user before applying. Safe to re-run; the HQ-managed block in `CLAUDE.md` is the only piece that bootstrap owns end-to-end, and even there a one-line diff summary is surfaced before write.

**Interactive build / test config** — the skill detects the project type (`*.xcodeproj` / `Package.swift` / `package.json` / `go.mod`) and proposes the matching install / dev / build / test / lint / format commands. The user then picks a **test strategy** — who runs verification and where checks route: Executor-run tests (the executor runs the test command autonomously as `[auto]` acceptance) / E2E via `hq:e2e-web` (browser outcomes verified `[auto]` with Playwright) / Reviewer-deferred (deterministic checks route to the PR's `## Manual Verification`) — which is recorded into the HQ block and seeded into `.hq/draft.md` as planning priors.

| Target | What bootstrap does |
|--------|---------------------|
| `CLAUDE.md` | Create from template if missing. If present with `<!-- BEGIN HQ --> ... <!-- END HQ -->` markers, refresh only that block; the rest is user territory. If present without markers, ask before appending. |
| `.claude/settings.local.json` | Add `attribution: { commit: "", pr: "" }` (suppresses the default commit / PR footer). Existing values are never overwritten. |
| `.gitignore` | Append `.hq/` (the HQ working directory — plan, task context, FBs, decision records, retro) if missing. |
| `.hq/draft.md` | Seed draft-protocol priors from the chosen test strategy (primary-tier preference, `## Manual Verification` routing). Per-clone (gitignored); if the file exists, a diff summary is shown and overwrite is confirmed. |
| `.hq/xcodebuild-config.md` *(Xcode projects only)* | Delegated to the `hq:xcodebuild-config` skill — interactively captures Build / Run commands. |

## Design Philosophy

- **Root agent as judge** — decisions that cannot be settled deterministically are made by the strongest model in the loop, with recorded rationale, instead of being forced into mechanical rules or delegated to smaller agents. Deterministic rails (scripts, structural gates, the regression gate) stay deterministic.
- **PR-last** — review and triage happen before the PR exists, so the PR's `## Known Issues` carries only what was deliberately accepted or escalated. Nothing is "to be processed later".
- **Human-gated where it matters** — the plan approval, plan revisions after divergence, and `hq:feedback` Issue creation always pass through the user.
- **Leave no trace** — committed to the consumer repo only when missing: `CLAUDE.md` (bootstrap block) and the `.gitignore` entry. Everything else lives under the gitignored `.hq/` (plan, context, FBs, reports, retro, start-memory). The workflow specs live inside the plugin; nothing is copied out — editing the spec files is the change.
- **Closed learning loop** — every run ends with a retrospective (written by a different party than the judge) distilled into a char-capped `.hq/start-memory.md`, read by the next run's build and judgments.
- **Dual-write telemetry** — human-readable records stay in the project `.hq/`; structured run events (gates, judgments, dispositions, J8 verdicts, timings) are additionally appended to the central `~/.hq/events.jsonl` for cross-project analytics. Non-blocking: telemetry never gates the pipeline.

Per-project guidance can be layered via `.hq/<name>.md` overrides (e.g. `.hq/draft.md`, `.hq/start.md`, `.hq/loop.md`, `.hq/pr.md`). Overrides **augment**, never **replace**, the workflow contract.

## Repository Layout

| Path | Role |
|------|------|
| `.claude-plugin/plugin.json` | Plugin manifest |
| `plugin/v3/` | Active plugin — commands, agents, skills, rules, scripts, docs |
| `plugin/v2/` | Legacy — frozen, do not modify |
| `plugin/v1/` | Legacy — frozen, do not modify |
| `CLAUDE.md` | Project instructions for Claude Code |
| `AGENTS.md` | Pointer to `CLAUDE.md` for OpenAI Codex |

## Companion

The HQ CLI / TUI dashboard (Go binary that reads a Markdown `db/` directory for tasks, notes, milestones, and monthly logs) was split out to a sibling repo: [tom-e-kid/hqdb](https://github.com/tom-e-kid/hqdb). It is independent of this plugin — install it separately if you want the cross-project dashboard.
