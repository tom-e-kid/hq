# HQ Workflow

This document is the **orientation map** for the hq workflow — how the commands fit together and where each artifact lives. It deliberately stays at overview altitude: the authoritative specifications live in `plugin/v3/rules/workflow.md` (cross-cutting rules, loaded on demand by each command) and in each command / skill file. When this document and a spec disagree, the spec wins.

## Overview

hq separates a feature from idea to merge into command-scoped operations. **Two user interventions** anchor the flow — everything else is autonomous:

1. **Approve the plan** (at `/hq:draft`'s commit-or-pushback gate) — the fully-composed plan body is presented verbatim in-chat; the user's `go` creates the plan file. The file remains directly editable before `/hq:start`.
2. **Review the PR** (after `/hq:start`) — the user inspects the produced PR and decides the next move (merge, `/hq:triage`, `/hq:respond`, `/hq:archive`).

Core artifacts:

- **`hq:task`** — GitHub Issue (label `hq:task`): the requirement ("what"). Optional trigger.
- **`hq:plan`** — local file `.hq/tasks/<branch-dir>/plan.md`: the implementation plan ("how"). Created by `/hq:draft`, identified by its branch name, executed by `/hq:start`. Durable via the PR body's `## Implementation Plan` snapshot from PR creation onward.
- **`hq:pr`** — the PR that realizes an `hq:plan`. Labeled `hq:pr`; body carries the workflow sections (`## Manual Verification` / `## Known Issues` / `## Implementation Plan`) and `Refs #<task>` when a parent task exists.
- **`hq:feedback`** — GitHub Issue for residual problems carved out of a PR's Known Issues. Created only by `/hq:triage` (and `/hq:respond` for external review comments).

## Command Map

```
                 (intervention #1)              (intervention #2)
                approve plan body                 review hq:pr
                        ↓                              ↓
 [hq:task] ─/hq:draft─→ plan.md ─/hq:start─→ hq:pr ──┬─ merge ──────────/hq:archive────────→ (tasks/done/)
            (optional)  (.hq/tasks/<dir>/)           ├─ close w/o merge ─/hq:archive cancel→ (tasks/canceled/)
                                                     │
                                                     ├─ /hq:triage   (Known Issues from PR body)
                                                     └─ /hq:respond  (external review comments)
```

- **Creation path**: `/hq:draft` → `/hq:start` → (merge) → `/hq:archive`.
- **Cancel path**: `/hq:archive cancel` closes the PR (if open) and archives the task folder under `.hq/tasks/canceled/`. The plan is a local file — there is no plan Issue to close in either path; the parent `hq:task` is never touched.
- **Response tools** (user-directed, zero or more times, any order): `/hq:triage` for in-PR Known Issues, `/hq:respond` for external review comments.

## Lifecycle

1. **`/hq:draft [hq:task]`** — intake (optional task fetch + wide-impact survey) → interactive brainstorm with the Simplicity gatekeeper → compose the plan body → **commit-or-pushback gate** (`go`) → write `.hq/tasks/<branch-dir>/plan.md` + `context.md`. The branch name is derived here from the plan title; the git branch is NOT created. Spec: `plugin/v3/rules/draft-protocol.md`.
2. **`/hq:start [branch]`** — autonomous: resolve plan (no argument = current branch; otherwise `find-plan.sh` query) → create branch → execute Plan items (one commit each) → Acceptance sweep (Phase 4↔5 mini-loop, capped) → Self-Review → Quality Review (judgment-selected agent subset; pure review, no auto-fix) → PR creation (workflow sections + plan snapshot) → Retrospective → Distillation → report. Spec: `plugin/v3/rules/start-protocol.md`.
3. **Review the PR.** Optionally:
   - **`/hq:triage <PR>`** — per-item strict-interactive triage of `## Known Issues`: (1) add to plan (appends to the local `plan.md`; re-run `/hq:start` to resume), (2) leave, (3) escalate to `hq:feedback` (`Refs #<PR>`), (4) fix in place under a regression gate. Spec: `plugin/v3/rules/triage-protocol.md`.
   - **`/hq:respond`** — autonomously fix / escalate / dismiss external review comments. Spec: `plugin/v3/commands/respond.md`.
4. **Merge**, then **`/hq:archive`** (done mode) — verifies merge + no pending FBs, archives the task folder to `.hq/tasks/done/`, deletes the local branch.

## Where things live

```
.hq/tasks/<branch-dir>/plan.md        # the hq:plan — single source of truth (gitignored)
.hq/tasks/<branch-dir>/context.md     # focus: source (task #), branch, base_branch
.hq/tasks/<branch-dir>/gh/task.json   # hq:task snapshot (only when a parent exists)
.hq/tasks/<branch-dir>/feedbacks/     # pending FB files → moved to done/ at PR creation
.hq/retro/<branch-dir>.md             # per-run retrospective (Phase 9)
.hq/start-memory.md                   # distilled repo learnings (Phase 10 writes, Phase 4/6/7 read)
```

`<branch-dir>` = branch name with `/` → `-`. Everything under `.hq/` is per-clone and gitignored; the plan's durability handoff is the PR body snapshot.

Helper scripts (`plugin/v3/scripts/`): `plan-check-item.sh` (checkbox toggle), `find-plan.sh` (branch lookup), `read-context.sh`, `phase-timing.sh`, `quality-review.sh`.

## Key design decisions (with spec pointers)

- **Plan body contract** — flat 5-section structure (`## Why` / `## Approach` / `## Editable surface` / `## Plan` / `## Acceptance`) + optional `## Manual Verification`; `## Editable surface` is the AI agent fence with inline tags (`[新規]` / `[改修]` / `[削除]` / `[silent-break]`); exactly one `[auto] [primary]` acceptance signal at the strongest start-executable tier. Spec: `hq:workflow § hq:plan`.
- **Local Plan Principle** — the plan file is the single source of truth; no GitHub sync during execution. Spec: `hq:workflow § Local Plan Principle`.
- **Two user interventions only** — the draft gate and PR review. `/hq:start` is autonomous after pre-flight, with a single sanctioned `pause-consult` exception (Phase 6 significant-gap). Spec: `rules/start-protocol.md § Stop Policy`.
- **Pure-review Quality Review** — Phase 7 agents (`code-reviewer` / `security-scanner` / `integrity-checker`) never auto-fix; every FB flows to the PR's `## Known Issues`, grouped by action priority. Fix decisions are human-gated in `/hq:triage`. Spec: `hq:workflow § Feedback Loop`.
- **PR body = 2 layers** — the narrative layer is project-overridable via `.hq/pr.md`; the workflow sections (`## Manual Verification` / `## Known Issues` / `## Implementation Plan` / `Refs` trailer) are English-fixed invariants. Spec: `hq:workflow § PR Body Structure`, `skills/pr/SKILL.md`.
- **Learning loop** — Phase 9 writes the retrospective, Phase 10 distills repo-specific cautions into the char-bounded `.hq/start-memory.md`, which Phase 4 (implementation), Phase 6 (Self-Review), and Phase 7 (Agent Selection) read on the next run. Spec: `hq:workflow § Retrospective`.
- **Project overrides** — every command / skill / agent may consult `.hq/<name>.md` for project-local guidance; overrides augment, Invariants govern. Spec: `hq:workflow § Project Overrides`.
