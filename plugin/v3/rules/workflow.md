# Workflow

## Prerequisites

- **`gh` CLI** must be authenticated: `gh auth status` must succeed
- All issue operations (`gh issue view`, `gh issue create`, `gh issue list`, `gh issue close`) require this

## Branch Rules

- **Never work directly on base branches** (`main`, `develop*`) — always create a feature branch
- **Base branch resolution** (used by all skills): `.hq/tasks/<branch-dir>/context.md` `base_branch:` → `.hq/settings.json` `base_branch` → `git symbolic-ref refs/remotes/origin/HEAD` → `"main"`
  - `.hq/tasks/<branch-dir>/context.md` `base_branch:` is the **per-branch authoritative record** — written at branch creation time (execute-protocol Phase 3) from `git symbolic-ref --short HEAD` immediately before `git checkout -b`. It captures the actual divergence point and survives global setting drift across worktrees / stacked PRs.
  - `.hq/settings.json` is the **project-wide default** — used when no `context.md` exists for the current branch (e.g., the branch was created outside the loop, or `context.md` was lost). Most projects need no config here — git remote HEAD detection works automatically.
  - Set `.hq/settings.json` `{ "base_branch": "<branch>" }` only when an explicit project-wide override is needed (e.g., a repo whose default base is `develop`, not `main`).
  - The resolution order is **invariant** across all consumers (execute-protocol, `pr` skill, `worktree-rebase` skill). Consumers MUST NOT skip the `context.md` step.

## Terminology

- **`hq:workflow`** — shorthand for `plugin/v3/rules/workflow.md` (this file — the plugin-internal source of truth for the workflow rule, loaded on demand by each command). Skills and commands cite sections as `hq:workflow § <section>` instead of repeating the full path.
- **`hq:task`** — a GitHub Issue (label: `hq:task`) that describes **what** needs to be done. The requirement. **Trigger** of the workflow.
- **`hq:plan`** — a **local plan file** at `.hq/tasks/<branch-dir>/plan.md` that describes **how** to do it. The implementation plan. **Center** of the workflow — drives execution, verification, and PR. Created at loop Stage 1 (draft protocol); identified by its branch name. One `hq:task` can have multiple `hq:plan` files (one per branch). Not a GitHub Issue, and **not embedded in the PR** — it is the loop's internal work log; its motivation / approach reach the PR reviewer through the Stage 5 narrative (see `## PR Body Structure`). It travels with the task folder to `done/` / `canceled/` on archive.
- **`hq:feedback`** — a GitHub Issue (label: `hq:feedback`) for residual problems the loop escalates. Created only with explicit user confirmation: at `/hq:loop` Stage 7 (from triage escalate-candidates), or by `/hq:respond` for external review comments.
- **`hq:doc`** — a GitHub Issue (label: `hq:doc`) for informational notes / research findings worth preserving (not a direct task). Created manually by the user when investigation turns up something useful to retain. Not consumed by any workflow command.
- **`hq:pr`** — a PR label applied automatically by the `pr` skill (in either invocation mode — Standalone `/pr` or from the loop's Stage 5). Marks a PR as a product of the `hq:plan` → PR workflow. Useful for filtering PRs that belong to this workflow vs ad-hoc PRs.
- **`hq:wip`** — a GitHub Issue modifier label on `hq:task` Issues. Purpose is twofold: (1) **drafting marker** — the issue is still being shaped and not ready for automation, (2) **automation gate** — when the loop's Stage 1 receives the task automatically (e.g., from GitHub Actions), it must skip (or, in interactive invocation, pause and confirm) any Issue carrying this label.
- **`hq:loop`** — the pipeline's single entry command (`/hq:loop`); its root agent orchestrates and judges (J1–J8). Composes `draft-protocol` (inline) and `execute-protocol` (via the `executor` agent), with review / triage / ship / retro stages owned per `## Loop`.

These are plugin-specific terms. Always use the `hq:` prefix to distinguish from general "task", "plan", or "feedback".

## Naming Conventions

Titles follow **Conventional Commits** style. Recognized `<type>` values: `feat`, `fix`, `docs`, `refactor`, `chore`, `test`.

- **`hq:task` title**: `<type>: <requirement>`
  - Example: `feat: add user authentication`
- **`hq:plan` title**: `<type>(plan): <implementation approach>` — the `# `-heading first line of the plan file
  - Example: `feat(plan): implement user authentication with OAuth 2.0`
  - The `(plan)` scope distinguishes the implementation plan from the parent requirement.
- **PR title**: `<type>: <implementation>` — same as `hq:plan` title with `(plan)` removed
  - Example: `feat: implement user authentication with OAuth 2.0`
- **Branch name**: `<type>/<short-description>` (kebab-case, ≤ 40 chars, alphanumeric + hyphens)
  - Example: `feat/oauth-login`
  - Derived from the plan title at loop Stage 1 (the branch name keys the plan's directory `.hq/tasks/<branch-dir>/`; the execute protocol creates the actual git branch later).

## Language

Runtime-generated content — `hq:task` / `hq:plan` / PR bodies — is authored in the **conversation language** (the language the user is speaking in this session). Headings that are **auto-injected by the loop or parsed by downstream tooling** stay in **English** regardless, so the injection / parsing contract holds across projects. Narrative headings — including the PR body's narrative sections — are free-form and follow the conversation language.

- **English (fixed — auto-injected or parse-targeted)**:
  - Workflow markers: `[auto]`, `[manual]`, `[primary]`, `Refs #<task>`
  - `hq:task` / `hq:plan` prescribed headings: `## Why`, `## Approach`, `## Editable surface`, `## Plan`, `## Acceptance`, `## Manual Verification` (all consumed by the draft / execute protocols and the root's judgments; `## Manual Verification` is emitted only when the plan has reviewer-owned checks)
  - PR body **workflow sections**: `## Manual Verification` (Stage 5 carry-forward of the plan's reviewer-owned checks), `## Known Issues` (Stage 5 post-triage residual; Stage 7 rewrites pending escalation lines)
  - Editable surface inline tags: `[新規]` / `[改修]` / `[削除]` / `[silent-break]` (the brackets and tag values are fixed; the latter three are romaji-free fixed strings even in English-only repos — they are structural markers, not translatable prose)
  - Plan item consumer suffix: `*(consumer: <name>)*` (the literal `consumer:` keyword is fixed; `<name>` is the consumer identifier)
  - File paths, identifiers, code fences, shell commands
- **Conversation language (content)**:
  - `hq:task` body content — prose inside `## Background` / `## What` / `## Scope` / `## Success Criteria`, plus the optional `## Phase Split` (see `## hq:task` below)
  - `hq:plan` body content — prose inside `## Why` / `## Approach`, each `## Editable surface` entry note (after the inline tag), each `## Plan` step description, each `## Acceptance` condition
  - **PR body narrative** — the author-controlled section that sits above the workflow sections. Default heading set (`## Summary` / `## Changes` / `## Notes`) and prose, both in the conversation language. Projects may override the entire narrative — heading names, language, structure — via `.hq/pr.md` (see `pr` skill § Project Overrides and § PR Body Structure below for the 2-layer composition contract).
  - Free-form narrative text under `## Known Issues` entries
  - Any free-form section headings the author introduces (e.g., `### 背景`, `### Requirements`)

This rule applies to everything that generates Issue, plan-file, or PR content — the draft protocol, the execute protocol, the loop's Stage 5/7, and the `pr` skill.

## Project Overrides

Every hq command, skill, and agent MAY consult a project-local override file under `.hq/` and layer its content on top of the defaults defined in this rule file. Overrides **augment**, never **replace**, the workflow contract — a consumer's own Invariants (phases, gates, required outputs, structural invariants of generated artifacts such as the PR body) remain in force.

### Override files

| Override file | Consumed by | Typical content |
|---|---|---|
| `.hq/draft.md` | loop Stage 1 (draft protocol) | Domain-specific acceptance defaults (e.g. primary-tier preference and `## Manual Verification` routing for iOS / CLI / instruction-only projects), brainstorm hints, plan-split preferences |
| `.hq/start.md` | execute protocol (executor agent) | Project-specific execution nuance (commit / build / test notes the build phases should layer in) |
| `.hq/triage.md` | root J5 triage judgment | Project-specific lean cues for individual findings (judgment priors) |
| `.hq/loop.md` | `/hq:loop` (root agent) | `loop_max_iterations` / start-memory char-limit overrides, report style hints |
| `.hq/respond.md` | `/hq:respond` | Reply tone / language, project-specific dismissal criteria |
| `.hq/pr.md` | `pr` skill | PR body prose style, title conventions — scope-limited by the `pr` skill's own Invariants |
| `.hq/code-review.md` | `code-reviewer` agent | Project-specific review axes |
| `.hq/security-scan.md` | `security-scanner` agent | Project-specific security patterns |
| `.hq/integrity-check.md` | `integrity-checker` agent | Project-specific plan / diff reconciliation hints |
| `.hq/xcodebuild-config.md` | `xcodebuild-config` skill | Xcode build / run commands — managed by the skill itself (not hand-authored) |

Override files are optional. Absence means "apply defaults"; missing files are never errors. Each consumer resolves its override file by a literal `cat .hq/<name>.md` (or equivalent Read) at load time.

### Scope rules

- **Overrides augment, Invariants govern.** A consumer's Invariants are NOT overridable. If override content appears to contradict an Invariant, the Invariant wins; the consumer SHOULD flag the conflict to the user after execution so the override file can be corrected. Concrete example: `.hq/triage.md` MUST NOT contain category-level or severity-level disposition pre-decisions (e.g. "always escalate Critical", "leave all Low as-is") — dispositions are the root agent's per-FB judgment (J5), derived from the finding's actual content; an override supplies priors and lean cues, never decisions.
- **Local to the consuming command / skill / agent.** An override file affects only its own consumer. It cannot introduce new phases, gates, or mandatory checks that alter another command's behavior. Cross-command behavior changes go through this rule file, not through overrides.
- **Per-clone by default.** `.hq/` is included in `.gitignore` by `hq:bootstrap` Task 4, so override files are **per-clone / per-worktree** and NOT team-shared out of the box. Teams that want shared policy either (a) un-ignore specific override files and commit them, or (b) upstream the policy into this rule file. The former is experimental and risks per-member drift; the latter is the canonical path for team-wide rules.
- **Worktree propagation.** `plugin/v3/skills/worktree-setup/scripts/worktree-setup.sh` copies existing override files into a newly created worktree so the worktree inherits the same behavior without re-setup. New override file names introduced here MUST be added to that script's copy list.

### Override Language

Override content is free-form prose in the project's working language (typically the user's conversation language). No structural markers are required — the consumer reads the file body as guidance.

## Issue Hierarchy

```
With a parent hq:task:
  Milestone (GitHub built-in, optional)
    └── hq:task Issue  — requirement ("what")
          └── hq:plan file  — .hq/tasks/<branch-dir>/plan.md ("how"; local, gitignored)
                └── PR  (Refs #hq:task; final proposal — created after triage)
                      └── ← loop Stage 7 (user-confirmed) → hq:feedback Issue(s)  (Refs #PR)

Without a parent hq:task:
  hq:plan file  — .hq/tasks/<branch-dir>/plan.md; requirement captured in ## Why
    └── PR  (no Refs trailer; final proposal — created after triage)
          └── ← loop Stage 7 (user-confirmed) → hq:feedback Issue(s)  (Refs #PR)
```

- `hq:task` (requirement) and `hq:plan` (implementation plan) are separate artifacts (separation of concerns). The task is a GitHub Issue; the plan is a local work log whose essence (motivation / approach) reaches the durable record through the PR narrative.
- **`hq:task` is optional** — an `hq:plan` can be created without a parent `hq:task` by invoking `/hq:loop` with free text (no issue number). Use this when the requirement already lives in an external tracker, or for 1:1 cases where a separate requirement Issue is pure overhead. When no parent exists, the plan's `## Why` section becomes the sole source of truth for the requirement.
- Parent linkage lives in `context.md` `source:` (see `### Focus`), not in the plan body.
- PR uses `Refs #<hq:task>` to maintain a link to the requirement — only when the plan has a parent `hq:task`; omitted when absent. Merging a PR closes nothing automatically; `hq:task` closure is user-owned.
- **Traceability inheritance** — if the source `hq:task` has a milestone or project(s), all generated GitHub items (PR, `hq:feedback`) must inherit them via `--milestone` / `--project` flags. Exception: `hq:feedback` issues do NOT inherit milestones. When no parent `hq:task` exists, there is nothing to inherit from, so milestone / project are left unset.
- Labels are created lazily at first use:
  - `gh label create "hq:task" --description "HQ requirement (what to do)" --color "39FF14" 2>/dev/null || true`
  - `gh label create "hq:feedback" --description "HQ unresolved feedback" --color "FF073A" 2>/dev/null || true`
  - `gh label create "hq:doc" --description "HQ informational note / research findings (not a direct task)" --color "5319E7" 2>/dev/null || true`
  - `gh label create "hq:pr" --description "HQ PR associated with an hq:plan" --color "8A2BE2" 2>/dev/null || true`
  - `gh label create "hq:wip" --description "HQ work in progress — automation gate / drafting marker" --color "FFA500" 2>/dev/null || true`
  - `gh label create "hq:manual" --description "HQ PR marker — plan has ## Manual Verification items (reviewer verification required before merge)" --color "FFD700" 2>/dev/null || true`

## `hq:task`

An `hq:task` issue describes **what** needs to be done — the requirement, not the implementation. It is the trigger of the workflow and the input source for the loop's Stage 1 (which composes one or more `hq:plan` files from it).

The body is a **lightweight requirement document** primarily read by humans. Optimize for four properties; when they conflict, prioritize in this order:

1. **Sufficient** — carries enough information for Stage 1 to compose a `hq:plan` without re-soliciting requirements.
2. **Phase-split aware** — when the requirement clearly exceeds a single `hq:plan` grain, the split is acknowledged here.
3. **Volume-appropriate** — verbose task bodies dissolve reader attention; aim for a length the reader will actually read.
4. **Human-readable** — prose and structure favor the human reviewer, not the machine consumer.

The body's required sections are `## What` and `## Success Criteria` — the minimum a requirement document needs. `## Background`, `## Scope`, and `## Phase Split` are **optional** — emit each only when it carries information not already implied by `## What`. Emission rules:

- Angle-bracket `<placeholder>` tokens are substituted with real content.
- Optional sections are **omitted entirely** when they would carry no substantive content. Do not emit empty headings, `_None._`, or single-phase / boundary-self-evident placeholders.
- Section content follows the **Language** rule — content in the conversation language, headings in English.

```markdown
## Background *(optional)*
<Why now — the pain or opportunity that motivates the task.>

## What
<The requirement — desired end state in user or system terms, not in code-change terms.>

## Scope *(optional)*
**In:** <what this task covers>
**Out:** <what this task deliberately excludes>

## Success Criteria
- <observable conditions that, when satisfied, indicate the requirement is met>

## Phase Split *(optional)*
- **Phase 1**: <name and responsibility>
- **Phase 2**: <name and responsibility>
```

### `## Background` *(optional)*

Include when motivation is non-obvious, or when later readers (including the Stage 1 brainstorm) benefit from knowing why now. Avoid architectural rationale — that belongs in `hq:plan` `## Approach`. Skip on tasks whose `## What` already implies the motivation.

### `## What` *(required)*

The outcome statement. State the desired end state in user / system terms, not in code-change terms.

- ✓ *"Users can sign in with Google OAuth, with first-time sign-in auto-creating a profile row."*
- ✗ *"Add a new endpoint `POST /auth/google` that calls Google's OAuth API and writes to the `users` table."*

The first leaves the implementation path open for Stage 1 to design; the second pre-decides the implementation and constrains the plan space.

### `## Scope` *(optional)*

Use when scope boundaries are non-obvious, or when there is real risk of the brainstorm expanding into territory the requester does not want. Format: a two-bullet block — `**In:**` (what this task covers) and `**Out:**` (what this task deliberately excludes). Skip the section entirely when the boundary is self-evident from `## What`.

### `## Success Criteria` *(required)*

1–5 observable conditions, each one sentence. **Outcome-level** — what the user or system can do — not machine-checkable signals. The translation to a concrete `[primary]` signal happens in `hq:plan` `## Acceptance`.

- ✓ *"A new user can complete sign-in within 3 clicks from the landing page."*
- ✓ *"Existing sessions remain valid across the deployment."*
- ✗ *"`pnpm test` passes"* — that is a `hq:plan` acceptance, not a task-level success criterion.

When the requirement is too vague to yield any observable condition, the task is not ready — return to the brainstorm before creating the issue.

### `## Phase Split` *(optional)*

Emit only when the requirement naturally splits into multiple `hq:plan` grains. Trigger conditions:

- The change crosses **multiple architectural layers** (e.g., DB schema + API + UI), each carrying independent value.
- A **meaningful intermediate state exists** — a stopping point that delivers user-visible value or unblocks parallel work.
- **Verification boundaries differ** across the phases (e.g., a schema migration must reach production before UI exposure).

Each phase bullet states a name and a responsibility — **not** the editable surface or implementation steps. Surface and Plan items are the responsibility of the Stage 1 brainstorm, not of `hq:task` authoring. The phase split here is a recommendation, not a binding contract — Stage 1 may revise the boundary based on what investigation surfaces.

### Length guideline

`hq:task` length is bounded by **the reader's attention budget**, not a numeric line count. When the body grows long enough that a reviewer skims rather than reads, evaluate whether (a) the task should split into multiple tasks, (b) implementation detail has leaked from `hq:plan`, or (c) `## Background` is over-explaining. Numeric guidelines may emerge once enough `hq:task` examples accumulate; until then, volume judgment stays qualitative.

### Self-contained invariant

Every `hq:task` must:

- Be **self-contained** — readable as a standalone requirement document. Stage 1 should be able to produce a `hq:plan` from the body alone, supplemented only by the brainstorm conversation.
- Define **`## What`** and **`## Success Criteria`** at minimum. `## Background`, `## Scope`, and `## Phase Split` are optional — include each when it carries information not already implied by `## What`.
- Stay **outcome-level** — implementation paths belong in `hq:plan`, not here.
- Follow the **Language** rule — content in the conversation language, headings in English.

## `hq:plan`

An `hq:plan` is the implementation plan that drives work on a branch. It is a **local file** at `.hq/tasks/<branch-dir>/plan.md`, created at loop Stage 1; its first line is a `# <type>(plan): <title>` heading, followed by the body specified here. The plan file IS the source of truth for what needs to be done and how completion is verified — the loop's internal work log. It is **not embedded in the PR**: the reviewer-facing record is the Stage 5 narrative (motivation / approach / deviations), and the file itself travels with the task folder to `done/` / `canceled/` on archive.

**Two readers, one body.** The same body serves two audiences, and the readability investment is split deliberately so it stays complete-but-not-bloated for both:

- **Human reviewer** (including a developer unfamiliar with this area) reads `## Why` + `## Approach` to decide whether to approve. These two sections carry the **reader self-sufficiency** bar below: the reader should grasp the problem and the chosen mechanism from them alone, without spelunking the diff. When the design is structural, a figure / snippet is the readability tool — not optional decoration.
- **The executor / root judgments / `integrity-checker`** consume `## Editable surface` / `## Plan` / `## Acceptance` as the agent fence. These stay terse (≤1行 per entry / item) — that compression is a functional requirement, not a stylistic one. Do **not** spend prose on them.

Figures and intent snippets live in `## Approach` and are **excluded from its sentence count** (see below), so the readability investment in Why/Approach never fights the volume bounds.

The `hq:plan` body follows a **flat 5-section structure** — `## Why` + `## Approach` + `## Editable surface` + `## Plan` + `## Acceptance` — plus an optional `## Manual Verification` section appended when the plan has reviewer-owned checks. Emission rules:

- Angle-bracket `<placeholder>` tokens are substituted with real content.
- Parent-task linkage is NOT part of the body — it lives in `context.md` `source:` (see `### Focus`).
- Optional sub-content (figure / sample code in `## Approach`) is omitted entirely when empty. Never write `_None._` / `Not applicable` / padded prose as filler.
- The `## Manual Verification` section is emitted only when the plan has reviewer-owned checks; omit the heading entirely when every acceptance signal is executor-executable.

```markdown
# <type>(plan): <implementation approach>

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
- [ ] [auto] [primary] <strongest executor-executable signal — see specificity hierarchy>
- [ ] [auto] <secondary executor-executable check>

## Manual Verification
- [ ] [manual] <reviewer-owned check — a runtime / subjective outcome (one named observable), or a deterministic check the project defers to the reviewer>
```

### `## Why` *(required)*

The pain and why now. Gives the reader the "what problem is this solving" answer in seconds.

**Content rules**:

- Required: (a) the pain or opportunity, (b) why now / what triggers this plan.
- **Reader self-sufficiency**: a developer unfamiliar with this area should be able to grasp *what problem this solves* from `## Why` alone. If understanding the pain requires already knowing the code, the framing is too thin — name the concrete failure / friction, not an abstract gesture at it.
- Anti-content (move to `## Approach` if present): file:line citations, error code enumerations, design judgment, comparison of alternatives, implementation hints.
- Volume guidance: a few sentences. The test is not a sentence count but whether every sentence answers (a) or (b) — if it doesn't, it is content type leak and belongs elsewhere.

### `## Approach` *(required)*

The chosen design + at least one rejected alternative with reason. This section is the single load-bearing field for "why this implementation" — generic phrasing here is the failure mode that wastes PR-reviewer cycles.

**Content rules**:

- Required: (a) chosen design summary, (b) at least one rejected alternative named and dismissed with a one-line reason. "We considered alternatives" without naming any is not enough.
- **Reader self-sufficiency**: `## Approach` must let an unfamiliar reader understand the *mechanism* of the change, not merely *name* the decision. "Adopt single-flight" is a label; the reader still needs to see how the requests collapse. Close that gap here — that is the whole point of the section.
- **Figure expected for structural changes** (not optional decoration): when the chosen design is structural — a flow, a state transition, a before/after relationship, or a control-path change — render the key point as a Mermaid / ASCII diagram instead of compressing it into prose. GitHub renders Mermaid natively inside Issue bodies. Prose alone for a structural change is the readability failure this section exists to prevent. A figure is only skippable when the design genuinely has no structural shape to draw (a pure value / wording / threshold change).
- **Intent snippet** (≤ 10 lines): when the shape of the change is faster to read as code than as prose, include an intent-conveying snippet. Intent only — not a copy of the eventual implementation.
- Anti-content (move out): full implementation listings, complete signature enumerations, attribute-by-attribute spec dumps. Implementation detail belongs in the actual code, not in the plan. A figure / snippet that crosses into a full spec dump is anti-content even though figures are otherwise encouraged.
- Volume guidance: prose ≤ 5 sentences. **Figures and intent snippets are excluded from the count** — they exist to *raise* readability without spending the prose budget, so reaching for one never trades against the sentence bound. If more independent decisions need to be articulated, see **plan-split signal** below.

**plan-split signal** — when `## Approach` is forced to enumerate multiple **independent** decisions, the plan is probably trying to do too much. Judge by **coupling**, not raw count:

- **3 parallel decisions in coupled vertical features** (e.g., UI / API / data model for a single feature) → **acceptable in one plan** — splitting would create coordinated multi-PR work which is usually worse than a single cohesive PR.
- **4+ parallel decisions** → stop and reconsider — is this really one feature, or has scope crept?
- **Even with 3 or fewer decisions**, if the decisions could be **released independently** (one can ship without the others), split into separate `hq:plan`s (e.g., "logging revamp" + "error screen addition" living together → split).

The count is a secondary warning indicator; the load-bearing criterion is whether the decisions are couplings-of-one-feature or independent shippables.

### `## Editable surface` *(required)*

Files or symbols this plan may modify. The single positive set — anything not on this list is **implicit out of scope**.

**Format**: one bullet per entry. Each entry: `` `<path / symbol>` — `[<tag>]` <≤1行 note> ``. The `<≤1行 note>` is mandatory and describes the concrete change at that surface.

**Inline tags (closed set)**:

- **`[新規]`** — a new surface is introduced (new function / field / command / config key / section / label / file path). Boundary: a new section added inside an existing file is `[新規]` (the *section* is the new surface), not `[改修]`.
- **`[改修]`** — an existing surface's contract changes (arguments, return shape, emission rules, accepted values). The note must indicate what callers need to react to.
- **`[削除]`** — an existing surface is removed.
- **`[silent-break]`** — the surface's signature is stable but its semantics shift, potentially breaking existing callers silently. The highest-risk tag — name the breakage mechanism in the note. **Default to `[silent-break]` when in doubt over `[改修]`**: the worst case for `[改修]` is verbose, the worst case for `[silent-break]` is callers continuing to compile / run while returning subtly different results.

**Volume bound (strict)**: each entry's note is ≤ 1 line. Method signatures, attribute lists, complete type annotations, exact pattern specifications are **anti-content** — they belong in the actual code, not here. If a note overflows, either split the entry (different concerns → different entries) or move detail to `## Approach`.

**Boundary scope** — this list IS the **AI agent fence**:

- The `integrity-checker` agent flags any diff that touches a file / symbol not on this list as `Diff-but-undeclared` — scope creep hiding in the implementation.
- Every diff hunk must trace back to a `## Editable surface` entry; entries without a corresponding diff are flagged as `Declared-but-missing`.

**Boundary expansion protocol** — when implementation reveals that a stack-natural extension requires touching a surface not on this list (canonical examples: Swift Concurrency `async` propagation that drags `await` annotation across an actor boundary, a unit test file co-located with a production surface that gained a new public symbol):

1. Add the new entry to `## Editable surface` with its tag and note **before** touching it.
2. Note the rationale in `## Approach` (one line is enough: "X also required because Y").
3. Then proceed with the modification.

This converts the boundary from a rigid fence into an explicit expansion channel — the Karpathy-loop fence invariant is preserved, while the failure mode of mechanically rejecting stack-correct implementations is eliminated.

### `## Plan` *(required)*

Implementation steps as a checkbox list. Every item must be `[x]` before PR creation.

**Format**: `` - [ ] <step description — ≤1行> *(consumer: <name>)* `` — the `*(consumer: <name>)*` suffix is appended when the step performs a coordinated update on a named downstream consumer (docs, tests, templates, README, distribution artifacts, other commands / skills / agents in this plugin). The suffix is the single mechanism for declaring "this step touches consumer X for coordinated update."

**Granularity — single meaningful commit unit.** Each item is something that reads as one independent change in `git log` afterward:

- If two consecutive items would edit the same file in the same editing session, they are **one item**, not two.
- If an item would produce a half-working intermediate state, it is split wrong — merge upward with its neighbor.
- 1-item plans are valid (atomic change).
- No numeric cap on item count. Motive-driven bloat — adding items because "while we're at it" rather than because the change genuinely needs them — is not bounded by a count ceiling; it is challenged by the Stage 1 Simplicity gatekeeper (J2) before the plan is composed. When a brainstorm produces a naturally broad scope, Stage 1 raises the question of whether it should split into multiple plans rather than being padded as one.

**Volume bound (strict)**: ≤ 1 line per item. Implementation-level signatures, method names, attribute lists are anti-content — they belong in the actual code.

**Consumer coverage check** — the draft protocol enforces a coverage check before emitting the plan: every Plan item carrying a `(consumer: <name>)` suffix must name a consumer that is consistent with the change described by the step. The `integrity-checker` agent reconciles declared consumers against the diff as a second net — a `(consumer: <name>)` suffix whose consumer does not appear in the diff is flagged as `Declared-but-missing`.

### `## Acceptance` *(executor-owned)*

`## Acceptance` holds the completion criteria **the executor verifies autonomously** (execute-protocol Phase 5). Every item is `[auto]` — a signal the executor can run in this project — and exactly one carries `[primary]`. Checks a human must perform live in `## Manual Verification` below; **nothing the executor cannot run belongs here** (this is the load-bearing rule: the build's evaluation criteria never include what it structurally cannot do).

- **`[auto]`** — Claude can verify autonomously: unit / integration tests, type checks, builds, shell / CLI commands, API calls, file / directory / content checks, **and browser automation via `/hq:e2e-web` (Playwright)** — navigation, URL assertions, element / text presence, form submit flows, DOM state. Executed during execute-protocol Phase 5. **"It happens in a browser" alone does NOT justify moving a check to `## Manual Verification`** — `/hq:e2e-web` drives browser UI deterministically.
- **`[primary]`** *(role marker)* — **exactly one** `## Acceptance` item per plan MUST carry `[primary]`, and it is **always `[auto]`**. It is the single executor-executable pass/fail signal the plan is judged by — and the build's motivation to actually reach the target. All other items are secondary (no explicit role marker). A `[primary]` the executor cannot run is a drafting defect: the real outcome it reached for belongs in `## Manual Verification`, and `[primary]` moves to the strongest signal the executor *can* run per the hierarchy below.

**Primary specificity hierarchy** — the `[primary]` must be the **strongest assertion about the change's own correctness that the executor can run in this project**. Pick the highest achievable tier; landing on a lower tier for a change that has real logic is a drafting smell to confront, not a default to settle for:

| Tier | Signal | When it applies |
|---|---|---|
| **1 Behavioral** | an executable test asserting the changed logic produces its intended result (`xcodebuild test` / unit / integration) | the project lets the executor run tests |
| **2 Anchored-semantic** | the executor cross-checks the diff against a **named external artifact** (spec / contract / reference) — a grounded semantic assertion | an external ground truth exists to check against |
| **3 Structural** | a grep / file assertion that the change reached its exact target state (all N targets in new form + 0 residual, new surface reachable) | success IS a structural fact (refactors, surface add / remove) |
| **4 Bare build** | compilation succeeds | rejected as `[primary]` unless the change is genuinely compile-only |

A **self-judged** semantic check with no external anchor — Claude reading its own diff and declaring it correct — is **not** a valid `[primary]`: it is not reproducible and is weaker than a grep. Semantic breakage is caught by the root's build review (J3) and the Stage 3 reviewers, so the primary need not carry that load alone.

**Choosing primary** — the `[primary]` answers *"if this single check passes, has the build done its job?"* Concrete and reproducible (commit count, file / string presence, API return code, URL transition, named artifact) — never an abstract phrase ("plan works", "app launches"). When the change's true outcome is only human-observable (native mobile UI, subjective UX), `[primary]` stays on the strongest executor-executable tier above and the human outcome goes to `## Manual Verification` — do **not** inflate a lazy `[auto]` into a fake outcome signal.

Examples:

| Check | Section / Markers | Why |
|---|---|---|
| Final commit count ≤ 10 and each `## Plan` item appears in a commit subject | `## Acceptance` `[auto] [primary]` | Tier 3 structural — single machine-checkable signal |
| `APIClientTests` rescue-branch test green via `xcodebuild test` | `## Acceptance` `[auto] [primary]` | Tier 1 behavioral — project lets the executor run tests |
| Error-code mapping matches server spec (DocBase #4097556) | `## Acceptance` `[auto] [primary]` | Tier 2 anchored-semantic — grounded against a named artifact |
| `pnpm test` passes | `## Acceptance` `[auto]` | Secondary — necessary but not sufficient |
| Click "Save" → page URL becomes `/issues/{id}` | `## Acceptance` `[auto]` | Playwright URL assertion |
| Back gesture dismisses modal with native iOS animation on iPhone 16 simulator | `## Manual Verification` `[manual]` | Runtime outcome — reviewer-owned, no `[primary]` |
| Run `RefreshTokenCoordinatorTests` in Xcode → green | `## Manual Verification` `[manual]` | Deterministic, but this project defers test execution to the reviewer |

Each item is a single concrete signal — not a vague goal.

### `## Manual Verification` *(reviewer-owned; optional)*

The checks a human performs at PR review — everything the executor structurally cannot, or by project policy does not, run. This section is **omitted entirely** when every acceptance signal is executor-executable. It never carries `[primary]`: the primary is the build's motivation and lives in `## Acceptance`.

Items land here routed by **who verifies**, not by what kind of signal. Two kinds:

- **Runtime / subjective outcome** — native mobile UI behavior, animation feel, visual design, physical-device gestures, multi-session scenarios outside Playwright's reach. Each item MUST name exactly one concrete observable target (UI state name, interaction terminus, visual / sound target, named artifact); abstract phrases ("works correctly", "feature complete", "app launches") are rejected.
- **Deterministic check the project defers** — e.g. a unit-test suite that `xcodebuild test` could run but the project policy hands to the reviewer. Deterministic in principle, but the executor does not run it in this project, so the reviewer owns it. (When the project *does* allow it, it is `[auto]` and belongs in `## Acceptance` — often as the Tier 1 primary.)

**Format**: `` - [ ] [manual] <one named observable or deferred check> ``. Loop Stage 5 carries these verbatim into the PR body's `## Manual Verification` section; the `hq:manual` label marks the PR as needing reviewer verification before merge.

### Self-contained invariant

Every `hq:plan` must:

- Be **self-contained** — readable as a standalone plan document. It survives session clears (it lives on disk, and in the PR body from PR creation onward), so it must not depend on conversation state.
- Define **`## Why`** (pain + why now), **`## Approach`** (chosen design + ≥1 rejected alternative with reason), **`## Editable surface`** (positive scope set with inline tags `[新規]` / `[改修]` / `[削除]` / `[silent-break]`), **`## Plan`** (implementation steps, single-commit-grain), and **`## Acceptance`** (executor-executable completion criteria, including exactly one `[auto] [primary]` item per the specificity hierarchy) — plus **`## Manual Verification`** (reviewer-owned runtime / deferred checks, no `[primary]`) when such checks exist.
- Follow the **Language** rule above — content in the conversation language, markers and prescribed headings in English.
- Keep Acceptance checks atomic and verifiable — each `[auto]` item maps to a single concrete signal (pass/fail).

### Focus

**Focus** is a pointer to the `hq:plan` currently driving work. It is stored in two places:

1. **`.hq/tasks/<branch-dir>/context.md`** — deterministic file (branch name: `/` → `-`). Agents and skills resolve focus from this file; the plan itself is the sibling file `plan.md` in the same directory.
2. **Memory** — a project-type memory entry for cross-session awareness. Lets new sessions know what was in progress.

**context.md format** (frontmatter YAML — no free-text body). `source` and `gh.task` are present only when the plan has a parent `hq:task`; `base_branch` is present only once the execute protocol has created the git branch (see field descriptions).

```yaml
---
source: <hq:task issue number>
branch: <original branch name with slashes intact, e.g., feat/oauth-login>
base_branch: <branch this feature branch was created from, e.g., main / develop / refactor/parent-feature>
gh:
  task: .hq/tasks/<branch-dir>/gh/task.json
---
```

- `source` — **optional**. The `hq:task` issue number this plan implements. Present when the plan has a parent `hq:task` (the normal case); **omitted when no parent exists** (plans whose Stage 1 input had no `hq:task` number). This is the single carrier of parent linkage — the plan body has no `Parent:` line.
- `branch` — **MUST**. The original git branch name (with slashes), derived at Stage 1 from the plan title. Lets tooling check out the correct branch given a plan query (the directory name has `/` → `-` transformation which is not reliably invertible).
- `base_branch` — **MUST once the git branch exists**. The branch this feature branch was created from, appended by execute-protocol Phase 3 via `git symbolic-ref --short HEAD` immediately before `git checkout -b`. Absent between Stage 1 (which writes `context.md` without it) and the first build. This is the **per-branch authoritative base record** consumed by the Base branch resolution chain in § Branch Rules — it survives global `.hq/settings.json` drift across worktrees / stacked PRs (the failure mode that motivates this field). When absent, consumers fall back to the next step in the resolution chain.
- `gh` — path to the local `hq:task` snapshot (`gh/task.json`, written by execute-protocol Phase 3). Present only when `source` is set.

**Lifecycle**:

- **At Stage 1** (draft protocol): create `.hq/tasks/<branch-dir>/` with `plan.md` and `context.md` (`source` when a parent exists, `branch`).
- **At first build** (execute-protocol Phase 3): append `base_branch:`, write `gh/task.json` (when a parent exists). The root saves focus info to memory (project type) — branch name, plus the source number when a parent exists.
- **On status query**: read `.hq/tasks/<branch-dir>/context.md` → read the plan body from `.hq/tasks/<branch-dir>/plan.md` → report status.
- **On completion**: when a PR is created and all Plan items + Acceptance `[auto]` items are checked, update your memory to indicate no active task. The `context.md` and `plan.md` files are left in place — they travel with the task folder until `/hq:archive` moves it to either `.hq/tasks/done/` (PR merged) or `.hq/tasks/canceled/` (PR closed without merging, via `/hq:archive cancel`).

### Focus Resolution

When the user gives a **vague instruction** (e.g., "the auth task", "the oauth plan"), resolve the focus by searching in order:

1. **context.md** — check `.hq/tasks/<current-branch-dir>/context.md` for the current branch. If it exists, use it and confirm with the user: "Restored focus: branch=X, source=#Y. Correct?" (drop the `source=` part when the plan has no parent `hq:task`). If the user says no, continue to the steps below.
2. **memory** — check your memory for active focus info.
3. **search** — run `bash find-plan.sh <keyword>` (scans `.hq/tasks/*/context.md` `branch:` fields; exact match wins, unique substring accepted).

If exactly one match: set focus automatically. If multiple matches (`find-plan.sh` exit 5): show candidates and ask the user to choose. If no match: ask the user to specify the branch.

**NOTE**: `/hq:loop` Stage 0 does **NOT** use this resolution order. It resolves the work branch via `find-plan.sh` from its argument, or falls back to the current branch (see `commands/loop.md § Stage 0`).

## Simplicity Criterion

An `hq:plan` must survive a benefit/complexity tradeoff check before it is composed. The canonical formulation, from `autoresearch/program.md` and referenced in `hq:doc #40`:

> All else being equal, simpler is better. A small improvement that adds ugly complexity is not worth it. A 0.001 val_bpb improvement that adds 20 lines of hacky code? Probably not worth it. An improvement of ~0 but much simpler code? Keep.

`hq:doc #40` frames this as a **limit of formal plan constraints**: rules like the `## Editable surface` inline-tag set, granularity guidance, or a hypothetical `## Plan` item count cap stop the *result* of motive-driven bloat (many small "while-we're-at-it" additions) but not the *motive* itself. The motive has to be challenged during drafting, where a proposal is still malleable.

This limit is **mitigated** by the Stage 1 Simplicity gatekeeper (J2 — draft-protocol Phase 2), which challenges reuse vs new-build, minimum-solution comparison, and spread cost before the plan is composed. Pushback is one-round (the root raises the concern, the user decides, the tradeoff — if accepted — is recorded in `## Approach`). Plans reaching the build stage have already passed this gate.

Consequences for plan structure:

- `## Plan` has **no numeric item cap**. Formal caps target the result (how many items) rather than the motive (why each was added); they were deprecated once the gatekeeper role was introduced. The quality rules on `## Plan` (single meaningful commit unit, same-file consecutive items merge, no half-working intermediate state) remain because they are about the *grain* of each item, not its *necessity*.
- Naturally broad scopes should be split into multiple `hq:plan`s at the gatekeeper stage rather than padded into one. Stage 1 raises this split decision explicitly when the brainstorm produces a large scope (see `## hq:plan` § Approach § plan-split signal for the coupling-based criterion).
- The `## Editable surface` inline-tag set and `[auto] [primary]` 1-per-plan rule are retained as formal constraints; they pass the Simplicity criterion test by being low-burden and tightly targeted at specific gaming patterns (undeclared surface change, success-signal dissolution).

## Loop

`/hq:loop` is the **single entry point** of the pipeline; the model running it — the **root agent** — is the orchestrator and the judge. Semantic decisions that cannot be settled deterministically are the root's (judgment points **J1–J8**, each with a written decision record under `.hq/tasks/<branch-dir>/reports/`); deterministic rails (scripts, structural gates, the regression gate) stay deterministic; subagents gather evidence and execute, never making final calls. Spec: `plugin/v3/commands/loop.md`.

```
Stage 0 RESUME  (root, J1)          state detection → entry stage
Stage 1 PLAN    (root+user, J2)     draft-protocol inline → plan.md; gate: go / stop / pushback
Stage 2 BUILD   (executor agent)    execute-protocol: fresh | fix-directive → commits + acceptance + FBs
Stage 3 REVIEW  (root J3, J4)       build acceptance review → reviewer agents in parallel → FBs
Stage 4 TRIAGE  (root J5; J8 exit)  per-FB disposition on local FBs (fix / plan / accept / escalate-candidate)
   J8: converged → micro-fix + integrity-checker re-run → Stage 5
       continue  → Stage 2 re-entry (budget-bounded)
       diverging → block: plan-revision proposal to the user, or safe cancel (archive cancel route)
Stage 5 SHIP    (root J6)           PR created as the FINAL PROPOSAL — narrative body via pr skill
Stage 6 RETRO   (retro-distiller)   retrospective + start-memory distillation
Stage 7 REPORT  (root+user, J7)     judgment audit trail + feedback candidates → user-confirmed hq:feedback
```

Invariants:

- **PR-last** — triage precedes PR creation; the PR's `## Known Issues` holds only post-triage residual (accepted limitations / escalation status).
- **Three user interaction systems**: the Stage 1 gate, root-initiated consults (J3 / J5 / J8 — including the J8 plan-revision / safe-cancel gate), and the Stage 7 feedback confirmation. All non-skippable.
- **`hq:feedback` creation is user-gated** at Stage 7 (and `/hq:respond` for external review comments) — the root never creates one alone.
- **J8 is the loop control** — semantic convergence judgment; `loop_max_iterations` (default 2) is only the runaway backstop.
- `/hq:respond` and `/hq:archive` remain standalone post-PR tools.

## PR Body Structure

The PR is created at loop Stage 5 as the **final proposal** — after triage. Its body serves the **human reviewer**: motivation, approach (including deviations from the plan discovered during build), changes. The plan file is a local work artifact and is **never embedded**. Two layers:

1. **Narrative layer** — author-controlled via `.hq/pr.md` (headings, language, structure, prose). Default: `## Summary` (what + why) / `## Approach` (chosen design, named rejected alternatives, build-time deviations with reasons) / `## Changes`, in the conversation language.
2. **Workflow sections layer** — English-fixed, injected at creation:

```markdown
## Manual Verification            <!-- only when the plan has [manual] items -->
- [ ] [manual] <item, verbatim from the plan>

## Known Issues                   <!-- only when triaged residual exists -->
- [<Severity>] [<origin>] <title> — accepted: <reason>
- [<Severity>] [<origin>] <title> — escalation pending user confirmation

---
Refs #<hq:task>                   <!-- only when the plan has a parent hq:task -->
```

- **`## Manual Verification`** — the plan's reviewer-owned checks, verbatim; the PR carries the `hq:manual` label when present.
- **`## Known Issues`** — **post-triage residual only**: limitations the root accepted at J5 (with reasons) and escalation candidates awaiting Stage 7 confirmation. Stage 7 finalizes pending lines in one `gh pr edit`: created → `- escalated: #<N>`; declined → `— accepted: escalation declined by user`. There is no "process later" backlog and no triage-summary header — triage already happened.
- If a section's trigger is absent, omit it entirely.

### Invariants (NOT overridable by `.hq/pr.md`)

- `hq:pr` label on every PR; `hq:manual` label whenever `## Manual Verification` is present.
- `## Manual Verification` / `## Known Issues` headings, content passed by the caller unmodified.
- `Refs #<hq:task>` trailer when a parent task exists; omitted otherwise.
- Milestone / project inheritance from the parent `hq:task` when present.
- **No plan embed** — the plan checklist never appears in the PR body.

`.hq/pr.md` MAY redefine the narrative layer in full (see `pr` skill § Override scope); it MUST NOT suppress, rename, or reformat the workflow layer.

## Before Edit

Before modifying an existing surface, take **one bounded read pass** over the context the edit depends on — the pre-edit counterpart to the post-edit § Before Commit blast-radius self-check. The two are complementary, not redundant: this pass prevents a contradiction from being written in the first place (it fires *before* the edit); the blast-radius self-check detects stale references already written (it fires *after*). One pass per surface, not a defect-exhaustion loop:

1. **The whole target surface** — read the entire function / section / config block being changed end-to-end, not just the lines at the edit point, so the change fits the surface's existing shape and invariants.
2. **Same-concept occurrences in the same file + adjacent context** — scan the file for the concept being edited appearing elsewhere (the same key / heading / marker / helper / branch) and read the lines immediately around the edit, so parallel occurrences stay consistent and neighbouring logic is not broken.
3. **The change target's contract + nearest callers / consumers** — for code: confirm the exact signature, arguments, and return shape; for a doc / procedure surface: confirm the section's prescribed fields, accepted values, markers, and citation contract (which commands / rules cite it by `§ <section>`). Then read the closest call sites or consumer files that depend on the target, so the edit matches the contract its callers / consumers expect.

This is a read discipline, not a fix loop: when the three reads surface no conflict, proceed straight to the edit. It exists to test the hypothesis that the dominant defect-prevention lever at implementation time is reading the surrounding code before writing. That hypothesis is tracked as the `better-pre-read` entry in `## Retrospective` § `prevention_lever`, whose accumulated distribution across runs is the evidence that will confirm or revise it.

## Before Commit

1. Run `format` command (see Commands table in CLAUDE.md)
2. Verify `build` command passes
3. **Blast-radius self-check** — one pass per unit, not a defect-exhaustion loop:
   - For each **named thing** (symbol / heading / marker / config key / enum case / label / error code) this change introduces, renames, or shifts the semantics of, `grep` the repo and update every stale reference. LSP find-references is an equivalent substitute where available.
   - For each procedure (gate / pipeline / phased doc / state machine) this change touches, re-read it top-to-bottom once in **flow order** and verify each step's preconditions still hold against the new state.

## Local Plan Principle

The plan file `.hq/tasks/<branch-dir>/plan.md` is the **single source of truth** for the plan body. There is no GitHub copy to synchronize during execution — all reads and writes go straight to the local file. The plan is the loop's internal work log: it is NOT embedded in the PR (the Stage 5 narrative carries its essence to the reviewer), and it is archived with the task folder by `/hq:archive`.

### Task-folder files

```
.hq/tasks/<branch-dir>/plan.md         # the hq:plan — single source of truth
.hq/tasks/<branch-dir>/context.md      # focus frontmatter (see § Focus)
.hq/tasks/<branch-dir>/gh/task.json    # read-only snapshot of hq:task (only when a parent exists)
```

### Helper scripts

All located under `${CLAUDE_PLUGIN_ROOT}/plugin/v3/scripts/`:

- **`plan-check-item.sh <pattern>`** — toggle a single `[ ]` checkbox to `[x]` in the current branch's `plan.md`, matching by fixed substring. Exit 3 = no match, exit 4 = ambiguous, already-checked = idempotent no-op.
- **`find-plan.sh <branch-or-substring>`** — scan `.hq/tasks/*/context.md` `branch:` fields for a match (exact wins; unique substring accepted), print the branch name. Exit 1 = not found, exit 5 = ambiguous.
- **`read-context.sh`** — print the current branch's `context.md`, or `none`.

**Rule**: individual checkbox toggles during execution call `plan-check-item.sh`. Structural plan edits (e.g., a J5 plan-append disposition, a J8-approved plan revision) edit `plan.md` directly.

## Feedback Loop

Verification and review stages output feedback files (FB) to `.hq/tasks/<branch-dir>/feedbacks/`. FBs are **triaged by the root agent before the PR exists** (loop Stage 4, judgment J5) — the PR's `## Known Issues` carries only the triaged residual.

### FB Output Rules (for anything that generates FB files)

**Directory** — branch name: replace `/` with `-` (e.g., `feat/m9-wiki` → `feat-m9-wiki`).

```
.hq/tasks/<branch-dir>/feedbacks/              # pending — awaiting J5 triage
.hq/tasks/<branch-dir>/feedbacks/done/         # triaged — disposition recorded in the file
.hq/tasks/<branch-dir>/feedbacks/screenshots/  # evidence (optional)
```

**Numbering** — check existing files in `feedbacks/` and `feedbacks/done/` for the next number. Format: `FB001.md` (zero-padded to 3).

**Format** — per [feedback.md](feedback.md). `branch` and `source` frontmatter from `.hq/tasks/<branch-dir>/context.md`.

**`covers_acceptance` (optional, soft convention)** — populate in execute-protocol Phase 4/5-origin FBs (1:1 with an acceptance item by construction); leave unset on review-origin FBs. No script enforces it — it keeps the audit trail linear.

### FB origins

- **Execute protocol Phase 4** — continue-reports on blocked / ambiguous / twice-failed steps.
- **Execute protocol Phase 5** — `[auto]` checks that exhausted the retry cap (`[x]`-toggled anyway; the FB tracks the failure — `[primary]` failures carry a `[primary failure]` prefix).
- **Root build review (J3)** — minor gaps the root records itself.
- **Stage 3 reviewer agents** — `code-reviewer` / `integrity-checker` FB files; `security-scanner` scan-report findings the root deems actionable are synthesized into FBs (`skill: /security-scan`, default severity Medium).

Review is **pure review** — no agent fixes anything. Every fix decision is the root's (J5), and every fix executes through the executor's fix-directive mode under the regression gate.

### FB lifecycle

1. FB lands in `feedbacks/` (pending).
2. Loop Stage 4: the root judges it (J5 — see `commands/loop.md § Triage judgment criteria`): **fix** (→ fix-directive queue) / **plan** (→ `## Plan` append) / **accept** (→ PR `## Known Issues` residual) / **escalate candidate** (→ Stage 7 user confirmation).
3. The file moves to `feedbacks/done/` with a `disposition: <fix|plan|accept|escalate> — <reason>` line appended. This move happens at triage time — there is no other path to `done/`.
4. `hq:feedback` Issues are created only at Stage 7 from user-selected candidates (`Refs #<PR>`), and by `/hq:respond` for external review comments.

`feedbacks/` should be empty of pending files after Stage 4; `/hq:archive` defensively checks this.

## Retrospective

Per-run reflective analysis written by the **`retro-distiller` agent** (loop Stage 6, after the PR exists) to `.hq/retro/<branch-dir>.md`. The distiller is deliberately a different party from the root that made the run's judgments — hindsight without self-grading. Axes: *was each finding a valid detection, was it preventable at implementation time* AND *do the root's judgment calls (J3 / J4 / J5 / J8) read sound given what later surfaced*.

`.hq/retro/` follows `.hq/` semantics: gitignored, per-clone, branch-local (`<branch-dir>` = branch with `/` → `-`; one plan per branch keys the artifact). One file per run; re-runs overwrite (latest snapshot, not history).

### Fixed schema (four sections, in order — the structure itself is the acceptance gate)

1. **`## Run Summary`** — facts only: plan title / branch / timestamp (UTC ISO 8601); `phase-timing.sh summary` output verbatim (slot → stage mapping: `commands/loop.md § Timing slots`; any slot 4–8 `(no data)` is a workflow defect `## Reflection` must call out); total commits (`git rev-list --count <base>..HEAD`); J3 verdicts; J4 launched / skipped; per-agent FB counts + severity breakdown; disposition counts (fix / plan / accept / escalate); iterations used and J8 outcomes.
2. **`## Judgment Review`** — one subsection per judgment class that fired (`### J3 Build Review` / `### J4 Reviewer Selection` / `### J5 Triage Dispositions` / `### J8 Convergence`): quote the decision record's **Decision rationale**, then a `**Hindsight**:` line (≤ 2 sentences) with concrete citations — over-fixing, under-escalation, a divergence signal read late, an over-launched reviewer. Missing record → `(decision record not found — judgment review unavailable)`.
3. **`## FB Analysis`** — one entry per FB in `feedbacks/done/`: a YAML fence with the 3 closed-enum axes below plus a `disposition:` line, then `**Notes**` (≤ 2 sentences, factual). Zero FBs → literal body `(no FBs to analyze)` — never omit the section.
4. **`## Reflection`** — ≤ 8 sentences; at least one concrete pattern cited across FB Analysis / Judgment Review / timing. Self-praise without a pattern citation is the failure mode this section guards against.

### Per-FB YAML axes (closed enumerations)

| Axis | Values | Meaning |
|---|---|---|
| `detection_validity` | `valid` / `invalid` / `borderline` | Was the detection sound? |
| `preventable_at_implementation` | `yes` / `no` / `partial` | Could the build have caught it (Phase 4 discipline) instead of review? |
| `prevention_lever` | `stricter-acceptance` / `smaller-commit-grain` / `reuse-existing` / `better-pre-read` / `plan-discipline` / `n/a` | If preventable, by what workflow change? `n/a` when not preventable or the detection was invalid. |

Plus `disposition: <fix|plan|accept|escalate>` (from the FB file's appended line). Adding axis values or keys is a deliberate change to this rule file — runtime composition MUST NOT invent them.

### Distillation (Stage 6 Step 2) — closing the active loop

The distiller consumes its own retro and re-distills **`.hq/start-memory.md`** — a char-bounded compressed instruction of repo-specific, forward-looking cautions ("next time in this repo, do X"), covering both implementation lessons (read at execute-protocol Phase 4 entry) and judgment lessons (read by the root at J3 / J4 / J5). Contract:

- **Char budget = 1500** (hard cap; tune via `.hq/loop.md`). Over budget → merge / generalize / evict until it fits. The cap is the curation mechanism.
- **Repo-specific only** — learnings that would change the plugin itself are returned to the loop as `plugin_level_findings`, never distilled into start-memory.
- User corrections MAY be appended to the file directly; the next distillation folds them in.
- No distillable learning → file unchanged (valid outcome).

Reading retro learnings back into Stage 1 (Simplicity-gate priors) remains future work — when added, it ships as its own plan.
