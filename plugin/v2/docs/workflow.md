# HQ Workflow

This document describes the full hq workflow and how its commands fit together. For the authoritative rule specifications, see `plugin/v2/rules/workflow.md` (loaded on demand by each command).

## Overview

hq separates a feature from idea to merge into five command-scoped operations. **Two user interventions** anchor the flow — everything else is autonomous:

1. **Review `hq:plan` Issue** (after `/hq:draft`) — the user edits / approves the plan before execution.
2. **Review `hq:pr`** (after `/hq:start`) — the user inspects the produced PR and decides the next move (merge, `/hq:triage`, `/hq:respond`, `/hq:archive`).

These two review points are the workflow's center of gravity. Everything downstream of intervention #2 is **user-directed** — the response tools compose freely, not in a fixed sequence.

- **`hq:task`** = trigger (what to build — requirement)
- **`hq:plan`** = center of execution (how to build it — drives execution, verification, PR)
- **`hq:pr`** = the PR that realizes an `hq:plan`. Labeled `hq:pr` by `/hq:start` at creation; body carries `Closes #<plan>` + `Refs #<task>`.

## Command Map

```
                 (intervention #1)   (intervention #2)
                  review hq:plan       review hq:pr
                         ↓                   ↓
 hq:task ─/hq:draft─→ hq:plan ─/hq:start─→ hq:pr ──┬─ merge ─/hq:archive─→
                                                   │
                                                   ├─ /hq:triage   (Known Issues from PR body)
                                                   └─ /hq:respond  (external review comments)
```

- **Creation path** (produces artifacts): `/hq:draft` → `/hq:start` → (merge) → `/hq:archive`.
- **Response tools** (invoked at the user's discretion after intervention #2, zero or more times, in any order): `/hq:triage` for in-PR Known Issues, `/hq:respond` for external review comments.

## Lifecycle Overview

Creation path:

1. **`/hq:draft <hq:task>`** — interactive brainstorm → orchestrator composes plan body inline → creates `hq:plan` Issue as a sub-issue of the `hq:task`.
   → **User intervention #1**: review / edit the `hq:plan` Issue on GitHub UI.
2. **`/hq:start <hq:plan>`** — autonomous: branch → execute → acceptance → quality review → PR (labeled `hq:pr`).
   → **User intervention #2**: review the `hq:pr`, then choose how to proceed.
3. **Merge the `hq:pr`** — GitHub auto-closes `hq:plan` via `Closes #<plan>`.
4. **`/hq:archive`** — safety-checked close-out: requires PR merged + no pending FBs, then archives `.hq/tasks/<branch-dir>/` and deletes the local feature branch.

Response tools (invoked between intervention #2 and merge, at the user's discretion):

- **`/hq:triage <PR>`** — interactive per-item: for each entry in the PR body's `## Known Issues` section, choose (1) add to `hq:plan` for follow-up, (2) leave as-is, or (3) carve out as `hq:feedback`. The **only** place `hq:feedback` Issues are created from the main workflow.
- **`/hq:respond`** — autonomously processes external PR review comments (Copilot, reviewers): fix / escalate as `hq:feedback` / dismiss.

## Commands

### `/hq:draft`

Input: optional `hq:task` Issue number (+ optional supplementary context). When omitted, the plan is created top-level and the requirement is captured in `## Why`.

```
Phase 1: Intake (hq:task + pre-session context + wide-impact survey)
│  Fetch hq:task when provided (verify label, warn on hq:wip)
│  Carry pre-session conversation context forward as brainstorm material
│  Run mandatory wide-impact survey:
│    git log --oneline -- <paths>    → past design decisions / abandoned approaches
│    gh pr list --state merged --search <keyword>  → related merged PRs
│    grep -rn <main symbol>          → impact radius before declaring Editable surface
│  Surface outcomes (including zero-hits) at Phase 2 opening
│
Phase 2: Brainstorm + Simplicity gatekeeper (interactive — user intervention)
│  Exploration-led dialogue; internal checklist tracks required fields
│  Simplicity gate: reuse vs new-build / minimum-solution / spread cost / marker domain judgment
│  Plan-split judgment: coupling test (4+ parallel decisions OR independently-shippable → split)
│  Convergence: Why / Approach / Editable surface entries with inline tags /
│               Plan items with consumer suffixes / primary w/marker committable
│  Exit: commit-or-pushback message (single in-chat commitment line)
│         User endorses "go" → Phase 3, or raises 違和感 → continue brainstorm
│
Phase 3: Compose plan body + consumer coverage check (autonomous)
│  Compose body from Phase 2 conversation state — no further user prompt
│  Pre-emit check: every Plan item's (consumer: <name>) suffix is consistent
│
Phase 4: Create hq:plan Issue
│  gh issue create --label hq:plan
│  Register as sub-issue, inherit milestone + projects (when a parent hq:task exists)
│
Phase 5: Report
   Issue URL → "edit on GitHub, then /hq:start <plan>"
```

**Key decisions**:

- No branch, no code, no cache writes in this command. The only artifact is the `hq:plan` Issue.
- The orchestrator composes the exact `## Why` + `## Approach` + `## Editable surface` + `## Plan` + `## Acceptance` flat 5-section structure inline from Phase 2 conversation state, with exactly one `[auto] [primary]` item in `## Acceptance` (or `[manual] [primary]` under the escape hatch).
- `## Editable surface` IS the single AI agent fence — each entry carries an inline tag (`[新規]` / `[改修]` / `[削除]` / `[silent-break]`) and the complement is implicit out of scope. Stack-natural extensions follow the Boundary expansion protocol (add the entry to `## Editable surface` *before* touching the surface, note the rationale in `## Approach`).
- Downstream coordination lives in `## Plan` items via the `*(consumer: <name>)*` suffix; the consumer coverage check at Phase 3 enforces consistency before the Issue emits.
- Phase 2 is the mitigation checkpoint for `hq:workflow § Simplicity Criterion` — it challenges benefit/complexity tradeoffs before the plan is composed rather than after.
- `## Plan` granularity: each item is a single meaningful commit unit. No numeric cap — motive-driven bloat is challenged by the Phase 2 Simplicity gatekeeper, not by a count ceiling.
- Review surface is the **GitHub Issue** only. The Phase 2 commit-or-pushback message is a one-shot commitment checkpoint, not a Recap review; full plan-body review happens on the Issue after Phase 4.
- The handoff is intentional — user reviews / edits the `hq:plan` Issue before `/hq:start` is invoked.

### `/hq:start`

Input: `hq:plan` Issue number.

```
Phase 1: Pre-flight Check (non-interactive)
│  find-plan-branch.sh <plan>
│  ├─ found existing branch → auto-resume
│  │    (git checkout, cache pull, resume phase by checkbox state)
│  └─ not found → fresh start (proceed to Phase 2)
│
Phase 2: Load Plan (fresh start only)
│  gh issue view <plan> → title, body, milestone, projects
│  Parse Parent: #<task> → fetch hq:task
│  Derive branch name from plan title
│
Phase 3: Execution Prep (fresh start only)
│  git checkout -b <branch> from base
│  Write context.md (plan, source, branch, gh paths)
│  Write task.json cache
│  plan-cache-pull.sh <plan> (→ plan.md)        [Sync: Pull]
│  Save focus to memory
│
Phase 4: Execute
│  Fresh entry: implement each Plan item (§ Before Commit + check + commit)
│  Loopback entry (from Phase 5 fails): diagnose + fix across all failures,
│    `fix: ...` commits, no Plan checkbox changes
│  End (fresh): plan-cache-push.sh <plan>        [Sync: Push]
│
Phase 5: Acceptance (sweep only — no fixing)
│  Run all unchecked [auto] items → pass/fail per item (1-by-1 toggle, batch prohibited)
│  └─ all pass         → push cache, proceed to Phase 6
│  └─ some fail, any item under retry cap
│                      → loopback to Phase 4 with full failure set
│                         (Phase 4 fixes; re-enter Phase 5)
│  └─ cap exhausted    → FB per remaining item (with `covers_acceptance`)
│                         + toggle [x] + push, Phase 6
│  Retry cap = FB retry cap (§ Settings, default 2)
│
Phase 6: Quality Review (pure review — judgment-based agent selection)
│  Step 0: Pre-Quality Self-Review Gate
│    orchestrator self-assesses across 3 axes:
│      (1) Plan alignment   (2) Out-of-scope impact   (3) Tunnel vision check
│    result: pass | minor-gap (FB → Known Issues) | significant-gap (pause-consult)
│    decision report MUST be written; .hq/start-memory.md consulted
│
│  Step 1: Agent Selection
│    mode = judgment (default) | full (matrix fallback)
│    judgment: "third-party senior engineer" picks agent subset to launch
│      hard floor: literal credential prefix → security-scanner forced
│    full: apply Diff Classification matrix deterministically
│      (doc → code-reviewer skip; security-scanner runs on doc too)
│    decision report MUST be written
│
│  Step 2: Initial Review + FB Collection (no fix loop)
│    launch selected agents in parallel
│    integrity-checker prompt carries plan ## Editable surface + ## Plan —
│      NOT ## Why, NOT ## Approach (caller framing kept out of agent's lens)
│    integrity-checker scope = external grep only:
│      [削除] residuals + unmatched consumer external visits
│      (mechanical reconciliation moved to orchestrator Step 0)
│    All FBs (any severity, any origin) flow directly to ## Known Issues
│    No commits, no batch-fix loop, no severity gate — pure review
│    (working tree unchanged across Phase 6)
│
Phase 7: PR Creation
│  Gate: all Plan + Acceptance [auto] checked
│  Assemble PR body:
│    ## Summary / ## Changes / ## Notes
│    ## Manual Verification (unchecked [manual] items)
│    ## Known Issues (unresolved FBs + move to done/)
│    Closes #<plan> / Refs #<task>
│  Final plan-cache-push.sh <plan>               [Sync: Push]
│  gh pr create --label hq:pr (inherit milestone + projects)
│
Phase 8: Retrospective
│  Read feedbacks/done/ + JSONL events + git log + plan cache
│  Write .hq/retro/<branch-dir>/<plan>.md per hq:workflow § Retrospective
│    (## Run Summary / ## FB Analysis / ## Reflection — fixed schema)
│  Per-FB: 3 YAML axes (closed enums) — detection_validity /
│    preventable_at_implementation / prevention_lever — plus Notes
│    Markdown field (free-form ≤ 2 sentences) below the YAML fence
│
Phase 9: Report
   Task, plan, branch, PR URL, [manual] count, Known Issues count
```

**Key decisions**:

- **Plan-centric pre-flight** — the given plan number decides everything. Current branch, current focus, uncommitted changes are irrelevant inputs; let git's own errors surface if checkout fails.
- **Cache-first** — Phases 4–7 touch `.hq/tasks/<branch-dir>/gh/plan.md` only; GitHub is hit at sync checkpoints (after Phase 4 Execute, after Phase 5 Acceptance, and before PR creation).
- **Commit as you go** — each Plan item and fix lands as its own commit. Working tree is clean by Phase 7.
- **Acceptance → Quality Review** — Phase 5 confirms the implementation works first (sweep only, looping back to Phase 4 to fix), Phase 6 then reviews quality on a known-working baseline. Reviewing quality before Acceptance would waste effort on code that may not work.
- **Phase 6 is pure review** — no auto-fix. Every FB from Quality Review (Self-Review Gate Step 0 minor gaps + agent-emitted findings from Step 2) flows directly to the PR's `## Known Issues`, regardless of severity. The prior batch-fix loop / severity gate / per-round retry cap are retired — leaving fix decisions to humans aligns with the Karpathy-loop bounded-scope principle. Phase 6 makes no commits.
- **Pre-Quality Self-Review Gate (Step 0)** — before any agent runs, the orchestrator self-assesses across 3 axes (Plan alignment / Out-of-scope impact / Tunnel vision). Significant gaps surface via the new `pause-consult` Stop Policy (the single permitted exception to "autonomous after Phase 1"); minor gaps become FBs that join the Phase 6 pool. Decision reports under `.hq/tasks/<branch-dir>/reports/`.
- **Agent Selection — `judgment` mode default** — the orchestrator picks the Quality Review agent subset as "a third-party senior engineer reviewing the PR" (framing defuses self-marking bias). `full` mode applies the Diff Classification matrix deterministically as a fallback. Hard floor: literal credential-prefix patterns force `security-scanner`. `.hq/start-memory.md` (per-clone, gitignored) accumulates user corrections about prior Self-Review Gate and Agent Selection calls to tighten future judgments.
- **Three-agent set with non-overlapping scopes** — `code-reviewer` covers quality / correctness / `/simplify`-era signals with a load-bearing guard against redundant-looking concurrency / lifecycle / subscription / cache / SSR / module-level-mutable-state code. `security-scanner` enumerates alert patterns (runs on `sonnet`). `integrity-checker` is narrowed to **external grep**: `[削除]` residual sweep + unmatched-consumer external visits. Mechanical Editable surface ↔ diff set-diff is now orchestrator-side at Phase 6 Step 0 — `integrity-checker`'s invocation prompt still carries plan `## Editable surface` + `## Plan` (NOT `## Why` / `## Approach`) so the agent has the symbols / consumer names it needs to grep.
- **Phase 4 ↔ Phase 5 mini-loop** — Phase 5 is a pure sweep; fixes live in Phase 4 (loopback entry). Capped by § Settings Phase 5 retry cap per item. This batch-fix model surfaces shared root causes across multiple failing items.
- **Phase 5 1-by-1 toggle** — per failing `[auto]` item, write the FB (with `covers_acceptance` pointing back to the item) and toggle the checkbox in a single `plan-check-item.sh` tool call. Batch toggles are prohibited.
- **PR body Known Issues — action-priority grouped** — `## Known Issues` carries a leading `**Triage summary**` line + three category sub-sections: `### Must Address (Critical / High)` / `### Recommended (Medium)` / `### Optional (Low)`, with each entry tagged `[<Severity>] [<originating-agent>]` so the reviewer triages at a glance. Empty categories are omitted.
- **PR body is the source of truth for residual problems** — every FB flows into `## Known Issues` and the local FB files move to `feedbacks/done/` atomically at PR creation. `/hq:triage` then handles dispositions per category.
- **No `hq:feedback` creation** — escalation to `hq:feedback` is a `/hq:triage` responsibility, not `/hq:start`.
- **Strict PR creation gate** — all `## Plan` items and all `[auto]` Acceptance items must be checked. `[manual]` items carry over to the PR body for the user to verify.

### `/hq:triage`

Input: PR number.

```
Phase 1: Load PR
│  gh pr view (state, body, Closes #<plan>, Refs #<task>)
│
Phase 2: Parse Known Issues
│  Extract ## Known Issues section
│  List bullets (one triage item each)
│
Phase 3: Triage (interactive)
│  For each item, ask user:
│    (1) add to hq:plan
│    (2) leave as-is
│    (3) escalate to hq:feedback
│  (collect decisions; no writes yet)
│
Phase 4: Apply (batch)
│  (1) append to hq:plan cache + plan-cache-push.sh
│  (3) gh issue create --label hq:feedback (inherit projects from hq:task, NOT milestone)
│  Edit PR body to reflect dispositions (single gh pr edit call)
│
Phase 5: Report
   counts per disposition + next-step hint
```

**Key decisions**:

- **Only creator of `hq:feedback` Issues** in the workflow. All other commands route residual issues through the PR body.
- **Batch edits** — collect all per-item decisions interactively, then apply them in a single PR body edit.
- **hq:plan updates go through cache sync** — never `gh issue edit <plan>` directly.

### `/hq:archive`

Input: none (operates on the current branch's task folder).

```
Phase 1: Resolve focus
│  Read .hq/tasks/<branch-dir>/context.md (current branch)
│  (missing → ABORT)
│
Phase 2: Pre-check PR
│  gh pr list --head <branch> --state all
│  MERGED → proceed
│  OPEN / CLOSED / missing → ABORT with reason
│
Phase 3: Pre-check FBs
│  Any pending files in feedbacks/ (not done/)?
│  yes → ABORT with list
│  no  → proceed
│
Phase 4: Archive
│  mv .hq/tasks/<branch-dir> → .hq/tasks/done/<branch-dir>[-timestamp]
│
Phase 5: Branch cleanup
│  git checkout <base>
│  git branch -d <feature>  (fallback -D on squash-merge)
│
Phase 6: Memory
│  Clear focus entry
│
Phase 7: Report
```

**Key decisions**:

- **No interactive confirmation** when pre-checks pass — archive and cleanup run unconditionally. If pre-checks fail, report what remains and stop; the user resolves manually.
- **Never pushes / force-pushes** — all operations are local.
- **No `hq:feedback` escalation** — pending FBs should never exist at archive time in a normal `/hq:start` flow; the check is defensive.

### `/hq:respond`

Input: none (operates on the current branch's PR).

```
Phase 1: Preconditions
│  PR exists? open?
│
Phase 2: Fetch
│  gh api → line-level review comments
│  Filter: top-level + no reply from PR author
│  (nothing unaddressed → done)
│
Phase 3: Deep Analysis (parallel per comment)
│  ┌─────────────────────────────────────────────┐
│  │  review-comment-analyzer (per comment)       │
│  │  Read code → assess → classify               │
│  │  → self-validate → structured result         │
│  └──┬──────────────┬──────────────┬─────────────┘
│   Fix          Feedback       Dismiss
│
Phase 4: Execute
│  Fix (sequential): edit → format → build → test → commit → push → reply w/ SHA
│  Feedback (parallel): gh issue create --label hq:feedback → reply w/ link
│  Dismiss (parallel): reply with evidence-based reasoning
│
Phase 5: Report
```

**Key decisions**:

- **Fully autonomous** — no user approval gates. Every decision is self-validated with evidence.
- **Orthogonal to the main axis** — invoked ad-hoc whenever external reviewers leave comments; does not advance the `/hq:draft → start → triage → archive` pipeline.
- **Conservative on Fix** — escalates to `hq:feedback` when uncertain about safety; a tracked issue is better than a broken build.

## Shared Concepts

### Plan Structure

Every `hq:plan` Issue body follows a **flat 5-section structure**:

```markdown
Parent: #<hq:task issue number>

## Why
<1-3 sentences: pain and why now>

## Approach
<chosen design + at least one rejected alternative with reason. Optional: Mermaid / ASCII figure, or sample code ≤10 lines.>

## Editable surface
- `<file / symbol>` — `[新規]` <≤1行 note: what happens here>
- `<file / symbol>` — `[改修]` <≤1行 note>
- `<file / symbol>` — `[削除]` <≤1行 note>
- `<file / symbol>` — `[silent-break]` <≤1行 note: signature stable, semantics shift>

## Plan
- [ ] <implementation step — single meaningful commit unit> *(consumer: <name>)*

## Acceptance
- [ ] [auto] [primary] <single concrete pass/fail signal>
- [ ] [auto] <secondary verifiable check>
- [ ] [manual] <requires user verification>
```

Highlights:

- **`## Why`** — pain + why now. Anti-content (file:line citations, error code dumps, design judgment, comparison of alternatives) belongs in `## Approach`.
- **`## Approach`** — chosen design + ≥1 rejected alternative with reason. Optional figure (Mermaid / ASCII) and sample code (≤10 lines, intent-conveying only) when structure-conveying. **plan-split signal**: 4+ parallel independent decisions, or ≤3 decisions that could be released independently, means the plan should split.
- **`## Editable surface`** — the single positive set, and **the AI agent fence**. Each entry has an inline tag (`[新規]` / `[改修]` / `[削除]` / `[silent-break]`) and a ≤1行 note. The complement is implicit out of scope; the `integrity-checker` flags any diff touching a surface absent from this list. **Boundary expansion protocol**: when implementation reveals a stack-natural extension (e.g., Swift Concurrency async propagation, co-located test file), add the entry *before* touching the surface and note the rationale in `## Approach`.
- **`## Plan`** — implementation steps. Each item is a single meaningful commit unit; adjacent edits to the same file collapse into one item. No numeric cap. `*(consumer: <name>)*` suffix is appended when the step performs a coordinated update on a named downstream consumer; the consumer coverage check at `/hq:draft` Phase 3 enforces consistency. All items must be checked before PR creation.
- **`## Acceptance`** — completion criteria tagged by execution mode and role:
  - `[auto]` — Claude executes and toggles (unit tests, API calls, file checks, Playwright). Prefer `[auto]`.
  - `[manual]` — flows to PR body for user verification.
  - `[primary]` — role marker; combines with `[auto]` only by default. Exactly one `[auto] [primary]` per plan, designating the single pass/fail signal that tells the plan succeeded. All other `[auto]` items are secondary. The `[manual] [primary]` escape hatch is permitted only under strict conditions (`hq:workflow § ## Acceptance § #### [manual] [primary] escape hatch`).

See `hq:workflow § ## hq:plan` for the authoritative schema, anti-content rules per section, volume bounds, and the `[primary]` / granularity rules.

### Naming Conventions (Conventional Commits)

- `hq:task` title: `<type>: <requirement>`
- `hq:plan` title: `<type>(plan): <implementation approach>`
- PR title: `<type>: <implementation>` (plan title minus `(plan)`)
- Branch: `<type>/<short-description>`

Recognized `<type>`: `feat`, `fix`, `docs`, `refactor`, `chore`, `test`.

### Cache-First + Sync Checkpoints

Cache files under `.hq/tasks/<branch-dir>/gh/` (branch-dir = branch name with `/` → `-`):

- `task.json` — read-only snapshot of `hq:task`
- `plan.md` — read/write working copy of `hq:plan` body

| Direction | When | Purpose |
|---|---|---|
| Pull | `/hq:start` begin | Initialize / refresh cache |
| Push | End of `/hq:start` Phase 4 | Plan checkbox updates |
| Push | End of `/hq:start` Phase 5 | Acceptance `[auto]` updates |
| Push | Before PR creation | Final consistency |

Helper scripts under `${CLAUDE_PLUGIN_ROOT}/plugin/v2/scripts/`:

- `plan-cache-pull.sh <plan>` — atomic pull to `plan.md`
- `plan-cache-push.sh <plan>` — push `plan.md` via `gh issue edit --body-file`
- `plan-check-item.sh <pattern>` — toggle `[ ]` → `[x]` in cache (cache only; exit 3 no match, exit 4 ambiguous, idempotent on already-checked)
- `find-plan-branch.sh <plan>` — scan `.hq/tasks/*/context.md` for a `plan: <N>` match, print the `branch:` field

**Rule**: during `/hq:start`, never call `gh issue edit <plan>` directly. Cache edits use `plan-check-item.sh`; sync uses `plan-cache-push.sh`.

### FB Lifecycle

Feedback files are branch-internal artifacts in `.hq/tasks/<branch-dir>/feedbacks/`:

```
feedbacks/              # pending
feedbacks/done/         # resolved in-branch OR escalated to PR body
feedbacks/screenshots/  # evidence (optional)
```

An FB moves to `done/` when:

1. **Escalated to PR body** — at `/hq:start` Phase 7 PR creation, every pending FB is written into `## Known Issues` (under the appropriate action-priority category) and its file is moved to `done/` atomically. This is the single path to `done/` under the post-refactor pure-review Phase 6.

Local `feedbacks/` should be empty of pending files after PR creation. `/hq:archive` defensively checks this.

Escalation to `hq:feedback` Issues happens only through `/hq:triage` during PR review, or through `/hq:respond` for external review comments.

### PR Body Structure

```markdown
## Summary
<1-3 sentences explaining what and why>

## Changes
<bullet list>

## Notes
<optional>

## Manual Verification
<unchecked [manual] Acceptance items, verbatim>

## Known Issues
**Triage summary**: N must address, M recommended, K optional. Process via `/hq:triage <PR>`.

### Must Address (Critical / High)
- [<Severity>] [<originating-agent>] <title> — <brief description>

### Recommended (Medium)
- [<Severity>] [<originating-agent>] <title> — <brief description>

### Optional (Low)
- [<Severity>] [<originating-agent>] <title> — <brief description>

---
Closes #<hq:plan>
Refs #<hq:task>
```

Omit optional sections (`## Notes`, `## Manual Verification`, `## Known Issues`) when empty. `Closes` is mandatory. `Refs` is mandatory **only when the plan has a parent `hq:task`** — when no parent exists, omit the `Refs` line entirely.

### Project Overrides

Every hq command / skill / agent may consult a project-local override file under `.hq/` (e.g. `.hq/draft.md`, `.hq/start.md`, `.hq/triage.md`, `.hq/respond.md`, `.hq/pr.md`, `.hq/code-review.md`, `.hq/security-scan.md`, `.hq/integrity-check.md`, `.hq/xcodebuild-config.md`). Override content is free-form guidance that augments the consumer's default behavior; it cannot replace phases, gates, or other Invariants the consumer defines for itself.

`.hq/` is gitignored by `hq:bootstrap` Task 4, so overrides are per-clone by default. Teams that want shared policy either un-ignore specific files and commit them, or upstream the policy into `plugin/v2/rules/workflow.md`. The latter is the canonical path.

See `hq:workflow § Project Overrides` for the authoritative table of override files, scope rules, and worktree propagation behavior.
