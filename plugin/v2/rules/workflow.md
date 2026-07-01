# Workflow

## Prerequisites

- **`gh` CLI** must be authenticated: `gh auth status` must succeed
- All issue operations (`gh issue view`, `gh issue create`, `gh issue list`, `gh issue close`) require this

## Branch Rules

- **Never work directly on base branches** (`main`, `develop*`) — always create a feature branch
- **Base branch resolution** (used by all skills): `.hq/tasks/<branch-dir>/context.md` `base_branch:` → `.hq/settings.json` `base_branch` → `git symbolic-ref refs/remotes/origin/HEAD` → `"main"`
  - `.hq/tasks/<branch-dir>/context.md` `base_branch:` is the **per-branch authoritative record** — written at branch creation time (`/hq:start` Phase 3) from `git symbolic-ref --short HEAD` immediately before `git checkout -b`. It captures the actual divergence point and survives global setting drift across worktrees / stacked PRs.
  - `.hq/settings.json` is the **project-wide default** — used when no `context.md` exists for the current branch (e.g., the branch was created outside `/hq:start`, or `context.md` was lost). Most projects need no config here — git remote HEAD detection works automatically.
  - Set `.hq/settings.json` `{ "base_branch": "<branch>" }` only when an explicit project-wide override is needed (e.g., a repo whose default base is `develop`, not `main`).
  - The resolution order is **invariant** across all consumers (`/hq:start`, `pr` skill, `worktree-rebase` skill). Consumers MUST NOT skip the `context.md` step.

## Terminology

- **`hq:workflow`** — shorthand for `plugin/v2/rules/workflow.md` (this file — the plugin-internal source of truth for the workflow rule, loaded on demand by each command). Skills and commands cite sections as `hq:workflow § <section>` instead of repeating the full path.
- **`hq:task`** — a GitHub Issue (label: `hq:task`) that describes **what** needs to be done. The requirement. **Trigger** of the workflow.
- **`hq:plan`** — a GitHub Issue (label: `hq:plan`) that describes **how** to do it. The implementation plan. **Center** of the workflow — drives execution, verification, and PR. One `hq:task` can have multiple `hq:plan` issues.
- **`hq:feedback`** — a GitHub Issue (label: `hq:feedback`) for unresolved problems carved out from a PR's Known Issues during PR review. Created via `/hq:triage` only.
- **`hq:doc`** — a GitHub Issue (label: `hq:doc`) for informational notes / research findings worth preserving (not a direct task). Created manually by the user when investigation turns up something useful to retain. Not consumed by any workflow command.
- **`hq:pr`** — a PR label applied automatically by the `pr` skill (in either invocation mode — Standalone `/pr` or via `/hq:start`). Marks a PR as a product of the `hq:plan` → PR workflow. Useful for filtering PRs that belong to this workflow vs ad-hoc PRs.
- **`hq:wip`** — a GitHub Issue modifier label. Purpose is twofold: (1) **drafting marker** — the issue is still being shaped and not ready for automation, (2) **automation gate** — when `/hq:start` or `/hq:draft` is triggered automatically (e.g., from GitHub Actions), the command must skip (or, in manual invocation, pause and confirm) any Issue carrying this label.

These are plugin-specific terms. Always use the `hq:` prefix to distinguish from general "task", "plan", or "feedback".

## Naming Conventions

Titles follow **Conventional Commits** style. Recognized `<type>` values: `feat`, `fix`, `docs`, `refactor`, `chore`, `test`.

- **`hq:task` title**: `<type>: <requirement>`
  - Example: `feat: add user authentication`
- **`hq:plan` title**: `<type>(plan): <implementation approach>`
  - Example: `feat(plan): implement user authentication with OAuth 2.0`
  - The `(plan)` scope distinguishes the implementation plan from the parent requirement.
- **PR title**: `<type>: <implementation>` — same as `hq:plan` title with `(plan)` removed
  - Example: `feat: implement user authentication with OAuth 2.0`
- **Branch name**: `<type>/<short-description>` (kebab-case)
  - Example: `feat/oauth-login`

## Language

Runtime-generated content — `hq:task` / `hq:plan` / PR bodies — is authored in the **conversation language** (the language the user is speaking in this session). Headings that are **auto-injected by `/hq:start` or parsed by downstream tooling** stay in **English** regardless, so the injection / parsing contract holds across projects. Narrative headings — including the PR body's narrative sections — are free-form and follow the conversation language.

- **English (fixed — auto-injected or parse-targeted)**:
  - Workflow markers: `Parent: #N`, `[auto]`, `[manual]`, `[primary]`, `Closes #<plan>`, `Refs #<task>`
  - `hq:task` / `hq:plan` prescribed headings: `## Why`, `## Approach`, `## Editable surface`, `## Plan`, `## Acceptance`, `## Manual Verification` (all consumed by `/hq:draft` / `/hq:start`; `## Manual Verification` is emitted only when the plan has reviewer-owned checks)
  - PR body **workflow sections**: `## Manual Verification` (Phase 8 carry-forward of the plan's reviewer-owned checks), `## Known Issues` (Phase 8 auto-inject from pending FBs + `/hq:triage` literal-grep target)
  - Editable surface inline tags: `[新規]` / `[改修]` / `[削除]` / `[silent-break]` (the brackets and tag values are fixed; the latter three are romaji-free fixed strings even in English-only repos — they are structural markers, not translatable prose)
  - Plan item consumer suffix: `*(consumer: <name>)*` (the literal `consumer:` keyword is fixed; `<name>` is the consumer identifier)
  - File paths, identifiers, code fences, shell commands
- **Conversation language (content)**:
  - `hq:task` body content — prose inside `## Background` / `## What` / `## Scope` / `## Success Criteria`, plus the optional `## Phase Split` (see `## hq:task` below)
  - `hq:plan` body content — prose inside `## Why` / `## Approach`, each `## Editable surface` entry note (after the inline tag), each `## Plan` step description, each `## Acceptance` condition
  - **PR body narrative** — the author-controlled section that sits above the workflow sections. Default heading set (`## Summary` / `## Changes` / `## Notes`) and prose, both in the conversation language. Projects may override the entire narrative — heading names, language, structure — via `.hq/pr.md` (see `pr` skill § Project Overrides and § PR Body Structure below for the 2-layer composition contract).
  - Free-form narrative text under `## Known Issues` entries
  - Any free-form section headings the author introduces (e.g., `### 背景`, `### Requirements`)

This rule applies to every skill and command that generates Issue or PR content — `/hq:draft`, `/hq:start` (fallback drafting), and the `pr` skill.

## Project Overrides

Every hq command, skill, and agent MAY consult a project-local override file under `.hq/` and layer its content on top of the defaults defined in this rule file. Overrides **augment**, never **replace**, the workflow contract — a consumer's own Invariants (phases, gates, required outputs, structural invariants of generated artifacts such as the PR body) remain in force.

### Override files

| Override file | Consumed by | Typical content |
|---|---|---|
| `.hq/draft.md` | `/hq:draft` | Domain-specific acceptance defaults (e.g. primary-tier preference and `## Manual Verification` routing for iOS / CLI / instruction-only projects), brainstorm hints, plan-split preferences |
| `.hq/start.md` | `/hq:start` | Project-specific execution nuance (commit / build / test notes that the command's phases should layer in) |
| `.hq/triage.md` | `/hq:triage` | Briefing tone / Suggestion wording hints / project-specific lean cues for individual findings |
| `.hq/respond.md` | `/hq:respond` | Reply tone / language, project-specific dismissal criteria |
| `.hq/pr.md` | `pr` skill | PR body prose style, title conventions — scope-limited by the `pr` skill's own Invariants |
| `.hq/code-review.md` | `code-reviewer` agent | Project-specific review axes |
| `.hq/security-scan.md` | `security-scanner` agent | Project-specific security patterns |
| `.hq/integrity-check.md` | `integrity-checker` agent | Project-specific plan / diff reconciliation hints |
| `.hq/xcodebuild-config.md` | `xcodebuild-config` skill | Xcode build / run commands — managed by the skill itself (not hand-authored) |

Override files are optional. Absence means "apply defaults"; missing files are never errors. Each consumer resolves its override file by a literal `cat .hq/<name>.md` (or equivalent Read) at load time.

### Scope rules

- **Overrides augment, Invariants govern.** A consumer's Invariants are NOT overridable. If override content appears to contradict an Invariant, the Invariant wins; the consumer SHOULD flag the conflict to the user after execution so the override file can be corrected. Concrete example: `.hq/triage.md` MUST NOT contain category-level or severity-level disposition pre-decisions (e.g. "always escalate Critical", "leave all Low as-is"), because the `/hq:triage` Phase 3 invariant — "No disposition may be APPLIED without an explicit per-item response from the user" — forbids any pre-applied disposition. Briefing tone, Suggestion wording, and per-finding lean cues are permissible; pre-decisions are not.
- **Local to the consuming command / skill / agent.** An override file affects only its own consumer. It cannot introduce new phases, gates, or mandatory checks that alter another command's behavior. Cross-command behavior changes go through this rule file, not through overrides.
- **Per-clone by default.** `.hq/` is included in `.gitignore` by `hq:bootstrap` Task 4, so override files are **per-clone / per-worktree** and NOT team-shared out of the box. Teams that want shared policy either (a) un-ignore specific override files and commit them, or (b) upstream the policy into this rule file. The former is experimental and risks per-member drift; the latter is the canonical path for team-wide rules.
- **Worktree propagation.** `plugin/v2/skills/worktree-setup/scripts/worktree-setup.sh` copies existing override files into a newly created worktree so the worktree inherits the same behavior without re-setup. New override file names introduced here MUST be added to that script's copy list.

### Override Language

Override content is free-form prose in the project's working language (typically the user's conversation language). No structural markers are required — the consumer reads the file body as guidance.

## Issue Hierarchy

```
With a parent hq:task:
  Milestone (GitHub built-in, optional)
    └── hq:task Issue  — requirement ("what")
          └── hq:plan Issue  — implementation plan ("how")
                ├── ← Closes → PR  (Refs #hq:task)
                │     └── ← /hq:triage → hq:feedback Issue(s)  (residual, Refs #plan)
                └── (or escalated during PR review via /hq:triage)

Without a parent hq:task:
  hq:plan Issue  — implementation plan ("how"); top-level, requirement captured in ## Why
    ├── ← Closes → PR  (no Refs trailer)
    │     └── ← /hq:triage → hq:feedback Issue(s)  (residual, Refs #plan)
    └── (or escalated during PR review via /hq:triage)
```

- `hq:task` and `hq:plan` are separate issues (separation of concerns)
- **`hq:task` is optional** — an `hq:plan` can be created without a parent `hq:task` by invoking `/hq:draft` with no issue number. Use this when the requirement already lives in an external tracker, or for 1:1 cases where a separate requirement Issue is pure overhead. When no parent exists, the plan's `## Why` section becomes the sole source of truth for the requirement.
- `hq:plan` is created as a **sub-issue** of its parent `hq:task` (GitHub sub-issues API) only when a parent `hq:task` exists. Plans without a parent are top-level Issues.
- PR uses `Closes #<hq:plan>` to auto-close the plan issue on merge
- PR uses `Refs #<hq:task>` to maintain a link to the requirement — only when the plan has a parent `hq:task`; omitted when absent
- **Traceability inheritance** — if the source `hq:task` has a milestone or project(s), all generated items (`hq:plan`, PR, `hq:feedback`) must inherit them via `--milestone` / `--project` flags. Exception: `hq:feedback` issues do NOT inherit milestones. When no parent `hq:task` exists, there is nothing to inherit from, so milestone / project are left unset.
- Labels are created lazily at first use:
  - `gh label create "hq:task" --description "HQ requirement (what to do)" --color "39FF14" 2>/dev/null || true`
  - `gh label create "hq:plan" --description "HQ implementation plan (how to do it)" --color "00D4FF" 2>/dev/null || true`
  - `gh label create "hq:feedback" --description "HQ unresolved feedback" --color "FF073A" 2>/dev/null || true`
  - `gh label create "hq:doc" --description "HQ informational note / research findings (not a direct task)" --color "5319E7" 2>/dev/null || true`
  - `gh label create "hq:pr" --description "HQ PR associated with an hq:plan" --color "8A2BE2" 2>/dev/null || true`
  - `gh label create "hq:wip" --description "HQ work in progress — automation gate / drafting marker" --color "FFA500" 2>/dev/null || true`
  - `gh label create "hq:manual" --description "HQ PR marker — plan has ## Manual Verification items (reviewer verification required before merge)" --color "FFD700" 2>/dev/null || true`

## `hq:task`

An `hq:task` issue describes **what** needs to be done — the requirement, not the implementation. It is the trigger of the workflow and the input source for `/hq:draft` (which composes one or more `hq:plan` issues from it).

The body is a **lightweight requirement document** primarily read by humans. Optimize for four properties; when they conflict, prioritize in this order:

1. **Sufficient** — carries enough information for `/hq:draft` to compose a `hq:plan` without re-soliciting requirements.
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

Include when motivation is non-obvious, or when later readers (including `/hq:draft`) benefit from knowing why now. Avoid architectural rationale — that belongs in `hq:plan` `## Approach`. Skip on tasks whose `## What` already implies the motivation.

### `## What` *(required)*

The outcome statement. State the desired end state in user / system terms, not in code-change terms.

- ✓ *"Users can sign in with Google OAuth, with first-time sign-in auto-creating a profile row."*
- ✗ *"Add a new endpoint `POST /auth/google` that calls Google's OAuth API and writes to the `users` table."*

The first leaves the implementation path open for `/hq:draft` to design; the second pre-decides the implementation and constrains the plan space.

### `## Scope` *(optional)*

Use when scope boundaries are non-obvious, or when there is real risk of `/hq:draft` expanding into territory the requester does not want. Format: a two-bullet block — `**In:**` (what this task covers) and `**Out:**` (what this task deliberately excludes). Skip the section entirely when the boundary is self-evident from `## What`.

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

Each phase bullet states a name and a responsibility — **not** the editable surface or implementation steps. Surface and Plan items are the responsibility of `/hq:draft` Phase 2, not of `hq:task` authoring. The phase split here is a recommendation, not a binding contract — `/hq:draft` may revise the boundary based on what investigation surfaces.

### Length guideline

`hq:task` length is bounded by **the reader's attention budget**, not a numeric line count. When the body grows long enough that a reviewer skims rather than reads, evaluate whether (a) the task should split into multiple tasks, (b) implementation detail has leaked from `hq:plan`, or (c) `## Background` is over-explaining. Numeric guidelines may emerge once enough `hq:task` examples accumulate; until then, volume judgment stays qualitative.

### Self-contained invariant

Every `hq:task` must:

- Be **self-contained** — readable as a standalone requirement document. `/hq:draft` should be able to produce a `hq:plan` from the body alone, supplemented only by the brainstorm conversation.
- Define **`## What`** and **`## Success Criteria`** at minimum. `## Background`, `## Scope`, and `## Phase Split` are optional — include each when it carries information not already implied by `## What`.
- Stay **outcome-level** — implementation paths belong in `hq:plan`, not here.
- Follow the **Language** rule — content in the conversation language, headings in English.

## `hq:plan`

An `hq:plan` issue is the implementation plan that drives work on a branch. The issue body IS the source of truth for what needs to be done and how completion is verified.

**Two readers, one body.** The same body serves two audiences, and the readability investment is split deliberately so it stays complete-but-not-bloated for both:

- **Human reviewer** (including a developer unfamiliar with this area) reads `## Why` + `## Approach` to decide whether to approve. These two sections carry the **reader self-sufficiency** bar below: the reader should grasp the problem and the chosen mechanism from them alone, without spelunking the diff. When the design is structural, a figure / snippet is the readability tool — not optional decoration.
- **`/hq:start` / `integrity-checker`** consume `## Editable surface` / `## Plan` / `## Acceptance` as the agent fence. These stay terse (≤1行 per entry / item) — that compression is a functional requirement, not a stylistic one. Do **not** spend prose on them.

Figures and intent snippets live in `## Approach` and are **excluded from its sentence count** (see below), so the readability investment in Why/Approach never fights the volume bounds.

The `hq:plan` body follows a **flat 5-section structure** — `## Why` + `## Approach` + `## Editable surface` + `## Plan` + `## Acceptance` — plus an optional `## Manual Verification` section appended when the plan has reviewer-owned checks. Emission rules:

- Angle-bracket `<placeholder>` tokens are substituted with real content.
- The `Parent:` line is emitted only when the plan has a parent `hq:task`; omit it entirely otherwise.
- Optional sub-content (figure / sample code in `## Approach`) is omitted entirely when empty. Never write `_None._` / `Not applicable` / padded prose as filler.
- The `## Manual Verification` section is emitted only when the plan has reviewer-owned checks; omit the heading entirely when every acceptance signal is start-executable.

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
- [ ] [auto] [primary] <strongest start-executable signal — see specificity hierarchy>
- [ ] [auto] <secondary start-executable check>

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
- No numeric cap on item count. Motive-driven bloat — adding items because "while we're at it" rather than because the change genuinely needs them — is not bounded by a count ceiling; it is challenged by `/hq:draft` Phase 2 Simplicity gatekeeper before the plan is composed. When a brainstorm produces a naturally broad scope, `/hq:draft` Phase 2 raises the question of whether it should split into multiple plans rather than being padded as one.

**Volume bound (strict)**: ≤ 1 line per item. Implementation-level signatures, method names, attribute lists are anti-content — they belong in the actual code.

**Consumer coverage check** — `/hq:draft` enforces a coverage check before emitting the plan: every Plan item carrying a `(consumer: <name>)` suffix must name a consumer that is consistent with the change described by the step. The `integrity-checker` agent reconciles declared consumers against the diff as a second net — a `(consumer: <name>)` suffix whose consumer does not appear in the diff is flagged as `Declared-but-missing`.

### `## Acceptance` *(start-owned)*

`## Acceptance` holds the completion criteria **`/hq:start` verifies autonomously**. Every item is `[auto]` — a signal start can execute in this project — and exactly one carries `[primary]`. Checks a human must perform live in `## Manual Verification` below; **nothing start cannot run belongs here** (this is the load-bearing rule: start's evaluation criteria never include what start structurally cannot do).

- **`[auto]`** — Claude can verify autonomously: unit / integration tests, type checks, builds, shell / CLI commands, API calls, file / directory / content checks, **and browser automation via `/hq:e2e-web` (Playwright)** — navigation, URL assertions, element / text presence, form submit flows, DOM state. Executed during `/hq:start` Phase 5. **"It happens in a browser" alone does NOT justify moving a check to `## Manual Verification`** — `/hq:e2e-web` drives browser UI deterministically.
- **`[primary]`** *(role marker)* — **exactly one** `## Acceptance` item per plan MUST carry `[primary]`, and it is **always `[auto]`**. It is the single start-executable pass/fail signal the plan is judged by — and start's motivation to actually reach the target. All other items are secondary (no explicit role marker). A `[primary]` start cannot execute is a drafting defect: the real outcome it reached for belongs in `## Manual Verification`, and `[primary]` moves to the strongest signal start *can* run per the hierarchy below.

**start-primary specificity hierarchy** — the `[primary]` must be the **strongest assertion about the change's own correctness that start can execute in this project**. Pick the highest achievable tier; landing on a lower tier for a change that has real logic is a drafting smell to confront, not a default to settle for:

| Tier | Signal | When it applies |
|---|---|---|
| **1 Behavioral** | an executable test asserting the changed logic produces its intended result (`xcodebuild test` / unit / integration) | the project lets start run tests |
| **2 Anchored-semantic** | start cross-checks the diff against a **named external artifact** (spec / contract / reference) — a grounded semantic assertion | an external ground truth exists to check against |
| **3 Structural** | a grep / file assertion that the change reached its exact target state (all N targets in new form + 0 residual, new surface reachable) | success IS a structural fact (refactors, surface add / remove) |
| **4 Bare build** | compilation succeeds | rejected as `[primary]` unless the change is genuinely compile-only |

A **self-judged** semantic check with no external anchor — Claude reading its own diff and declaring it correct — is **not** a valid `[primary]`: it is not reproducible and is weaker than a grep. Semantic breakage is caught by `/hq:start` Phase 6 Self-Review and Phase 7 Quality Review, so the primary need not carry that load alone.

**Choosing primary** — the `[primary]` answers *"if this single check passes, has start done its job?"* Concrete and reproducible (commit count, file / string presence, API return code, URL transition, named artifact) — never an abstract phrase ("plan works", "app launches"). When the change's true outcome is only human-observable (native mobile UI, subjective UX), `[primary]` stays on the strongest start-executable tier above and the human outcome goes to `## Manual Verification` — do **not** inflate a lazy `[auto]` into a fake outcome signal.

Examples:

| Check | Section / Markers | Why |
|---|---|---|
| Final commit count ≤ 10 and each `## Plan` item appears in a commit subject | `## Acceptance` `[auto] [primary]` | Tier 3 structural — single machine-checkable signal |
| `APIClientTests` rescue-branch test green via `xcodebuild test` | `## Acceptance` `[auto] [primary]` | Tier 1 behavioral — project runs tests |
| Error-code mapping matches server spec (DocBase #4097556) | `## Acceptance` `[auto] [primary]` | Tier 2 anchored-semantic — grounded against a named artifact |
| `pnpm test` passes | `## Acceptance` `[auto]` | Secondary — necessary but not sufficient |
| Click "Save" → page URL becomes `/issues/{id}` | `## Acceptance` `[auto]` | Playwright URL assertion |
| Back gesture dismisses modal with native iOS animation on iPhone 16 simulator | `## Manual Verification` `[manual]` | Runtime outcome — reviewer-owned, no `[primary]` |
| Run `RefreshTokenCoordinatorTests` in Xcode → green | `## Manual Verification` `[manual]` | Deterministic, but this project defers test execution to the reviewer |

Each item is a single concrete signal — not a vague goal.

### `## Manual Verification` *(reviewer-owned; optional)*

The checks a human performs at PR review — everything `/hq:start` structurally cannot, or by project policy does not, execute. This section is **omitted entirely** when every acceptance signal is start-executable. It never carries `[primary]`: the primary is start's motivation and lives in `## Acceptance`.

Items land here routed by **who verifies**, not by what kind of signal. Two kinds:

- **Runtime / subjective outcome** — native mobile UI behavior, animation feel, visual design, physical-device gestures, multi-session scenarios outside Playwright's reach. Each item MUST name exactly one concrete observable target (UI state name, interaction terminus, visual / sound target, named artifact); abstract phrases ("works correctly", "feature complete", "app launches") are rejected.
- **Deterministic check the project defers** — e.g. a unit-test suite that `xcodebuild test` could run but the project policy hands to the reviewer. Deterministic in principle, but start does not run it in this project, so the reviewer owns it. (When the project *does* let start run it, it is `[auto]` and belongs in `## Acceptance` — often as the Tier 1 primary.)

**Format**: `` - [ ] [manual] <one named observable or deferred check> ``. `/hq:start` Phase 8 carries these verbatim into the PR body's `## Manual Verification` section; the `hq:manual` label marks the PR as needing reviewer verification before merge.

### Registration

When the `hq:plan` has a parent `hq:task`, register the newly created plan as a sub-issue of that task:

```bash
PLAN_ID=$(gh api /repos/{owner}/{repo}/issues/<plan> --jq '.id')
gh api --method POST /repos/{owner}/{repo}/issues/<task>/sub_issues --field sub_issue_id="$PLAN_ID"
```

When the plan has no parent `hq:task`, skip sub-issue registration entirely.

### Self-contained invariant

Every `hq:plan` must:

- Be **self-contained** — it survives session clears (it lives on GitHub, not locally).
- Define **`## Why`** (pain + why now), **`## Approach`** (chosen design + ≥1 rejected alternative with reason), **`## Editable surface`** (positive scope set with inline tags `[新規]` / `[改修]` / `[削除]` / `[silent-break]`), **`## Plan`** (implementation steps, single-commit-grain), and **`## Acceptance`** (start-executable completion criteria, including exactly one `[auto] [primary]` item per the specificity hierarchy) — plus **`## Manual Verification`** (reviewer-owned runtime / deferred checks, no `[primary]`) when such checks exist.
- Follow the **Language** rule above — content in the conversation language, markers and prescribed headings in English.
- Keep Acceptance checks atomic and verifiable — each `[auto]` item maps to a single concrete signal (pass/fail).

### Focus

**Focus** is a pointer to the `hq:plan` issue currently driving work. It is stored in two places:

1. **`.hq/tasks/<branch-dir>/context.md`** — deterministic file (branch name: `/` → `-`). Agents and skills resolve focus from this file.
2. **Memory** — a project-type memory entry for cross-session awareness. Lets new sessions know what was in progress.

**context.md format** (frontmatter YAML — no free-text body). When the plan has a parent `hq:task`, all keys below are present; `source` and `gh.task` are **omitted entirely when no parent exists** (see field descriptions).

```yaml
---
plan: <hq:plan issue number>
source: <hq:task issue number>
branch: <original branch name with slashes intact, e.g., feat/oauth-login>
base_branch: <branch this feature branch was created from, e.g., main / develop / refactor/parent-feature>
gh:
  task: .hq/tasks/<branch-dir>/gh/task.json
  plan: .hq/tasks/<branch-dir>/gh/plan.md
---
```

- `plan` — **MUST**. The `hq:plan` issue number driving current work.
- `source` — **optional**. The `hq:task` issue number this plan implements. Present when the plan has a parent `hq:task` (the normal case); **omitted when no parent exists** (plans created via `/hq:draft` without an `hq:task` argument).
- `branch` — **MUST**. The original git branch name (with slashes). Lets tooling check out the correct branch given a plan number (the directory name has `/` → `-` transformation which is not reliably invertible).
- `base_branch` — **MUST**. The branch this feature branch was created from, captured at `/hq:start` Phase 3 via `git symbolic-ref --short HEAD` immediately before `git checkout -b`. This is the **per-branch authoritative base record** consumed by the Base branch resolution chain in § Branch Rules — it survives global `.hq/settings.json` drift across worktrees / stacked PRs (the failure mode that motivates this field). When a `context.md` from a prior version of this rule lacks the field, consumers fall back to the next step in the resolution chain.
- `gh` — paths to the local GitHub issue cache (see Cache-First Principle below). `gh.plan` is always present; `gh.task` is present only when `source` is set (i.e. the plan has a parent `hq:task`).

**Lifecycle**:

- **On start** (`/hq:start`): write `.hq/tasks/<branch-dir>/context.md`. Save focus info to your memory (project type) — include the branch name and plan number, and the source number when the plan has a parent `hq:task` (omit source otherwise).
- **On status query**: read `.hq/tasks/<branch-dir>/context.md` → read the plan body from `.hq/tasks/<branch-dir>/gh/plan.md`. If cache not found, fall back to `gh issue view <plan> --json body --jq '.body'` → report status.
- **On completion**: when a PR is created and all Plan items + Acceptance `[auto]` items are checked, update your memory to indicate no active task. The PR's `Closes #<plan>` handles issue closure on merge. The `context.md` file is left in place — it travels with the task folder until `/hq:archive` moves it to either `.hq/tasks/done/` (PR merged) or `.hq/tasks/canceled/` (PR closed without merging, via `/hq:archive cancel`).

### Focus Resolution

When the user gives a **vague instruction** (e.g., "the auth task", "issue 42"), resolve the focus by searching in order:

1. **context.md** — check `.hq/tasks/<current-branch-dir>/context.md` for the current branch. If it exists, use it and confirm with the user: "Restored focus: plan=#X, source=#Y. Correct?" (drop the `source=` part when the plan has no parent `hq:task`). If the user says no, continue to the steps below.
2. **memory** — check your memory for active focus info.
3. **direct issue number** — if the user provides a number, check `.hq/tasks/` cache dirs first. If not cached, use `gh issue view <number>` to verify it exists and has the `hq:plan` label.
4. **search** — run `gh issue list --label hq:plan --state open --json number,title` and match against the user's keyword.

If exactly one match: set focus automatically. If multiple matches: show candidates and ask the user to choose. If no match: ask the user to specify the issue number.

**NOTE**: `/hq:start <plan>` does **NOT** use this resolution order. It takes a plan number directly and resolves the work branch via `.hq/tasks/*/context.md` (see `find-plan-branch.sh`), ignoring the current branch and memory.

## Simplicity Criterion

An `hq:plan` must survive a benefit/complexity tradeoff check before it is composed. The canonical formulation, from `autoresearch/program.md` and referenced in `hq:doc #40`:

> All else being equal, simpler is better. A small improvement that adds ugly complexity is not worth it. A 0.001 val_bpb improvement that adds 20 lines of hacky code? Probably not worth it. An improvement of ~0 but much simpler code? Keep.

`hq:doc #40` frames this as a **limit of formal plan constraints**: rules like the `## Editable surface` inline-tag set, granularity guidance, or a hypothetical `## Plan` item count cap stop the *result* of motive-driven bloat (many small "while-we're-at-it" additions) but not the *motive* itself. The motive has to be challenged during drafting, where a proposal is still malleable.

This limit is **mitigated** by `/hq:draft` **Phase 2** Simplicity gatekeeper, which challenges reuse vs new-build, minimum-solution comparison, and spread cost before the plan is composed. Pushback is one-round (Claude raises the concern, the user decides, the tradeoff — if accepted — is recorded in `## Approach`). Plans reaching `/hq:start` have already passed this gate.

Consequences for plan structure:

- `## Plan` has **no numeric item cap**. Formal caps target the result (how many items) rather than the motive (why each was added); they were deprecated once the gatekeeper role was introduced. The quality rules on `## Plan` (single meaningful commit unit, same-file consecutive items merge, no half-working intermediate state) remain because they are about the *grain* of each item, not its *necessity*.
- Naturally broad scopes should be split into multiple `hq:plan`s at the gatekeeper stage rather than padded into one. `/hq:draft` Phase 2 raises this split decision explicitly when the brainstorm produces a large scope (see `## hq:plan` § Approach § plan-split signal for the coupling-based criterion).
- The `## Editable surface` inline-tag set and `[auto] [primary]` 1-per-plan rule are retained as formal constraints; they pass the Simplicity criterion test by being low-burden and tightly targeted at specific gaming patterns (undeclared surface change, success-signal dissolution).

## PR Body Structure

The PR body is composed in **two layers**:

1. **Narrative layer** — the section above the workflow sections. Heading names, language, structure, and prose are all **author-controlled** via `.hq/pr.md` (see `pr` skill § Project Overrides). The default narrative — used when `.hq/pr.md` is absent or gives only prose-style hints — is `## Summary` / `## Changes` / `## Notes` in the conversation language. Projects MAY redefine the entire narrative (e.g., `## 概要` / `## 変更` / `## メモ` in Japanese).
2. **Workflow sections layer** — the sections auto-injected by `/hq:start` Phase 8: `## Manual Verification` / `## Known Issues` (each emitted only when its trigger condition holds), followed by the `Closes` / `Refs` trailer. These headings are **English-fixed** (each has an injection or parse contract — see § Language) and not overridable by `.hq/pr.md`.

The full default body produced by `/hq:start` (via the `pr` skill) looks like:

```markdown
## Summary
<brief summary of changes>

## Changes
- <bullet list>

## Manual Verification
- [ ] [manual] <[manual] item copied verbatim from the plan's ## Manual Verification section>
- [ ] [manual] <another [manual] item>

## Known Issues

**Triage summary**: <N> must address, <M> recommended, <K> optional. Process via `/hq:triage <PR>`.

### Must Address (Critical / High)
- [Critical] [<originating-agent>] <unresolved FB title> — <brief description>
- [High] [<originating-agent>] <unresolved FB title> — <brief description>

### Recommended (Medium)
- [Medium] [<originating-agent>] <unresolved FB title> — <brief description>

### Optional (Low)
- [Low] [<originating-agent>] <unresolved FB title> — <brief description>

Closes #<hq:plan>
Refs #<hq:task>
```

The `Refs #<hq:task>` line is emitted **only when the `hq:plan` has a parent `hq:task`**. When absent, omit the line entirely; the trailer block then contains only `Closes #<hq:plan>`.

- **`## Manual Verification`** — the plan's `## Manual Verification` items carried verbatim into the PR body for reviewer verification during PR review. Present only when the plan has such items.
- **`## Known Issues`** — every Phase 4 / 5 / 6 / 7 FB that did not auto-resolve, organized into three action-priority categories (Must Address / Recommended / Optional) so PR reviewers can triage at a glance. The leading `**Triage summary**` line gives the count breakdown immediately; each entry carries both a severity tag (`[<Severity>]`) and an originating-agent tag (`[<originating-agent>]`). **This becomes the source of truth for residual problems.** The corresponding local FB files are moved to `feedbacks/done/` at PR creation time (see FB Lifecycle below).
- If either section is empty, omit it.

During PR review, use `/hq:triage <PR>` to process the `Known Issues` entries — each can be: (1) added to the `hq:plan` for follow-up work, (2) left as-is, (3) carved out as an `hq:feedback` Issue, or (4) fixed in place (applied directly on the PR branch under a regression gate, for trivial and clearly-correct findings).

### Invariants (NOT overridable by `.hq/pr.md`)

The following structural elements of the PR body are invariants of the HQ workflow. A project's `.hq/pr.md` (consumed by the `pr` skill) MAY redefine the **narrative layer** in full — heading names, language, structure, and prose are all override targets — and MAY customize title-line conventions. But `.hq/pr.md` MUST NOT suppress, rename, reformat, or otherwise alter any **workflow-layer** invariant below:

- **`hq:manual` label** — whenever the plan has `## Manual Verification` items at PR creation time, the PR MUST carry the `hq:manual` label (in addition to `hq:pr`). Applied by the `pr` skill.
- **`## Manual Verification` section presence** — whenever the plan has `## Manual Verification` items at PR creation time, they MUST appear verbatim under a section literally named `## Manual Verification`.
- **`## Known Issues` section presence** — whenever pending FB files exist at PR creation time, their titles + brief descriptions MUST appear under a section literally named `## Known Issues`.
- **`## Known Issues` structure** — when pending FBs exist at PR creation time, `## Known Issues` MUST contain: (a) a `**Triage summary**` line at the top stating the count breakdown across the three action categories (e.g., `**Triage summary**: 2 must address, 1 recommended, 5 optional. Process via /hq:triage <PR>.`), and (b) up to three category sub-sections in this order — `### Must Address (Critical / High)` / `### Recommended (Medium)` / `### Optional (Low)`. Each category sub-section is emitted **only when at least one FB falls in it**; empty categories are omitted entirely (no empty headings). Each entry under a category MUST carry **both** tags: a severity tag in the literal form `[<Severity>]` (one of `[Critical]` / `[High]` / `[Medium]` / `[Low]`, drawn from the FB file's frontmatter `severity:` field — no trailing colon) **and** an originating-agent tag in the form `[<originating-agent>]` (drawn from the FB file's frontmatter `skill:` field, normalized to the agent / source name — e.g., `code-reviewer` / `integrity-checker` / `security-scanner` / `self-review` / `/hq:start`). Within each category, entries preserve **insertion order** (no secondary sort). `.hq/pr.md` MUST NOT suppress, rename, reformat, or reorder this structure.
- **FB atomic move to `feedbacks/done/`** — any FB file whose content is surfaced in `## Known Issues` MUST be moved to `feedbacks/done/` as part of the same PR-creation operation. Surfacing without moving (or moving without surfacing) is forbidden.
- **`Closes #<hq:plan>` trailer** — every PR body MUST end with this line.
- **`Refs #<hq:task>` trailer** — required when the `hq:plan` has a parent `hq:task`; the `Refs` line MUST follow `Closes`. Omitted entirely when no parent exists — the PR body then ends with only `Closes #<hq:plan>`.
- **`hq:pr` label** — every PR created by the `pr` skill (in either invocation mode — Standalone or via `/hq:start`) MUST carry the `hq:pr` label.
- **Milestone / project inheritance** *(only when the plan has a parent `hq:task`)* — if the source `hq:task` has a milestone or project(s), the PR MUST inherit them via `--milestone` / `--project` flags. When no parent exists, omit these flags entirely — there is nothing to inherit from.

A newly bootstrapped repository should understand these rules from this section alone — `.hq/pr.md` overrides are applied on top, never in place of, the invariants above.

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

## Cache-First Principle

During `/hq:start` execution, **all reads and writes to the plan body go to the local cache**. The GitHub API is touched only at explicit **sync checkpoints**. This keeps execution fast, avoids rate limits, and lets individual checkbox toggles be cheap.

### Cache files

```
.hq/tasks/<branch-dir>/gh/task.json    # read-only snapshot of hq:task
.hq/tasks/<branch-dir>/gh/plan.md      # read/write working copy of hq:plan body
```

### Sync checkpoints

| Direction | When | Action |
|---|---|---|
| Pull (GitHub → cache) | `/hq:start` begin (both proceed and auto-resume) | Initialize / refresh cache; on auto-resume warn if GitHub body diverges from prior cache |
| Push (cache → GitHub) | After Phase 4 (Execute) complete | Push Plan checkbox updates |
| Push (cache → GitHub) | After Phase 5 (Acceptance) complete | Push Acceptance `[auto]` checkbox updates |
| Push (cache → GitHub) | Before PR creation | Final consistency sync |

### Helper scripts

All located under `${CLAUDE_PLUGIN_ROOT}/plugin/v2/scripts/`:

- **`plan-cache-pull.sh <plan-number>`** — fetch plan body from GitHub, atomically write to `.hq/tasks/<branch-dir>/gh/plan.md`. Prints the written path.
- **`plan-cache-push.sh <plan-number>`** — push the cached plan body to the GitHub Issue via `gh issue edit --body-file`.
- **`plan-check-item.sh <pattern>`** — toggle a single `[ ]` checkbox to `[x]` in the cache, matching by fixed substring. Exit 3 = no match, exit 4 = ambiguous, already-checked = idempotent no-op.
- **`find-plan-branch.sh <plan-number>`** — scan `.hq/tasks/*/context.md` for a `plan: <N>` match, print the corresponding `branch:` field. Exit 1 = not found.

**Rule**: individual checkbox toggles during execution call `plan-check-item.sh` (cache only). Never call `gh issue edit <plan>` directly — always go through `plan-cache-push.sh` at the defined sync checkpoints.

## Feedback Loop

Skills that perform verification or review may output feedback files (FB) to `.hq/tasks/<branch-dir>/feedbacks/`.

### FB Output Rules (for skills that generate FB files)

**Directory** — branch name: replace `/` with `-` (e.g., `feat/m9-wiki` → `feat-m9-wiki`).

```
.hq/tasks/<branch-dir>/feedbacks/              # pending — files here need action
.hq/tasks/<branch-dir>/feedbacks/done/         # resolved or escalated to PR body
.hq/tasks/<branch-dir>/feedbacks/screenshots/  # evidence (optional)
```

**Numbering** — check existing files in `feedbacks/` and `feedbacks/done/` to determine the next number. Format: `FB001.md`, `FB002.md`, etc. (zero-padded to 3 digits).

**Format** — FB files must follow [feedback.md](feedback.md). Read `plan` and `source` values from `.hq/tasks/<branch-dir>/context.md` for the frontmatter fields.

**`covers_acceptance` frontmatter (optional, soft convention)** — FB files MAY include a `covers_acceptance: "<unique substring of an acceptance item>"` frontmatter field linking the FB to the specific `## Acceptance` item it covers. Populate this field in Phase 4/5-origin FBs (where the correspondence is 1:1 with an acceptance item by construction); leave it unset on Phase 6/7-origin FBs (Self-Review minor gaps and Quality Review findings that do not map 1:1 to an acceptance item). No hook or script enforces this field — it exists to make the audit trail linear for reviewers and to support the Phase 5 1-by-1 toggle rule. See [feedback.md](feedback.md) for the full schema.

### FB Lifecycle (for the root agent)

FB handling is **phase-dependent** — different phases generate FBs for different reasons, and the response differs accordingly:

- **Phase 4 (Execute) FBs** — continue-report on blocked / ambiguous / failed-twice steps. The root agent captures the residual as an FB so the work can continue, and the FB later escalates to the PR's `## Known Issues` (Phase 8).
- **Phase 5 (Acceptance) FBs** — continue-report on `[auto]` checks that exhausted the Phase 5 retry cap. Per `/hq:start § Phase 5`, the checkbox is toggled `[x]` anyway and the failure is tracked by the FB. The FB escalates to `## Known Issues` at Phase 8.
- **Phase 6 (Self-Review) FBs** — continue-report on Self-Review `minor-gap` findings. The orchestrator's pre-Quality-Review judgment surfaced a gap that did not rise to `significant-gap` (which would `pause-consult` instead). The FB escalates to `## Known Issues` at Phase 8.
- **Phase 7 (Quality Review) FBs** — Phase 7 is **pure review, no auto-fix**. Every FB produced by the Quality Review agents (code-reviewer / security-scanner / integrity-checker) flows **directly** to `## Known Issues` at Phase 8, regardless of severity (Critical through Low) and regardless of clarity (clearly-actionable through design-ambiguous). The root agent does NOT inline-fix Phase 7 FBs — the user (or `/hq:triage` post-merge) decides each FB's disposition.

**No batch-fix loop, no round counter, no severity gate.** Phase 7 is pure review: prior architecture's batch-fix loop, severity-based threshold gate, and Low-severity-specific exit rules are retired alongside the move to pure review. The motivation is that auto-fixing Quality Review FBs risks scope creep (重箱の隅をつく fix triggering unrelated regressions) — leaving the fix decision to the human aligns with the Karpathy-loop bounded-scope principle and is consistent across all severity levels.

**FB → `feedbacks/done/`** — an FB file moves to `feedbacks/done/` only when its content is surfaced in the PR body's `## Known Issues` (Phase 8's atomic write+move). There is no other path to `done/`. Files do not get modified or deleted at any other point.

**Atomicity** — escalation into `## Known Issues` and the move to `feedbacks/done/` are a single atomic operation at Phase 8 (PR Creation). Surfacing an FB in the PR body without moving its file (or moving the file without surfacing the content) is forbidden. This atomicity cannot be skipped or weakened by project-level overrides such as `.hq/pr.md` — see `## PR Body Structure` § Invariants.

**Note**: FB escalation to `hq:feedback` Issues happens during PR review via `/hq:triage` — not from `/hq:start`, `/pr`, or `/hq:archive`. Local FB files are a **branch-internal** concept; the PR body's `## Known Issues` is the hand-off point.

**`/hq:triage` dispositions (four)**: once a Known Issue reaches the PR body, `/hq:triage` resolves each entry as one of — (1) **add to `hq:plan`** (follow-up work), (2) **leave as-is** (accepted limitation, or already resolved by a later commit — annotated `already resolved in <SHA>`), (3) **escalate to `hq:feedback`**, or (4) **fix in place**. Disposition 4 is the in-PR-branch **resolution path**: a trivial, clearly-correct finding is fixed directly (regression gate → commit → push → `fixed in <SHA>`), bypassing the `hq:plan` re-run loop that would otherwise re-execute `/hq:start` Phases 5–7. This is human-gated and orthogonal to the `/hq:start` Phase 7 auto-fix that was deliberately retired (each fix needs an explicit per-item user decision).

## Retrospective

Per-run reflective analysis written by `/hq:start` Phase 9 (Retrospective) to a Markdown artifact at `.hq/retro/<branch-dir>/<plan>.md`. The artifact lets the run be re-examined after the fact along two axes — *was each Phase 7 (Quality Review) FB a valid detection? Could it have been prevented at implementation time? If so, by what lever?* AND *was the Phase 6 (Self-Review) call and the Phase 7 Agent Selection call appropriate given what subsequently surfaced?* — without re-reading session transcripts. The hypotheses are that (a) a non-trivial fraction of Phase 7 FBs are preventable at implementation time, exposed by structured per-FB analysis, and (b) the Phase 6/7 judgment calls drift over runs in ways that accumulated learnings in `.hq/start-memory.md` — auto-distilled from these retros by Phase 10 (Distillation) — should tighten.

`.hq/retro/` follows `.hq/` semantics: gitignored (covered by the existing `.hq` entry), per-clone, branch-local. Worktree copy is not propagated by `worktree-setup.sh` — retro is the run's frozen output, not project-wide configuration. Team-wide aggregation, if ever required, is a separate plan.

### File path

```
.hq/retro/<branch-dir>/<plan>.md
```

`<branch-dir>` = branch name with `/` → `-` (same convention as `.hq/tasks/<branch-dir>/`). `<plan>` = bare `hq:plan` issue number (e.g., `75`). One file per `/hq:start` run; auto-resume sessions overwrite the existing file because the artifact captures the latest run snapshot, not a per-session history.

### Fixed schema

The artifact has exactly **four** top-level Markdown sections, in this order:

1. **`## Run Summary`** — facts about the run, all derivable from existing JSONL events + git log + plan cache + decision reports (no LLM judgment in this section). **Every field below is MUST — omitting any of them breaks the primary acceptance gate.** Fields:
   - plan id, branch name, run timestamp (UTC, ISO 8601)
   - **phase wall-clock durations** — read `.hq/tasks/<branch-dir>/phase-timings.jsonl` via `phase-timing.sh summary` and emit the helper's output **verbatim**. Scope is **Phase 4–10**; Phase 1–3 / Phase 11 are deliberately not measured (see `/hq:start § Phase Timing` for the structural reasons — Phase 1–3 stamp pairs split across the Phase 3 branch switch, Phase 11 (Report) self-emits the summary). **Phase 10 (Distillation) runs after this artifact is written, so it shows `(no data)` here — expected, not a defect; its real duration appears only in the Phase 11 Report.** When the helper prints `No timing data recorded.` (no stamps ever landed for this run), emit that line verbatim with a one-line cause note — **never silently skip the field**. Any Phase 4–9 showing `(no data)` is a workflow defect signal (stamp invocations failed) and the `## Reflection` section MUST call it out (Phase 10's `(no data)` here is exempt per the above).
   - total commits made on the branch (`git rev-list --count <base>..HEAD`)
   - Phase 6 Self-Review result (read `.hq/tasks/<branch-dir>/quality-review-events.jsonl` via `quality-review.sh summary`)
   - Phase 7 Agent Selection mode and launched / skipped agents (same source)
   - Per-agent initial FB counts and severity breakdown
   - counts of FB files in `feedbacks/done/` and `feedbacks/` (residual)

2. **`## Judgment Review`** — reflective evaluation of the two judgment calls this run made. Two subsections in this order:

   - **`### Phase 6 Self-Review`** — quote the **Decision rationale** paragraph from the Phase 6 Self-Review decision report (`.hq/tasks/<branch-dir>/reports/self-review-*.md`). Then add a `**Hindsight**:` line (≤ 2 sentences) on whether the call (pass / minor-gap / significant-gap) reads sound given what Phase 7 subsequently surfaced and what landed in `feedbacks/done/`. Cite concrete signals — if Phase 7 produced FBs that the Self-Review should have caught, say so; if the Self-Review's minor-gap FB later proved load-bearing, note it; if everything aligned, name what aligned.
   - **`### Phase 7 Agent Selection`** — quote the **Overall rationale** paragraph from the Phase 7 Agent Selection decision report (`.hq/tasks/<branch-dir>/reports/agent-selection-*.md`) and list which agents were launched / skipped (with their one-line reasons from the decision report). Then add a `**Hindsight**:` line (≤ 2 sentences) on whether the subset was right — did a launched agent return nothing useful (over-launch), or did a skipped axis surface as an FB from somewhere else / from the user later (under-launch)? Cite concrete FB ids or severity counts where applicable.

   When a decision report file is missing (resumed runs, prior-version artifacts), emit `(decision report not found — judgment review unavailable)` in place of the quoted rationale and skip the **Hindsight** line for that subsection. The subsection header itself is always emitted — the fixed four-section structure is the primary acceptance gate.

3. **`## FB Analysis`** — one entry per FB file under `.hq/tasks/<branch-dir>/feedbacks/done/` at Phase 9 entry time. Under the post-refactor pure-review Phase 7, FBs reach `done/` via a single path: Phase 8's atomic `## Known Issues` write + `done/` move (per `## Feedback Loop`). There is no Phase 5 / Phase 6 / Phase 7 in-branch resolution path anymore.

   Each entry has the form:

   ````markdown
   ### FB### — <Severity> — <originating agent>

   ```yaml
   detection_validity: <valid | invalid | borderline>
   preventable_at_implementation: <yes | no | partial>
   prevention_lever: <stricter-acceptance | smaller-commit-grain | reuse-existing | better-pre-read | plan-discipline | n/a>
   ```

   **Notes**: <≤ 2 sentences, factual — no rationalization, no praise>
   ````

   When `feedbacks/done/` has no FB files at Phase 9 entry (which occurs when no FBs were generated across the entire run — Phase 4 / 5 / 6 / 7 all clean), `## FB Analysis` is still emitted with the literal body `(no FBs to analyze)` — do NOT omit the section. The fixed four-section structure is the primary acceptance gate, and an absent section breaks it.

4. **`## Reflection`** — free-form prose, ≤ 8 sentences. State what went well, what could improve, and any pattern visible across the FB Analysis entries, the Judgment Review entries, **or the `## Run Summary` Phase timing block** (e.g., "many FBs marked `preventable_at_implementation: yes` with `prevention_lever: smaller-commit-grain` — next run should split implementation steps before committing"; or "Phase 7 Agent Selection skipped `integrity-checker` despite a `[削除]` tag in the diff — the hard-floor for `[削除]` should be reconsidered"; or "Phase 7 wall-clock dominated the run at 18m — judgment-mode agent set is over-launching, consider skipping `integrity-checker` next run"). When `## Run Summary` shows any Phase 4–9 as `(no data)` or `No timing data recorded.`, the Reflection MUST surface this as a workflow defect signal — silent timing-stamp failure breaks cross-run comparability and is itself a reportable issue. (The defect trigger is **Phase 4–9**, not 4–10: Phase 10 (Distillation)'s expected `(no data)` at retro-write time is exempt — see the `## Run Summary` Phase timing field above.) Self-praise without a concrete pattern citation is the failure mode this section guards against — the LLM is the author and the analysis subject simultaneously, so explicit pattern citation is what keeps the section honest.

### Per-FB analysis fields

The per-FB block has **two parts**: (1) a YAML fence carrying **3 categorical axes** with closed enumerations, and (2) a `**Notes**` field below the fence — free-form Markdown, ≤ 2 sentences. The split is deliberate: the YAML axes are the aggregable structured surface (strict enumeration is what makes cross-run analysis tractable when an active loop is built later); the `Notes` field is the human-readable elaboration that does not need to fit a closed schema. Free-form prose MUST stay in `Notes`, never in axis values.

**YAML axes (closed enumerations):**

| Axis | Values | Meaning |
|---|---|---|
| `detection_validity` | `valid` / `invalid` / `borderline` | Was the QR detection itself sound? `valid` — yes, the FB names a real defect. `invalid` — false positive, the agent was wrong. `borderline` — defensible but the call could have gone either way. |
| `preventable_at_implementation` | `yes` / `no` / `partial` | Could this have been caught during Phase 4 (Execute) instead of surfacing in Phase 6/7? `yes` — clearly yes, a discipline gap. `no` — only QR's external lens could see it. `partial` — partially preventable; the underlying signal was reachable but the specific framing required QR. |
| `prevention_lever` | `stricter-acceptance` / `smaller-commit-grain` / `reuse-existing` / `better-pre-read` / `plan-discipline` / `n/a` | If preventable, by what change in workflow? `stricter-acceptance` — the plan's `## Acceptance` would have caught it if tightened. `smaller-commit-grain` — splitting the commit would have surfaced it. `reuse-existing` — reaching for an existing mechanism instead of new code would have avoided it. `better-pre-read` — reading the surrounding code more carefully before editing would have caught it. `plan-discipline` — the gap was a Phase 2 / Phase 4 plan-vs-diff discipline issue (over-declared `## Editable surface`, Boundary expansion protocol not invoked when stack-natural extension required it, speculative `(consumer: <name>)` declarations) — adhering to the workflow's plan/diff contract would have prevented Phase 6/7 from surfacing it. `n/a` — applies when `preventable_at_implementation` is `no`, OR when `detection_validity` is `invalid` (false positive — the question of prevention does not apply to a defect that did not exist). |

**Markdown field (free-form):**

- `**Notes**` — ≤ 2 sentences, factual elaboration. No rationalization. No praise. Lives below the YAML fence in the per-FB entry template; not part of the YAML block.

Adding axis values or introducing a new YAML axis is a deliberate change to this rule file; runtime composition MUST NOT invent values or add keys.

### Distillation (Phase 10) — closing the active loop

`/hq:start` Phase 10 (Distillation) closes the learning loop the retrospective opens: it consumes this run's retro artifact and distills the **repo-specific** learnings into a **char-bounded compressed instruction** at `.hq/start-memory.md`, which Phase 4 reads at implementation time (and Phase 6 / Phase 7 consult for judgment). Contract:

- **Source** — the retro artifact's `## FB Analysis` (`prevention_lever` + Notes) and `## Reflection`.
- **Output** — forward-looking imperative cautions ("next time in this repo, do X"), merged and deduplicated into `.hq/start-memory.md`. **Not** an incident log of past problems.
- **Budget** — `.hq/start-memory.md` is hard-capped by the `start-memory char limit` setting (`/hq:start § Settings`); Phase 10 re-distills (merge / generalize / evict) to stay within budget. The cap is the curation mechanism that prevents unbounded growth.
- **Repo-specific only** — learnings whose fix would change the **plugin itself** (workflow rules / commands) are NOT distilled into `start-memory.md`; surfacing those as plugin-improvement feedback from the same retro source is a **separate output owned by a future `hq:plan`**.

Reading retro learnings back into `/hq:draft` Phase 2 (Simplicity gate priors) remains future work — when added, it ships as a separate `hq:plan`, not as an extension to this section.
