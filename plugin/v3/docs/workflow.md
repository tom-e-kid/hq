# HQ Workflow

This document is the **orientation map** for the hq workflow — how the pipeline fits together and where each artifact lives. It deliberately stays at overview altitude: the authoritative specifications live in `plugin/v3/commands/loop.md` (the orchestrator + judgments), `plugin/v3/rules/` (cross-cutting rules + stage protocols), and each skill / agent file. When this document and a spec disagree, the spec wins.

## Overview

**`/hq:loop`** is the single entry point. The model running it — the **root agent** — orchestrates the pipeline and makes its semantic judgments (J1–J8, each with a written decision record); subagents gather evidence and execute. The design premise: the root agent out-judges a typical human developer on these calls, so the human's attention is reserved for three interaction systems:

1. **The Stage 1 gate** — the fully-composed plan body is presented verbatim; `go` continues, `stop` saves the plan and ends, pushback re-converges.
2. **Root-initiated consults** (rare) — J3 finds a gap outside the plan's scope; J8 detects divergence and proposes a plan revision (or safe-cancels on decline).
3. **The Stage 7 feedback confirmation** — `hq:feedback` Issues are created only from user-selected candidates.

The PR is created **last** (Stage 5), after triage — it is the final proposal, and its body is written for the human reviewer (motivation / approach / changes), not as an agent task-list dump.

Core artifacts:

- **`hq:task`** — GitHub Issue (label `hq:task`): the requirement ("what"). Optional trigger.
- **`hq:plan`** — local file `.hq/tasks/<branch-dir>/plan.md`: the implementation plan ("how"). Created at Stage 1, identified by its branch name. The loop's internal work log — never embedded in the PR; archived with the task folder.
- **`hq:pr`** — the PR that ships a plan. Labeled `hq:pr`; body = narrative + `## Manual Verification` + post-triage `## Known Issues` + `Refs #<task>`.
- **`hq:feedback`** — GitHub Issue for escalated residuals. Created only with explicit user confirmation (loop Stage 7, or `/hq:respond`).

## Pipeline map

```
/hq:loop <input>                          root agent = orchestrator + judge
│
├─ Stage 0 RESUME   (root, J1)   artifacts → entry stage (plan? built? triaged? shipped?)
├─ Stage 1 PLAN     (root+user)  draft-protocol: survey → brainstorm (J2) → go/stop gate → plan.md
├─ Stage 2 BUILD    (executor)   execute-protocol: branch → implement → acceptance sweep
├─ Stage 3 REVIEW   (root+agents) J3 build review → J4 selection → reviewers in parallel → FBs
├─ Stage 4 TRIAGE   (root)       J5 per-FB disposition → J8 convergence at exit:
│                                  converged → micro-fix + integrity re-check → Stage 5
│                                  continue  → Stage 2 (budget-bounded)
│                                  diverging → plan-revision consult / safe cancel
├─ Stage 5 SHIP     (root, J6)   PR = final proposal (pr skill; narrative body)
├─ Stage 6 RETRO    (distiller)  retrospective + start-memory distillation
└─ Stage 7 REPORT   (root+user)  judgment audit trail + feedback confirmation (J7)

Post-PR tools: /hq:respond (external review comments) · /hq:archive (done / cancel)
```

Full stage + judgment spec: `commands/loop.md`. Visual: `docs/hq-loop-flow.html`.

## Where things live

```
.hq/tasks/<branch-dir>/plan.md        # the hq:plan — single source of truth (gitignored)
.hq/tasks/<branch-dir>/context.md     # focus: source (task #), branch, base_branch
.hq/tasks/<branch-dir>/gh/task.json   # hq:task snapshot (only when a parent exists)
.hq/tasks/<branch-dir>/feedbacks/     # pending FBs → done/ with a disposition line at Stage 4
.hq/tasks/<branch-dir>/reports/       # J1–J8 decision records (the root's audit surface)
.hq/retro/<branch-dir>.md             # per-run retrospective (Stage 6)
.hq/start-memory.md                   # distilled repo learnings (Stage 6 writes; Phase 4 + J3/J4/J5 read)
```

`<branch-dir>` = branch name with `/` → `-`. Everything under `.hq/` is per-clone and gitignored.

Helper scripts (`plugin/v3/scripts/`): `plan-check-item.sh` (checkbox toggle), `find-plan.sh` (branch lookup), `read-context.sh`, `phase-timing.sh` (slots 4–10; mapping in `loop.md § Timing slots`), `quality-review.sh` (J3/J4 event records).

Agents (`plugin/v3/agents/`): `executor` (build; model inherit) · `code-reviewer` / `security-scanner` (sonnet) / `integrity-checker` (review) · `retro-distiller` (sonnet) · `review-comment-analyzer` (used by `/hq:respond`).

## Key design decisions (with spec pointers)

- **Root agent as judge** — semantic calls (state interpretation, design gates, build review, reviewer selection, triage dispositions, convergence, PR narrative) are J1–J8, decided by the root with recorded rationale; agents never make final calls. Spec: `commands/loop.md`.
- **Plan body contract** — flat 5-section structure with `## Editable surface` as the AI agent fence and exactly one `[auto] [primary]` acceptance signal at the strongest executor-executable tier. Spec: `hq:workflow § hq:plan`.
- **Local Plan Principle** — plan.md is the single source of truth; no GitHub copy; not embedded in the PR. Spec: `hq:workflow § Local Plan Principle`.
- **PR-last + reviewer-focused body** — triage precedes the PR; `## Known Issues` carries only post-triage residual; the narrative (`.hq/pr.md`-overridable) carries motivation / approach / deviations. Spec: `hq:workflow § PR Body Structure`, `skills/pr/SKILL.md`.
- **Pure-review reviewers + root-owned fixes** — reviewer agents only produce FBs; every fix is a J5 decision executed by the executor's fix-directive mode under the regression gate. Spec: `hq:workflow § Feedback Loop`.
- **J8 convergence over mechanical caps** — the loop re-enters on the root's trajectory judgment; `loop_max_iterations` is only a runaway backstop; divergence blocks with a plan-revision proposal or safe-cancels via the archive-cancel route. Spec: `commands/loop.md § Stage 4`.
- **Learning loop** — Stage 6's retro-distiller (a different party from the judge — hindsight without self-grading) writes the retrospective and re-distills `.hq/start-memory.md`, read by the next run's build and judgments. Spec: `hq:workflow § Retrospective`.
- **Project overrides** — `.hq/<name>.md` files supply project guidance; overrides augment, Invariants govern. Spec: `hq:workflow § Project Overrides`.
