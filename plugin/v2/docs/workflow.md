# HQ Workflow

This document describes the full hq workflow and how its commands fit together. For the authoritative rule specifications, see `.claude/rules/workflow.local.md` (auto-loaded as project context).

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

1. **`/hq:draft <hq:task>`** — interactive brainstorm → Plan agent → creates `hq:plan` Issue as a sub-issue of the `hq:task`.
   → **User intervention #1**: review / edit the `hq:plan` Issue on GitHub UI.
2. **`/hq:start <hq:plan>`** — autonomous: branch → execute → simplify → verify → PR (labeled `hq:pr`).
   → **User intervention #2**: review the `hq:pr`, then choose how to proceed.
3. **Merge the `hq:pr`** — GitHub auto-closes `hq:plan` via `Closes #<plan>`.
4. **`/hq:archive`** — safety-checked close-out: requires PR merged + no pending FBs, then archives `.hq/tasks/<branch-dir>/` and deletes the local feature branch.

Response tools (invoked between intervention #2 and merge, at the user's discretion):

- **`/hq:triage <PR>`** — interactive per-item: for each entry in the PR body's `## Known Issues` section, choose (1) add to `hq:plan` for follow-up, (2) leave as-is, or (3) carve out as `hq:feedback`. The **only** place `hq:feedback` Issues are created from the main workflow.
- **`/hq:respond`** — autonomously processes external PR review comments (Copilot, reviewers): fix / escalate as `hq:feedback` / dismiss.

## Commands

### `/hq:draft`

Input: `hq:task` Issue number (+ optional supplementary context).

```
Phase 1: Load hq:task
│  Fetch issue (verify hq:task label, warn on hq:wip)
│
Phase 2: Brainstorm (interactive — user intervention)
│  Review task, investigate code, align scope
│  Identify [auto] vs [manual] Acceptance opportunities
│  (wait for user "go")
│
Phase 3: Plan Generation (autonomous)
│  Launch Plan agent → Plan + Acceptance structure
│
Phase 4: Create hq:plan Issue
│  gh issue create --label hq:plan
│  Register as sub-issue of hq:task
│  Inherit milestone + projects from hq:task
│
Phase 5: Report
   Issue URL → "edit on GitHub, then /hq:start <plan>"
```

**Key decisions**:

- No branch, no code, no cache writes in this command. The only artifact is the `hq:plan` Issue.
- Plan agent must produce the exact `## Plan` + `## Acceptance` structure, with `[auto]` / `[manual]` markers on every Acceptance item.
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
│  For each unchecked Plan item:
│    implement → format + build → plan-check-item.sh (cache) → commit
│  End: plan-cache-push.sh <plan>                [Sync: Push]
│
Phase 5: Acceptance
│  Execute [auto] Acceptance items (incl. /hq:e2e-web)
│  Fix failures (max 2 rounds) → fix commits
│  Toggle checkboxes in cache on pass
│  End: plan-cache-push.sh <plan>                [Sync: Push]
│
Phase 6: Simplify
│  /simplify → format + build → single commit (if changed)
│
Phase 7: Quality Review
│  ┌────────────────────────────────────────────┐
│  │  code-reviewer    ║    security-scanner    │
│  └──────────┬────────╨────────┬───────────────┘
│             ▼                 ▼
│  Fix FB (max 2 rounds) → per-FB fix commits
│  (working tree must be clean at end)
│
Phase 8: Round 2 Drafting (Round 1 only, conditional)
│  pending FBs > 0 ?
│    ├─ yes → draft ## Round 2 on cache
│    │        (Follow-ups + Plan (Round 2) + Acceptance (Round 2))
│    │        → plan-cache-push → re-enter Phase 4 as Round 2
│    └─ no  → skip to Phase 9
│
Phase 9: PR Creation
│  Gate: all Plan + Acceptance [auto] checked
│  Assemble PR body:
│    ## Summary / ## Changes / ## Notes
│    ## Manual Verification (unchecked [manual] items)
│    ## Known Issues (unresolved FBs + move to done/)
│    Closes #<plan> / Refs #<task>
│  Final plan-cache-push.sh <plan>               [Sync: Push]
│  gh pr create --label hq:pr (inherit milestone + projects)
│
Phase 10: Report
   Task, plan, branch, PR URL, [manual] count, Known Issues count
```

**Key decisions**:

- **Plan-centric pre-flight** — the given plan number decides everything. Current branch, current focus, uncommitted changes are irrelevant inputs; let git's own errors surface if checkout fails.
- **Cache-first** — Phases 4–8 touch `.hq/tasks/<branch-dir>/gh/plan.md` only; GitHub is hit at sync checkpoints (after Phase 4 Execute, after Phase 5 Acceptance, after Phase 8 Round 2 Drafting if drafted, and before PR creation).
- **Commit as you go** — each Plan item, simplify, and fix lands as its own commit. Working tree is clean by Phase 9.
- **Acceptance → Simplify → Quality Review** — Phase 5 confirms the implementation works first, Phase 6 then refactors a known-working baseline, Phase 7 reviews code quality on the simplified diff. Simplifying before Acceptance would tangle refactor with functional fixes; reviewing quality before Acceptance would waste effort on code that may not work.
- **Round 2 retry, capped** — if Phase 7 leaves pending FBs, Phase 8 appends `## Round 2` (Follow-ups + Plan + Acceptance) to the plan and re-enters Phases 4–7 once. No Round 3; residuals escalate to the PR's `## Known Issues`.
- **PR body is the source of truth for residual problems** — unresolved FBs flow into `## Known Issues` and the local FB files move to `feedbacks/done/` atomically.
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

Every `hq:plan` Issue body MUST follow:

```markdown
Parent: #<hq:task issue number>

## Plan
- [ ] <implementation step>
- [ ] ...

## Acceptance
- [ ] [auto] <self-verifiable check>
- [ ] [auto] <another>
- [ ] [manual] <requires user verification>
```

- `## Plan` — implementation steps. All must be checked before PR creation.
- `## Acceptance` — completion criteria tagged by execution mode:
  - `[auto]` — Claude executes and toggles (unit tests, API calls, file checks). Prefer `[auto]`.
  - `[manual]` — flows to PR body for user verification.

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
| Push | End of `/hq:start` Phase 8 (if Round 2 drafted) | `## Round 2` section |
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

1. **Resolved in-branch** — fix committed, originating skill re-run clean.
2. **Escalated to PR body** — at `/hq:start` Phase 9 PR creation, unresolved FBs are written into `## Known Issues` and the files are moved to `done/` atomically.

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
<unresolved FBs: title + brief description>

---
Closes #<hq:plan>
Refs #<hq:task>
```

Omit optional sections (`## Notes`, `## Manual Verification`, `## Known Issues`) when empty. `Closes` and `Refs` are mandatory.
