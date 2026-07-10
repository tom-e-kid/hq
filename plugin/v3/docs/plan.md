# Implementation Plan: `hq:loop` Orchestrator + Plan Localization + Command Refactoring

Status: **Phases 1–3 and Phase 5 implemented and merged to develop (2026-07-04). Phase 5 (§ 11) supersedes D2/D4 and parts of the Phase 3 architecture — §§ 1–7 describe superseded intermediate states and are kept as history. Phase 4 remains an evaluation gate awaiting ≥ 3 real `/hq:loop` runs. Phase 6 (§ 12, telemetry sink) is implemented and merged (2026-07-04).**
Author context: composed 2026-07-04 from a design session with the repository owner. All user decisions below are final unless explicitly re-opened.

This document is written to be self-sufficient: an AI implementer (Opus / Sonnet class) should be able to execute each phase from this document plus the referenced source files, without access to the original design conversation.

---

## 1. Goal

Today the user manually drives `/hq:draft` → `/hq:start` → `/hq:triage` in sequence, and almost always accepts triage's per-item Suggestions. Introduce **`/hq:loop`** — a single orchestrator command that runs the whole pipeline on the user's behalf:

1. **Draft** from the user's input (hq:task Issue number or free text) → interactive brainstorm → present composed plan → user says `go`.
2. **Execute** the plan (the `/hq:start` workflow) autonomously.
3. **Triage** the resulting PR's Known Issues **automatically** (apply Suggestions without per-item confirmation); if follow-up work was added to the plan, loop back to step 2 — bounded by an iteration cap so steps 2–3 cannot loop forever.
4. **Report**: work summary + the list of triage findings recommended for `hq:feedback` escalation; the user confirms which become `hq:feedback` Issues (Issue creation is the only user-gated step at the end).

Along the way:

- **Localize `hq:plan`**: retire the `hq:plan` GitHub Issue. The plan becomes a local file; the PR body carries a snapshot for review and durability.
- **Refactor `draft` / `start` / `triage`**: remove duplication, contradictions, and stale text; restructure so the same protocol text serves both the standalone commands and the loop's subagents.
- **Per-role model assignment**: run autonomous stages as subagents so each role can carry its own `model:` frontmatter.

## 2. Fixed decisions (do not re-litigate)

Decisions made by the repository owner in the design session:

| # | Decision | Choice |
|---|---|---|
| D1 | `hq:plan` storage | **Local file only** — retire the `hq:plan` GitHub Issue. Plan lives at `.hq/tasks/<branch-dir>/plan.md`; the PR body embeds a plan snapshot at PR creation for reviewability/durability. Applies to standalone `/hq:draft` too, not just loop. |
| D2 | Triage interactivity inside loop | **Fully automatic** — inside `/hq:loop`, triage applies its own Suggestions with no per-item confirmation and reports after the fact. Exception: `hq:feedback` Issue creation is never automatic — candidates are collected and confirmed by the user in the final report. Standalone `/hq:triage` keeps its strict per-item interactive contract unchanged. |
| D3 | Command name | **`hq:loop`** (not `hq:orchestrate`). |
| D4 | Standalone commands | **Keep** `/hq:draft`, `/hq:start`, `/hq:triage` as standalone entry points. `/hq:loop` composes them; it does not replace them. |

Platform facts verified against official Claude Code docs (code.claude.com/docs — sub-agents, skills pages), 2026-07:

| # | Fact | Design consequence |
|---|---|---|
| P1 | Subagents **cannot** use `AskUserQuestion` or pause for user input; they run autonomously and return a final report. | All interactive stages (draft brainstorm, `go` gate, final feedback confirmation) MUST live in the main conversation (`/hq:loop` command itself). Autonomous stages (execute, auto-triage) MAY be subagents. |
| P2 | Agent definitions support `model:` frontmatter (`sonnet` / `opus` / `haiku` / `fable` / full model ID / `inherit`, default `inherit`). | Per-role model assignment is achieved by making roles subagents. |
| P3 | The agent `.md` body becomes the subagent's **system prompt**; the caller's Agent-tool `prompt` is the runtime task. Subagents do not receive the main conversation's history. | Agent bodies must instruct the agent to Read the protocol file(s) it needs; the orchestrator passes run-specific parameters (branch-dir, iteration number, budget) in the prompt. |
| P4 | Subagent nesting is allowed to depth 5. | loop (main) → executor agent (depth 1) → quality-review agents (depth 2) is fine. |
| P5 | Whether a skill/command can invoke another skill via the Skill tool mid-execution is **not clearly documented**. | Do NOT build the loop on nested Skill invocation. Reuse is achieved by **Read-and-follow**: protocol text lives in `rules/*.md` files; commands and agents Read those files and execute them. `!`-prefixed context-injection lines in command files do not execute for an agent Reading the file — protocols must therefore express context acquisition as explicit executable steps, not `!` preamble. |

## 3. Target architecture

```
/hq:loop  (command — main conversation; owns ALL user interaction)
│
├─ Stage 1: DRAFT (inline, interactive)
│    executes rules/draft-protocol.md
│    intake (hq:task or free text) → wide-impact survey → brainstorm +
│    Simplicity gate → compose plan body → commit-or-pushback gate ("go")
│    → writes .hq/tasks/<branch-dir>/plan.md + context.md
│
├─ Stage 2: EXECUTE (subagent: agents/executor.md)
│    executes rules/start-protocol.md in agent mode
│    branch → implement → acceptance → self-review → quality review
│    (nested reviewer agents) → PR (plan snapshot embedded) → retro → distill
│    returns: PR URL, FB summary, timings | or consult-needed (see 6.3)
│
├─ Stage 3: AUTO-TRIAGE (subagent: agents/auto-triager.md)
│    executes rules/triage-protocol.md in auto mode
│    liveness → ordered gate → APPLY dispositions 1/2/4 autonomously
│    disposition 3 (escalate) is NEVER applied — collected as candidates
│    returns: per-item report, feedback candidates, plan-gained-items flag
│
├─ Loop control: if plan gained items AND iteration budget remains → Stage 2
│    (executor auto-resumes: unchecked plan items → re-enter execution)
│
└─ Stage 4: REPORT (inline, interactive)
     work summary across iterations + triage audit trail
     + feedback candidates list → user selects → create hq:feedback Issues
```

Standalone commands after the refactor:

```
commands/draft.md   → thin entry: context + args, then Read rules/draft-protocol.md  (standalone mode)
commands/start.md   → thin entry: context + args, then Read rules/start-protocol.md  (standalone mode)
commands/triage.md  → thin entry: context + args, then Read rules/triage-protocol.md (interactive mode)
commands/loop.md    → the orchestrator above
```

Mode differences are small and explicitly parameterized inside each protocol file (see 6.2). `rules/workflow.md` remains the cross-cutting source of truth (terminology, plan body schema, FB lifecycle, PR body structure).

## 4. Phasing

Four sequential phases, each independently landable as its own branch/PR (dogfood each through the hq workflow itself). Do not start a phase before the previous one is merged.

1. **Phase 1 — Plan localization** (retire the `hq:plan` Issue). Storage foundation everything else builds on.
2. **Phase 2 — Protocol extraction + drift cleanup**. Pure restructuring: move phase specs into `rules/*-protocol.md`, slim commands to entry stubs, fix the enumerated contradictions/stale text. No behavior change.
3. **Phase 3 — `hq:loop` + executor/auto-triager agents**. The new orchestrator.
4. **Phase 4 — Evaluation pass** (model tuning, optional start decomposition). Explicitly deferred decisions with re-evaluation criteria.

---

## 5. Phase 1 — Plan localization

### 5.1 New storage contract

- Plan file: **`.hq/tasks/<branch-dir>/plan.md`** (replaces `gh/plan.md`; the `gh/` subdir keeps only `task.json`). Created by draft Phase 4, **before** the git branch exists — the directory is keyed by branch *name*, which draft now derives itself (move the branch-name derivation rule from `start.md` Phase 2 into the draft protocol: plan title `<type>(plan): <desc>` → branch `<type>/<slugified-desc>`, ≤40 chars kebab-case).
- Plan file format: first line is a `# <type>(plan): <title>` heading (source for PR title derivation), then the existing flat 5-section body (`## Why` / `## Approach` / `## Editable surface` / `## Plan` / `## Acceptance` [+ `## Manual Verification`]) — the body schema in `workflow.md § hq:plan` is **unchanged**. The `Parent: #<task>` line is dropped from the body; parent linkage lives only in `context.md` `source:`.
- `context.md` frontmatter: remove the numeric `plan:` field (the plan is implicit at `<dir>/plan.md`). Keep `source:` (optional), `branch:` (written by draft), `base_branch:` (still written by start at branch creation; absent until then — the existing resolution-chain fallback already tolerates this). `gh.plan` path entry is removed; `gh.task` stays (only when `source:` present).
- Plan identity for command arguments: **the branch name**. `/hq:start` with no argument = current branch's plan; `/hq:start <branch-or-unique-substring>` otherwise.
- Durability: between draft and PR creation the plan exists only in the (gitignored) `.hq/` tree of one clone — accepted risk (owner decision D1). From PR creation onward the PR body snapshot is the durable record.

### 5.2 PR body changes

- **Remove** the `Closes #<plan>` trailer everywhere. `Refs #<task>` (when a parent task exists) remains the only trailer. Merging a PR no longer auto-closes anything; `hq:task` closure stays user-owned as today.
- **Add** a new English-fixed workflow section, injected by start Phase 8 between `## Known Issues` and the trailer:

  ```markdown
  ## Implementation Plan
  <details><summary>Plan snapshot at PR creation</summary>

  <full plan.md content verbatim>

  </details>
  ```

  This is a creation-time snapshot: triage disposition 1 (add to plan) appends to the **local** plan.md only and does not re-edit the snapshot. Document this explicitly in `workflow.md § PR Body Structure`.
- `pr` skill Invariants list: replace the `Closes/Refs` invariant with `Refs`-only + the `## Implementation Plan` section invariant.

### 5.3 File-by-file deltas

All paths relative to `plugin/v3/`. `plugin/v2/` and `plugin/v1/` are frozen — do not touch.

1. **`rules/workflow.md`**
   - `§ Terminology`: `hq:plan` redefined as "the local plan file at `.hq/tasks/<branch-dir>/plan.md`" (no longer an Issue). `hq:wip` scope reduced to `hq:task` Issues. `hq:pr` unchanged.
   - `§ Naming Conventions`: plan title convention stays (it heads the plan file and derives PR title + branch name); note that branch derivation now happens at draft time.
   - `§ Language`: remove `Closes #<plan>` from the fixed-marker list; add `## Implementation Plan` to the English-fixed headings; remove `Parent: #N`.
   - `§ Issue Hierarchy`: redraw without the `hq:plan` Issue node (task → PR via `Refs`; feedback via triage). Delete the `hq:plan` lazy label creation line. Delete sub-issue registration everywhere (`§ Registration` subsection goes away). Milestone/project inheritance: task → PR / feedback only.
   - `§ hq:plan`: body schema, section rules, primary hierarchy, Manual Verification — **all unchanged**. Rewrite only the storage subsections: `§ Registration` deleted; `§ Focus` rewritten for the new `context.md` schema; `§ Focus Resolution` simplified (context.md → memory → branch-name search; the `gh issue list` step goes away).
   - `§ Cache-First Principle` → renamed/rewritten as **`§ Local Plan Principle`**: plan.md is the single source of truth; there are no sync checkpoints and no GitHub round-trips for the plan. Helper-script table updated (see item 8).
   - `§ PR Body Structure`: per 5.2. Update the full-body example and the Invariants list.
   - `§ Feedback Loop`: FB frontmatter references to plan number (see item 9); triage disposition 3 wording: `hq:feedback` body links `Refs #<PR>` instead of `Refs #<plan>`.
   - `§ Retrospective`: the artifact path `.hq/retro/<branch-dir>/<plan>.md` is keyed by the plan **Issue number**, which no longer exists. Change to **`.hq/retro/<branch-dir>.md`** (one plan per branch, so branch-dir alone is a sufficient key; overwrite-on-resume semantics unchanged). Update the same path in start.md Phases 9–10 and any `## Run Summary` field that records "plan id" (record the branch name instead). The Retrospective → Distillation → `start-memory.md` → Phase 4/6/7 learning loop is otherwise **unchanged by this migration** — none of it depends on the plan being an Issue.
2. **`commands/draft.md`**
   - Phase 4 (Create Issue) → **Create plan file**: derive branch name; `mkdir -p .hq/tasks/<branch-dir>`; write `plan.md` (title heading + approved body verbatim); write `context.md` (`source:` when a parent task exists, `branch:`). No `gh issue create`, no sub-issue registration, no milestone/project inheritance (that now happens only at PR creation from `task.json`).
   - Phase 5 (Report): report the plan file path + branch name; next step `/hq:start` (no argument needed if the user stays in this clone).
   - `hq:wip` handling: unchanged (it guards the *task* Issue).
   - The "Do NOT create a feature branch" rule stands — draft creates the task **directory**, start creates the git branch.
3. **`commands/start.md`**
   - Phase 1 (Pre-flight): argument is now optional branch/substring (5.1). Resolution: no arg → current branch; arg → scan `.hq/tasks/*/context.md` `branch:` fields (updated `find-plan-branch.sh`, item 8). Found dir with plan.md → resume-or-fresh decided by checkbox state as today. No `plan-cache-pull` refresh, no GitHub divergence check.
   - Phase 2 (Load Plan): read the local plan.md; **no** `gh issue view` for the plan; fetch the task Issue only when `context.md` has `source:`. Branch-name derivation moves out (now draft's job; the branch name is `context.md` `branch:`).
   - Phase 3 (Execution Prep): create the git branch; **append** `base_branch:` to the existing `context.md`; write `gh/task.json` when a parent exists. No plan pull.
   - Phases 4/5: replace every `plan-cache-push.sh` checkpoint with nothing (the local file is already authoritative); `plan-check-item.sh` keeps working against the new path. Delete the "never call `gh issue edit`" rule (no Issue to edit).
   - Phase 8: gate unchanged; workflow sections pack gains the `## Implementation Plan` snapshot block; trailer per 5.2. Remove the "Final Sync Checkpoint" step.
   - `hq:wip`-on-plan continue-report trigger: delete (no plan Issue to carry the label).
4. **`commands/triage.md`**
   - Phase 1: recover the plan via `headRefName` → `<branch-dir>` → `.hq/tasks/<branch-dir>/plan.md` (replaces parsing `Closes #`). If the local dir is missing (other-clone PR), disposition 1 becomes unavailable for that session — offer only 2/3/4 and say why.
   - Disposition 1: append to local plan.md (no pull/push). Note in the body transform table that the PR's `## Implementation Plan` snapshot is not re-edited.
   - Disposition 3: `hq:feedback` body `Refs #<PR>`.
5. **`commands/archive.md`**
   - done mode: remove the "plan was auto-closed by merge" note.
   - cancel mode: remove the `gh issue close <plan>` step entirely (close the PR only). Memory/report wording updated.
6. **`commands/respond.md`** — check for `hq:plan` Issue references; expected minimal (feedback `Refs` target moves to the PR).
7. **`skills/pr/SKILL.md`**
   - Step 3 (traceability): read `source`/`branch` from context.md (no `plan` number). If context.md is missing, ask for the task number only.
   - Step 4 (standalone mode): plan path `.hq/tasks/<branch-dir>/plan.md`; **also fix the stale Known Issues format here** — Step 4 currently emits severity-descending `- [<Severity>]: <title>` which contradicts the 3-category + `**Triage summary**` + `[<Severity>] [<originating-agent>]` invariant in `workflow.md § PR Body Structure` (drift item DR-1, see 7.2; fixing it is unavoidable in this phase because the surrounding lines change).
   - Step 5: assemble `## Implementation Plan` snapshot + `Refs`-only trailer. Title derives from the plan file's `#` heading.
   - Invariants section: per 5.2.
8. **`scripts/`**
   - **Delete** `plan-cache-pull.sh`, `plan-cache-push.sh`.
   - `plan-check-item.sh`: cache path `gh/plan.md` → `plan.md`.
   - `find-plan-branch.sh`: input changes from plan number to branch query. New behavior: exact match against `branch:` fields in `.hq/tasks/*/context.md`, else unique-substring match; same exit codes (0 found / 1 not found / 5 ambiguous). Rename to `find-plan.sh` and update all call sites.
   - `read-context.sh`: unchanged.
9. **`rules/feedback.md`** — FB frontmatter: replace the numeric `plan:` field with `branch:` (from context.md); `source:` unchanged. Update the field-sourcing instruction.
10. **`docs/workflow.md`** — rewrite affected sections (command map, lifecycle, draft/start/triage/archive flows, Cache-First → Local Plan, PR body example). Keep it a faithful summary of the rules, not a second spec.
11. **`agents/integrity-checker.md`, `agents/code-reviewer.md`, `agents/security-scanner.md`** — grep for `gh/plan.md` / plan-Issue references and update paths/wording only.

### 5.4 Acceptance (for this phase's own hq plan)

- `[primary]` (Tier 3 structural): `rg -n "plan-cache-(pull|push)|gh/plan\.md|Closes #" plugin/v3/` returns zero hits, AND `plugin/v3/scripts/plan-cache-pull.sh` / `plan-cache-push.sh` do not exist, AND `rg -l "Implementation Plan" plugin/v3/rules/workflow.md plugin/v3/skills/pr/SKILL.md plugin/v3/commands/start.md` hits all three files.
- Secondary: `bash -n` passes on all remaining scripts; `find-plan.sh` unit-style smoke (fixture context.md dirs → found/not-found/ambiguous exit codes).
- Manual: one end-to-end dogfood run (`/hq:draft` → file created → `/hq:start` → PR carries `## Implementation Plan` + `Refs`-only trailer → `/hq:triage` resolves the plan from headRefName).

---

## 6. Phase 2 — Protocol extraction + drift cleanup

Pure restructuring. Behavior after this phase must be 1:1 with behavior before it (post-Phase-1 behavior). This is the enabling move for Phase 3: agents cannot execute command files directly (P5 — `!` lines / `$ARGUMENTS` don't work for a Reading agent), so the phase specs move to plain rule files.

### 6.1 Extraction

Create three protocol files carrying the full phase specifications, moved (not copied) from the commands:

- **`rules/draft-protocol.md`** ← draft.md Phases 1–5 + Rules. Context acquisition (`git branch --show-current`, override file read, workflow.md read) expressed as explicit numbered steps instead of `!` preamble.
- **`rules/start-protocol.md`** ← start.md Settings / Commit Policy / Phase Timing / Phases 1–11 / Diff Classification / Rules / Stop Policy.
- **`rules/triage-protocol.md`** ← triage.md Phases 1–5 + Rules (ordered gate, bias rules, briefing template, apply logic).

Each command file shrinks to: frontmatter (name, description, allowed-tools — unchanged), `!` context block (kept for the command path — it is free context), `$ARGUMENTS` handling, and a single instruction: *"Read `${CLAUDE_PLUGIN_ROOT}/plugin/v3/rules/<name>-protocol.md` and execute it in `<mode>` mode with the arguments above."* Target ≤ 60 lines per command file.

### 6.2 Mode parameterization (declared now, exercised in Phase 3)

Each protocol file opens with a **Modes** section:

- `draft-protocol.md`: single mode. (Loop runs it inline, identically to standalone — after Phase 1, output is the same local file either way.)
- `start-protocol.md`: `standalone` (current behavior; `pause-consult` talks to the user directly) vs `agent` (differences defined in Phase 3 — placeholder subsection with "reserved for /hq:loop" note).
- `triage-protocol.md`: `interactive` (current strict per-item contract — unchanged, including the "no disposition applied without an explicit per-item response" invariant) vs `auto` (placeholder, defined in Phase 3). State explicitly that `auto` mode is sanctioned **only** when invoked by `/hq:loop`.

### 6.3 Drift / contradiction cleanup (verified findings)

Fix these concrete defects found during the design review:

- **DR-1** — `skills/pr/SKILL.md` Step 4 Known Issues format (severity-descending flat list, `- [<Severity>]: <title>`) contradicts `workflow.md § PR Body Structure` Invariants (3 action-priority categories + `**Triage summary**` line + dual `[<Severity>] [<originating-agent>]` tags). Already fixed in Phase 1 (5.3 item 7) — verify here, since standalone-mode Step 4 is the only remaining composer of this section outside start Phase 8.
- **DR-2** — `start.md § Phase 5 § 1-by-1 toggle rule` claims batch toggling "trips the integrity hook". **No hook exists** anywhere in this repo (no `hooks` entry in `.claude-plugin/plugin.json`, no hooks config in `.claude/settings.json`). Either delete the hook claim (keep the 1-by-1 rule on audit-trail grounds alone) or implement the hook; default: delete the claim, keep the rule.
- **DR-3** — Retrospective schema is specified twice, nearly verbatim (`workflow.md § Retrospective` and `start.md § Phase 9 § Schema`). Keep the schema in `workflow.md` only; `start-protocol.md` Phase 9 cites it (`hq:workflow § Retrospective`) and adds only the run-time steps (inputs list, output path, stop policy).
- **DR-4** — Plan body shape is specified three times (`workflow.md § hq:plan`, `draft.md § Required plan body shape`, `docs/workflow.md § Plan Structure`). Keep the normative template in `workflow.md`; `draft-protocol.md` cites it and keeps only composition rules that are draft-specific (consumer coverage check, tag→derivation table); `docs/workflow.md` keeps a shortened illustrative sketch with a pointer.
- **DR-5** — `docs/workflow.md` is an explanatory mirror that has already drifted (it restates phase mechanics at spec-level detail). Reduce it to command map + lifecycle + pointers; the protocols are the spec. This prevents the next drift rather than patching this one.
- **DR-6** — Sweep for post-Phase-1 stragglers: `rg -n "hq:plan Issue|sub-issue|sub_issues|gh issue (view|edit|create).*plan" plugin/v3/` must be clean.

### 6.4 Acceptance

- `[primary]` (Tier 3 structural): the three `rules/*-protocol.md` files exist; each of `commands/{draft,start,triage}.md` is ≤ 60 lines and contains a `Read`-protocol instruction; `rg -n "integrity hook" plugin/v3/` returns zero hits.
- Secondary: DR-1..DR-6 greps clean (each has a concrete pattern above).
- Manual: one dogfood run of `/hq:draft` + `/hq:start` via the thin commands confirming behavior parity.

---

## 7. Phase 3 — `/hq:loop` + executor / auto-triager agents

### 7.1 `commands/loop.md`

Frontmatter: `allowed-tools` = draft's set + `Agent` + `AskUserQuestion`. Input: `$ARGUMENTS` = optional `hq:task` number and/or free text (same intake as draft).

Settings (in-file, overridable via `.hq/loop.md` project override — add the row to `workflow.md § Project Overrides`):

- **`loop_max_iterations` = 2** — maximum number of Stage 2 re-entries *after* the initial execution (so at most 1 + 2 executor runs).

Stages:

1. **Stage 1 — Draft (inline, interactive)**: execute `rules/draft-protocol.md` in the main conversation, verbatim — including the wide-impact survey, Simplicity gate, and the commit-or-pushback `go` gate. The auto-mode prohibition in the draft protocol applies inside loop exactly as it does standalone: the brainstorm and the `go` gate are sanctioned interaction points and must not be skipped.
2. **Stage 2 — Execute**: launch **one** `executor` agent (7.2) with a prompt carrying: branch-dir, iteration number, `loop_max_iterations`, and mode=`agent`. On a `consult-needed` return (7.3): surface the question to the user in the main conversation, get the decision, re-launch the executor with the decision in the prompt (the start protocol's auto-resume picks up from cached checkbox state).
3. **Stage 3 — Auto-triage**: after the executor returns a PR URL, launch **one** `auto-triager` agent (7.4) with: PR number, branch-dir, iteration number, remaining iteration budget.
4. **Loop decision**: if the triager reports `plan_gained_items: true` AND iterations used < `loop_max_iterations` → go to Stage 2 (the executor auto-resumes into the unchecked plan items). Otherwise → Stage 4.
5. **Stage 4 — Report + feedback confirmation (inline, interactive)**:
   - Work report: per-iteration summary (commits, acceptance results, self-review/agent-selection calls, triage dispositions with SHAs), PR URL, Manual Verification count, residual Known Issues.
   - Feedback candidates: the union of every iteration's disposition-3 candidates. Present as a numbered list with each candidate's rationale; ask the user (multi-select) which to create. Create the selected ones (`gh issue create --label hq:feedback`, body `Refs #<PR>`, project inheritance from the task when present). Explicitly report the ones NOT created as "dropped by user decision".
   - This stage is the **only** place loop creates `hq:feedback` Issues (preserves the workflow invariant that Issue-creation is human-gated — the invariant's owner moves from per-item triage response to this batch confirmation, for loop mode only).

Progress tracking: TaskCreate/TaskUpdate rows per stage, iteration-suffixed on re-entry (e.g., "Execute plan (iteration 2)").

Stop policy: executor failure (agent dies / returns error) → report and stop, never silently retry the whole stage more than once; triager failure → report, offer standalone `/hq:triage` as fallback; user rejects the `go` gate → loop back to brainstorm (draft protocol's own rule).

### 7.2 `agents/executor.md`

- Frontmatter: `name: executor`; `description` states it runs the hq start protocol autonomously for `/hq:loop` (with `<example>` blocks per repo agent conventions); `tools: Read, Edit, Write, Glob, Grep, Bash, Agent, TaskCreate, TaskUpdate` (needs `Agent` for the Phase 7 reviewer agents; Bash scoping as in start.md's allowed-tools); `model: inherit` (implementation is the highest-difficulty role — it gets the session model).
- Body (system prompt): "Read `plugin/v3/rules/start-protocol.md` and execute it in **agent mode** for the plan named in your task prompt. Your final message must be exactly the return schema below." Return schema (structured, parseable by the loop):
  - `status: completed | consult-needed | failed`
  - completed → PR URL, FB counts by severity, self-review result, agents launched/skipped, phase-timing summary, `[primary]` pass/fail, and **distilled learnings** (the lines Phase 10 added/changed in `.hq/start-memory.md` this run, or "none") — surfaced in the loop's Stage 4 report so the user can audit that the learning loop is turning.
  - consult-needed → the Phase 6 significant-gap question, with the context the user needs to decide.
  - failed → what phase, what error, what state was left (branch, commits, cache).

`start-protocol.md` **agent mode** definition (added in this phase to the placeholder from 6.2):

- Phase 6 `pause-consult` (significant-gap) → do not attempt user interaction; write the decision report, then **return `consult-needed`** immediately (the loop re-launches after the user decides; auto-resume re-enters at Phase 6 via the resume-phase-selection rules).
- Phase 11 report → emitted as the structured return schema instead of a chat report (the loop renders the user-facing report in Stage 4).
- Everything else identical to standalone mode.
- The pr-skill delegation in Phase 8 becomes Read-and-follow for agent mode: read `plugin/v3/skills/pr/SKILL.md` and execute it (P5 — do not rely on the Skill tool inside a subagent).

### 7.3 Consult-needed round trip

```
executor (Phase 6 significant-gap) → returns consult-needed
loop (main conversation)           → presents gap → user decides
loop → re-launch executor, prompt includes the user's resolution
executor → auto-resume (checkbox state) → Phase 6 completes with the resolution → continues
```

This preserves the start protocol's single sanctioned mid-flight consult without violating P1.

### 7.4 `agents/auto-triager.md`

- Frontmatter: `name: auto-triager`; `tools: Read, Grep, Glob, Edit, Write, Bash, TaskCreate, TaskUpdate` (Bash: git/gh for liveness checks, fix-in-place commits, PR body edit); `model: sonnet` (gate application + liveness reading — mechanical relative to implementation; revisit in Phase 4).
- Body: "Read `plugin/v3/rules/triage-protocol.md` and execute it in **auto mode** for the PR named in your prompt."

`triage-protocol.md` **auto mode** definition (added in this phase):

- Phases 1–2 identical (load PR, parse Known Issues).
- Phase 3: derive each item's Suggestion via the existing liveness check + ordered gate + bias rules, then **apply it as the disposition without user confirmation** — with these auto-mode overrides:
  - **Disposition 3 (escalate) is never applied.** Record the item as a *feedback candidate* (title, severity, rationale, originating agent) in the return payload; transform its PR-body line only if/when the loop's Stage 4 actually creates the Issue (so: leave the line untouched, candidates carry enough info for loop to do the transform after creation — simplest: loop performs the `escalated: #N` body edit itself post-creation).
  - **Disposition 1 (add to plan) is budget-gated**: allowed only when the prompt says iteration budget remains, AND only for Must Address items (Critical/High). Medium/Low items that would gate to 1 are downgraded to 2 (leave) with a `deferred: loop budget` note. When budget is exhausted, all would-be-1 items become feedback candidates instead (they must not silently disappear).
  - Bias rules and the disposition-4 regression gate (format/build/test, 2-failure revert) apply unchanged — this is the safety floor for unattended fixes.
- Phase 4: apply 4-then-1-then-single-atomic-body-edit as in interactive mode (minus disposition-3 writes).
- Phase 5 → structured return: per-item table (item, liveness, gate fired, disposition applied, SHA where relevant), `plan_gained_items: true|false`, feedback candidates list.
- Guard text: auto mode is sanctioned only under `/hq:loop`; the interactive-mode invariant ("no disposition applied without an explicit per-item response") is explicitly scoped to interactive mode, and the compensating controls for auto mode are named: no autonomous Issue creation, regression-gated fixes, iteration budget, full audit trail in the loop report.

### 7.5 Registration + docs

- `.claude-plugin/plugin.json`: add `./plugin/v3/agents/executor.md` and `./plugin/v3/agents/auto-triager.md` to `agents` (file-path array — see memory: directories are not accepted). `commands` dir is auto-discovered; verify `loop.md` appears.
- `rules/workflow.md`: add `hq:loop` to Terminology + a short `§ Loop` section (stage map, iteration cap, the auto-triage sanction, feedback-confirmation gate). Add `.hq/loop.md` to the Project Overrides table.
- `docs/workflow.md`: add the loop to the command map.
- `skills/worktree-setup/scripts/worktree-setup.sh`: add `.hq/loop.md` to the override copy list (required by `workflow.md § Project Overrides § Worktree propagation`).

### 7.6 Acceptance

- `[primary]` (Tier 3 structural): `plugin.json` lists both new agent files; `commands/loop.md` exists and cites all three protocol files; `rules/triage-protocol.md` contains an `auto` mode section that forbids autonomous disposition-3 application; `rules/start-protocol.md` contains an `agent` mode section defining the `consult-needed` return.
- Secondary: `plugin-dev:plugin-validator`-style structural validation passes (manifest paths resolve).
- Manual Verification: one full `/hq:loop` dogfood run on a small real task — observe: go gate honored, executor PR created, auto-triage applied with audit trail, loop terminated within budget, feedback confirmation offered.

---

## 8. Phase 4 — Evaluation pass (deferred decisions)

Not scheduled work — re-evaluation gates after ≥ 3 real `/hq:loop` runs. Each item names its trigger.

- **E1 — Split `start` into multiple agents?** (owner's open question). Decision now: **no**. Rationale: phases 4–8 share heavy sequential state (plan checkboxes, commit stream, working tree, FB dir) — splitting forces that state through agent boundaries for no parallelism gain; Phase 7 already fans out to reviewer subagents where parallelism actually exists. Re-open if: executor runs routinely blow context (symptom: degraded quality in late phases — retro/distillation), in which case split **Phases 9–10 (retro + distillation)** into a cheap background agent first — it is read-only over run artifacts and needs none of the execution state.
- **E2 — Model assignment tuning.** Initial: executor `inherit`, auto-triager `sonnet`, security-scanner `sonnet` (existing), others `inherit`. Re-open if: auto-triager mis-gates dispositions (evidence: user overrides in reports) → raise to `inherit`; or executor cost dominates → try `sonnet` for doc-only plans.
- **E3 — Interactive triage inside loop as an option.** If unattended disposition-4 fixes ever regress production code despite the gate, add a `loop_triage_mode: auto | confirm` setting (batch-confirm before apply) rather than reverting to per-item.
- **E4 — Plan durability window.** If a plan is ever lost pre-PR (clone deletion), consider committing plan.md to the feature branch as the first commit instead of keeping it gitignored.
- **E5 — Feed retro learnings into draft (Stage 1).** Today only start Phases 4/6/7 consume `.hq/start-memory.md`; draft's Simplicity gate does not (explicitly deferred in `workflow.md § Retrospective`). `/hq:loop` raises the value of closing this: Stage 1 could read `start-memory.md` as brainstorm priors (e.g., recurring `prevention_lever: stricter-acceptance` → push harder on the primary tier). Re-open after ≥ 3 loop runs when there is real distilled content to test against; ship as its own plan per the existing deferral note.

## 9. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Nested Skill invocation is undocumented (P5) | Never used: reuse is Read-and-follow of `rules/*-protocol.md` and `skills/pr/SKILL.md` (agent mode). |
| Auto-triage removes the anti-pollution fence | Compensating controls: no autonomous `hq:feedback` creation; regression-gated fixes with 2-failure revert; iteration budget; Must-Address-only re-loop; full per-item audit trail; standalone `/hq:triage` unchanged. |
| Executor cannot consult the user (P1) | `consult-needed` return + re-launch on auto-resume (7.3). |
| Plan loss pre-PR (gitignored `.hq/`) | Accepted (D1); PR snapshot from creation onward; E4 escape hatch. |
| Big-bang doc surface (Phase 1 touches ~11 files) | Phase 1 is storage-only (no protocol moves); Phase 2 is moves-only (no behavior change); each phase has structural greps as `[primary]`. |
| `$ARGUMENTS` / `!` lines dead when agents Read command files | Protocols contain no `!` lines; commands keep them only as their own preamble (6.1). |

## 10. Out of scope

- `plugin/v2/`, `plugin/v1/` — frozen, untouched.
- `hq:task` authoring flow, `/hq:respond`, `/hq:archive` beyond the plan-Issue removals in 5.3.
- `tools/` CLI (Go binary) — no changes.
- Reading retro learnings back into draft Phase 2 (already deferred by `workflow.md § Retrospective`).
- Team-shared plan storage / multi-clone plan sync.

## 11. Phase 5 — Loop consolidation: root-agent judgment, PR-last, loop-only

Added 2026-07-04 after the Phase 1–3 implementation and before any real run. Owner directives (final):

| # | Directive |
|---|---|
| D5 | **Root agent is the judge.** The model running `/hq:loop` (session model, Opus/Fable class) is assumed to out-judge a typical human developer. Semantic decisions that cannot be settled deterministically are routed to the **root agent**, never to a subagent and never forced into mechanical rules. Deterministic rails (scripts, structural gates, regression gates) remain deterministic. Subagents gather evidence and execute; they do not make final calls. |
| D6 | **Loop-only.** Standalone `/hq:draft` / `/hq:start` / `/hq:triage` are retired (supersedes D4). `/hq:loop` is the single pipeline entry with a state-machine pre-flight; `/hq:respond` and `/hq:archive` remain as orthogonal post-PR tools. |
| D7 | **PR-last.** The PR is created only **after** triage completes — the PR is the final proposal, not an intermediate hand-off. Triage operates on local FB files directly (no PR-body parsing). Supersedes the Phase 3 order (PR → triage). |
| D8 | **PR content refocus.** The PR body is what a human reviewer needs: motivation, chosen approach (+ deviations discovered during build), changes, verification — not the agent's task list. The `## Implementation Plan` full-plan embed (Phase 1, 5.2) is **dropped**; `.hq/pr.md` format overrides continue to govern the narrative. The plan file stays a local working artifact, archived with the task dir (durability tradeoff re-accepted; E4 remains the escape hatch). |

### 11.1 Target stage map

```
/hq:loop <input>                                   ROOT = session model, main conversation
│
├─ Stage 0 RESUME  (root)          state detection from artifacts:
│     no plan.md                     → Stage 1
│     plan.md w/ unchecked items     → Stage 2 (covers old /hq:start)
│     built, FBs untriaged           → Stage 3/4
│     PR exists                      → Stage 7 or /hq:respond / /hq:archive hint
│
├─ Stage 1 PLAN    (root, interactive)  draft-protocol: intake+survey → brainstorm+
│     Simplicity gate → compose → go gate (answers: go / stop = plan-only exit / pushback)
│     → plan.md + context.md
│
├─ Stage 2 BUILD   (executor agent, model: inherit)  execute-protocol:
│     branch → per-item implement+commit → acceptance sweep (retry cap) → structured return
│     entry modes: fresh / fix-directive (root-composed fix instructions; absorbs the old
│     P4 loopback AND triage disposition-4 fixes AND disposition-1 follow-up items)
│
├─ Stage 3 REVIEW
│     J3 root: acceptance review of the build (plan alignment / out-of-scope impact /
│         tunnel vision — absorbs old start Phase 6 Self-Review; now genuinely third-party
│         because the root did not write the code) → pass | fix-directive → Stage 2 | consult user
│     J4 root: reviewer-agent selection (judgment; credential hard-floor stays deterministic)
│     → launch code-reviewer / security-scanner / integrity-checker in parallel → FB files
│
├─ Stage 4 TRIAGE  (root judgment over FB files — pre-PR, no PR body involved)
│     J5 root, per FB: validity → ownership → scope/risk (ordered-gate heuristic + bias
│     rules as judgment priors, not mechanical procedure). Dispositions:
│       fix now        → fix-directive queue → Stage 2 re-entry (regression-gated)
│       plan follow-up → plan.md append → Stage 2 re-entry            } budget-gated
│       accept         → residual list (→ PR ## Known Issues)
│       escalate       → feedback candidate (user-confirmed at Stage 7)
│     evidence gap → root MAY launch a read-only verification agent for that FB
│
├─ Convergence judgment (J8, root — **the exit judgment of Stage 4**, replacing the
│     mechanical loop decision):
│     fires after EVERY Stage 2→3→4 cycle — including the first (a first triage whose
│     FBs are all micro-fix-grade converges at iteration 0). Root judges the trajectory:
│     • CONVERGED — residual is trivial (low-severity, no new design questions):
│         one final fix-directive micro-pass (executor, regression-gated), then
│         **integrity-checker re-run scoped to the micro-diff** (residual/consumer/
│         surface-integrity check — the one reviewer whose axis a "trivial" fix can
│         still break) + root spot-check of the micro-diff → Stage 5. No full
│         Stage 3–4 re-run.
│         Spot-check record (unconditional): the J8 decision record (or an addendum
│         to it) MUST record the spot-check — the surface(s) checked, the
│         verification method (eyeball or command), and, when a command was run,
│         the command and its result.
│         Continue re-grading: a fix whose correctness the spot-check cannot
│         cheaply confirm is not micro-fix-grade — re-grade the verdict to Continue
│         (budget exhausted → force-close applies: ESCALATE candidate, never a
│         silent drop).
│     • CONTINUE — substantive but bounded follow-ups, budget remains → Stage 2
│         (Stage 3–4 re-run after). loop_max_iterations stays as the hard backstop.
│     • DIVERGING — fixes spawn new defects / new design questions (signals: same-or-
│         higher-severity FBs on already-fixed surfaces, FBs contradicting plan
│         assumptions, fix→new-FB chains across iterations, repeated primary failure)
│         → plan-defect hypothesis → BLOCK and consult the user (interaction ②):
│         present the problem analysis + root cause in the plan + a concrete revised-
│         plan proposal (verbatim, go-gate discipline).
│           user approves revision → plan.md updated (affected items re-opened),
│             iteration budget resets → Stage 2
│           user declines / aborts → SAFE CANCEL: archive-cancel route (no PR exists
│             yet — task folder → .hq/tasks/canceled/, branch force-deleted, memory
│             cleared; read-and-follow commands/archive.md cancel mode) → report & end
│
├─ Stage 5 SHIP    (root composes, J6; pr skill executes)  PR creation — final proposal:
│     narrative (Summary / Approach incl. deviations / Changes — from plan Why/Approach +
│     build reality; .hq/pr.md override) + ## Manual Verification + ## Known Issues
│     (post-triage residual only) + Refs #task. No plan embed.
│
├─ Stage 6 RETRO   (retro-distiller agent, model: sonnet, background-able)
│     retro (now covers build + review + triage dispositions) → .hq/retro/<branch-dir>.md
│     → distill into .hq/start-memory.md (char-capped)
│
└─ Stage 7 REPORT  (root, interactive)
      work report + J5 audit trail (incl. suggestion-vs-decision divergences) +
      feedback candidates → user multi-select → gh issue create hq:feedback (Refs #PR)
```

### 11.2 Root-agent judgment catalog

Every judgment leaves a decision record under `.hq/tasks/<branch-dir>/reports/` (auditability unchanged).

| ID | Where | Judgment | Deterministic floor that still binds |
|---|---|---|---|
| J1 | Stage 0 | ambiguous state → which stage to enter; stale-artifact handling | artifact existence checks are mechanical |
| J2 | Stage 1 | Simplicity gate pushbacks; `[primary]` tier commitment; plan-split | plan body schema, tag set, 1-`[primary]` rule |
| J3 | Stage 3 | build acceptance: plan alignment / out-of-scope / tunnel vision → pass / fix-directive / consult | Phase-5 sweep results are facts, not re-judged |
| J4 | Stage 3 | reviewer-agent subset selection | credential-prefix hard floor forces security-scanner |
| J5 | Stage 4 | per-FB disposition + fix-directive composition + budget allocation | regression gate on fixes; iteration cap; no autonomous Issue creation |
| J6 | Stage 5 | PR narrative: what the human reviewer needs (motive, approach, deviations) | workflow sections + labels + Refs trailer invariants; `.hq/pr.md` |
| J7 | Stage 7 | candidate presentation quality (grouping, rationale) | Issue creation itself is user-gated |
| J8 | Stage 4 exit (every cycle, incl. iteration 0) | **convergence judgment**: converged (micro-fix → integrity-checker re-run → Ship) / continue (re-enter) / diverging (plan-defect hypothesis → block, propose plan revision, or safe-cancel on user decline) | regression gate on the micro-pass; integrity-checker re-run is mandatory after any micro-fix; `loop_max_iterations` hard backstop; plan revision and cancel are both user-gated |

### 11.3 File-level deltas

1. **`commands/loop.md`** — full rewrite: Stage 0 state machine, Stages 1–7, the J1–J8 judgment specs (criteria + decision-record contract), settings (`loop_max_iterations`), stop policy. The triage judgment criteria (ordered-gate heuristic, bias rules, over-fixing guard) move here (or to `workflow.md § Triage Judgment` — implementer's choice; single home, cited from loop.md). **Progress Tracking is a first-class contract**: at loop start, TaskCreate one task per stage (Stage 0–7); set `in_progress`/`completed` at stage boundaries; on J8 re-entry, create iteration-suffixed tasks (`Build (iteration 2)` …); reflect J8 outcomes in task subjects (e.g., `Converged — micro-fix + integrity re-check`); update long stages with in-progress counts (`Build — item 3/5`). Subagents keep the existing convention of reporting via TaskCreate/TaskUpdate so their progress is visible in the same UI. The user must be able to tell the loop's current position from the task list alone at any moment.
2. **`rules/draft-protocol.md`** — keep as Stage 1 spec; add `stop` as a sanctioned gate answer (plan-only exit); drop the "consumed by /hq:draft" framing.
3. **`rules/start-protocol.md` → `rules/execute-protocol.md`** — strip Phases 6–11 (Self-Review → J3; Quality Review orchestration → Stage 3; PR → Stage 5; retro/distill → Stage 6; report → return schema). Keep: pre-flight/branch/context (P1–P3), execute (P4), acceptance sweep + retry loop (P5), commit policy, phase timing (rescope), continue-report FBs. Entry modes: `fresh` / `fix-directive` (a root-composed instruction list; replaces both the old P5 loopback framing and triage-fix application). Return schema gains `self_notes` (implementer's own residual concerns — evidence for J3).
4. **`rules/triage-protocol.md`** — **deleted**. Judgment criteria relocate per item 1; FB schema stays in `rules/feedback.md`.
5. **`skills/pr/SKILL.md`** — body redesign per D8: narrative (Summary / Approach / Changes, `.hq/pr.md`-overridable) + `## Manual Verification` + `## Known Issues` = post-triage residual (accepted limitations + `escalated: #N` links; no Triage-summary-for-later-processing framing — nothing is "to be processed" anymore) + `Refs #<task>`. Remove `## Implementation Plan` invariant. Standalone `/pr` mode stays for ad-hoc branches.
6. **Agents** — `auto-triager.md` deleted; `executor.md` updated (execute-protocol, fix-directive mode, self_notes); **new `retro-distiller.md`** (sonnet): consumes run artifacts (reports, FBs incl. triage dispositions, timings, git log) → retro artifact + start-memory distillation per `workflow.md § Retrospective` (schema updated to include a `## Triage Analysis` axis or fold dispositions into FB Analysis — implementer's choice, keep the 4-section gate).
7. **`rules/workflow.md`** — § Loop rewrite (stage map + judgment catalog pointer); § PR Body Structure rewrite (D8); § Feedback Loop rewrite (FBs are triaged pre-PR; `feedbacks/done/` move happens at triage disposition, not PR creation); § Terminology (`hq:loop` primary entry; retire `/hq:draft`/`/hq:start`/`/hq:triage` references repo-wide); Retrospective source list update.
8. **`commands/draft.md` / `start.md` / `triage.md`** — deleted. `respond.md` / `archive.md` swept for references (archive's pending-FB pre-check semantics now "untriaged FBs = abnormal"; respond unchanged).
9. **`docs/workflow.md` + `docs/hq-loop-flow.html`** — updated to the new model. `CLAUDE.md` Dogfooding paragraph updated.
10. **`.claude-plugin/plugin.json`** — agents list: −auto-triager, +retro-distiller.

### 11.4 Acceptance (structural, Tier 3)

- `commands/{draft,start,triage}.md` and `rules/triage-protocol.md` and `agents/auto-triager.md` do not exist; `rules/execute-protocol.md` and `agents/retro-distiller.md` exist; `plugin.json` reflects the agent set.
- `rg -n "Implementation Plan" plugin/v3/skills/pr/SKILL.md plugin/v3/rules/workflow.md` → zero hits (D8).
- `rg -n "/hq:draft|/hq:start|/hq:triage" plugin/v3/ --glob '!plugin/v3/docs/plan.md' --glob '!plugin/v3/docs/hq-loop-flow.html'` → zero hits (both excluded docs reference the old names only as history).
- loop.md contains all eight judgment IDs (J1–J8) with decision-record contracts, including J8's three outcomes (converged path mandating the integrity-checker re-run), the safe-cancel route, and the per-stage Progress Tracking contract.
- Manual Verification: one full dogfood run — plan-only exit (`stop`) works; a triage fix-directive round-trips through the executor; a simulated diverging run reaches the J8 block with a plan-revision proposal, and declining it lands in `.hq/tasks/canceled/`; PR carries the refocused body; retro-distiller writes both artifacts.

## 12. Phase 6 — Central telemetry sink (`~/.hq/`)

Added 2026-07-04. Owner decision: `.hq/` working state stays **project-local** (locality, direct plan editability, worktree isolation, override commit path, permission surface all depend on it); only **telemetry — write-once analytical run data** — is centralized, so cross-project statistics (e.g., J8 divergence rate, J5 disposition accuracy, timing distributions) become queryable without scraping clones. Architecture: **dual-write, not move** — human-readable records keep living in the project `.hq/`; a structured event row additionally lands in the central sink.

### 12.1 Storage

- **`~/.hq/events.jsonl`** — append-only JSONL, one event per line. Append-only is unconditionally safe for concurrent writers (parallel agents, parallel worktrees); no locking, no dependencies.
- **sqlite is a later query layer, not the write path.** When statistics work starts, an import script (`events.jsonl` → `~/.hq/hq.sqlite`) materializes tables; raw JSONL remains the source of truth so schema iteration never loses data. Building the importer is out of scope for this phase (deferred until the first real analysis need).

### 12.2 Event schema

```json
{"ts":"<ISO 8601 UTC>","repo":"<owner/repo — normalized origin URL; fallback: top-level dir name>",
 "branch":"<work branch>","run_id":"<branch-dir>-<loop start ts>","worktree":"<absolute path — attribute, never a key>",
 "kind":"<see catalog>","payload":{...}}
```

Identity rules: `repo` (normalized `git remote get-url origin` → `owner/repo`, strip `.git`; no remote → top-level dir name prefixed `local:`) is the aggregation key. `worktree` and `branch` are attributes — worktree churn must not fragment history. `run_id` groups one `/hq:loop` invocation (re-entries share it; a J8-approved revision keeps it, recording the revision as an event).

**Event kinds (closed catalog — extending it is a deliberate edit to this section):**

| kind | emitted at | payload (minimum) |
|---|---|---|
| `run_start` / `run_end` | loop entry / Stage 7 exit (or cancel/stop exit) | entry stage; end: outcome (`shipped` / `plan-only` / `canceled` / `failed`), iterations used |
| `gate` | Stage 1 gate resolution | `go` / `stop` / pushback count |
| `build_result` | each executor return | mode, status, primary pass/fail, fb count, noop |
| `j_decision` | each J1–J8 decision record write | judgment id, verdict (e.g. J3 pass/gap/consult; J4 launched set), record path |
| `disposition` | each J5 per-FB decision | fb id, severity, origin agent, disposition, prior-departure flag |
| `j8_verdict` | each Stage 4 exit | converged / continue / diverging; on diverging: user outcome (revised / canceled) |
| `timing` | Stage 7 (once) | `phase-timing.sh summary` parsed to per-slot seconds |
| `retro` | retro-distiller return | judgment_hindsight headline, start_memory_delta, plugin_level_findings count |

### 12.3 File-level deltas

1. **New `scripts/hq-event.sh`** — `hq-event.sh <kind> [key=val ...]`: resolves `repo`/`branch`/`worktree` itself (git), takes `run_id` from `.hq/tasks/<branch-dir>/context.md` (see item 3), JSON-escapes, appends one line to `~/.hq/events.jsonl` (`mkdir -p ~/.hq`). **Never fails the pipeline**: any error (unwritable home, no git) prints a warning and exits 0 — telemetry is observability, not a gate.
2. **`commands/loop.md`** — add § Telemetry: the emission points per the catalog (root emits `run_start`/`gate`/`j_decision`/`disposition`/`j8_verdict`/`timing`/`run_end`); one line per decision-record write, adjacent to it. Note the non-blocking contract.
3. **`rules/workflow.md § Focus`** — `context.md` gains an optional `run_id:` field, written at loop entry (Stage 0/1) so all writers (root, executor, distiller) share it; absent field → helper falls back to `<branch-dir>-unknown`.
4. **`rules/execute-protocol.md`** — executor emits `build_result` just before its structured return (one `hq-event.sh` call).
5. **`agents/retro-distiller.md`** — emits `retro` before its return.
6. **`hq:workflow § Terminology` or a short § Telemetry** — one paragraph: what `~/.hq/events.jsonl` is, dual-write principle, non-blocking contract, privacy note (events carry titles/ids/verdicts, never diff content or code).
7. **Docs** — `docs/workflow.md` "Where things live" gains the `~/.hq/events.jsonl` line; README Design Philosophy gains one bullet.

### 12.4 Acceptance

- `[primary]` (Tier 1 behavioral): a fixture-driven smoke test of `hq-event.sh` — emits 3 kinds from a temp git repo with `HOME` overridden, asserts 3 valid JSON lines with correct `repo` normalization (remote and no-remote cases) and that a read-only `HOME` exits 0 with a warning.
- Structural: `rg -c "hq-event.sh" plugin/v3/commands/loop.md plugin/v3/rules/execute-protocol.md plugin/v3/agents/retro-distiller.md` ≥ 1 each; the kind catalog appears in loop.md § Telemetry.
- Manual Verification: after the next real `/hq:loop` run, `~/.hq/events.jsonl` contains a coherent `run_start` → … → `run_end` sequence for it.

### 12.5 Deferred (named, not scheduled)

- **E7 — sqlite importer + first stats queries** (divergence rate per repo, disposition distribution, slot timing percentiles). Trigger: the first time the user actually asks a statistics question.
- **E8 — per-repo start-memory sharing** (`~/.hq/repos/<owner-repo>/start-memory.md`) so worktrees of the same repo share learnings. Trigger: worktree-parallel usage becomes routine. Carries the identity-key complexity — do not bundle into Phase 6.

