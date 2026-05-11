# Workflow

## Prerequisites

- **`gh` CLI** must be authenticated: `gh auth status` must succeed
- All issue operations (`gh issue view`, `gh issue create`, `gh issue list`, `gh issue close`) require this

## Branch Rules

- **Never work directly on base branches** (`main`, `develop*`) — always create a feature branch
- **Base branch resolution** (used by all skills): `.hq/settings.json` `base_branch` → `git symbolic-ref refs/remotes/origin/HEAD` → `"main"`
  - Most projects need no config — git remote HEAD detection works automatically
  - Set `.hq/settings.json` `{ "base_branch": "<branch>" }` only when an explicit override is needed (e.g., worktree targeting `develop`)

## Before Commit

1. Run `format` command (see Commands table in CLAUDE.md)
2. Verify `build` command passes
3. **Blast-radius self-check** — one pass per unit, not a defect-exhaustion loop:
   - For each **named thing** (symbol / heading / marker / config key / enum case / label / error code) this change introduces, renames, or shifts the semantics of, `grep` the repo and update every stale reference. LSP find-references is an equivalent substitute where available.
   - For each procedure (gate / pipeline / phased doc / state machine) this change touches, re-read it top-to-bottom once in **flow order** and verify each step's preconditions still hold against the new state.

## Terminology

- **`hq:workflow`** — shorthand for `plugin/v2/rules/workflow.md` (this file — the plugin-internal source of truth for the workflow rule, loaded on demand by each command). Skills and commands cite sections as `hq:workflow § <section>` instead of repeating the full path.
- **`hq:task`** — a GitHub Issue (label: `hq:task`) that describes **what** needs to be done. The requirement. **Trigger** of the workflow.
- **`hq:plan`** — a GitHub Issue (label: `hq:plan`) that describes **how** to do it. The implementation plan. **Center** of the workflow — drives execution, verification, and PR. One `hq:task` can have multiple `hq:plan` issues.
- **`hq:feedback`** — a GitHub Issue (label: `hq:feedback`) for unresolved problems carved out from a PR's Known Issues during PR review. Created via `/hq:triage` only.
- **`hq:doc`** — a GitHub Issue (label: `hq:doc`) for informational notes / research findings worth preserving (not a direct task). Created manually by the user when investigation turns up something useful to retain. Not consumed by any workflow command.
- **`hq:pr`** — a PR label applied automatically by the `pr` skill (in either invocation mode — Standalone `/pr` or via `/hq:start`). Marks a PR as a product of the `hq:plan` → PR workflow. Useful for filtering PRs that belong to this workflow vs ad-hoc PRs.
- **`hq:wip`** — a GitHub Issue modifier label. Purpose is twofold: (1) **drafting marker** — the issue is still being shaped and not ready for automation, (2) **automation gate** — when `/hq:start` or `/hq:draft` is triggered automatically (e.g., from GitHub Actions), the command must skip (or, in manual invocation, pause and confirm) any Issue carrying this label.

These are plugin-specific terms. Always use the `hq:` prefix to distinguish from general "task", "plan", or "feedback".

## Project Overrides

Every hq command, skill, and agent MAY consult a project-local override file under `.hq/` and layer its content on top of the defaults defined in this rule file. Overrides **augment**, never **replace**, the workflow contract — a consumer's own Invariants (phases, gates, required outputs, structural invariants of generated artifacts such as the PR body) remain in force.

### Override files

| Override file | Consumed by | Typical content |
|---|---|---|
| `.hq/draft.md` | `/hq:draft` | Domain-specific acceptance defaults (e.g. always prefer `[manual]` primary on iOS / CLI / instruction-only projects), brainstorm hints, plan-split preferences |
| `.hq/start.md` | `/hq:start` | Project-specific execution nuance (commit / build / test notes that the command's phases should layer in) |
| `.hq/triage.md` | `/hq:triage` | Default disposition guidance per Known-Issue category |
| `.hq/respond.md` | `/hq:respond` | Reply tone / language, project-specific dismissal criteria |
| `.hq/pr.md` | `pr` skill | PR body prose style, title conventions — scope-limited by the `pr` skill's own Invariants |
| `.hq/code-review.md` | `code-reviewer` agent | Project-specific review axes |
| `.hq/security-scan.md` | `security-scanner` agent | Project-specific security patterns |
| `.hq/integrity-check.md` | `integrity-checker` agent | Project-specific plan / diff reconciliation hints |
| `.hq/xcodebuild-config.md` | `xcodebuild-config` skill | Xcode build / run commands — managed by the skill itself (not hand-authored) |

Override files are optional. Absence means "apply defaults"; missing files are never errors. Each consumer resolves its override file by a literal `cat .hq/<name>.md` (or equivalent Read) at load time.

### Scope rules

- **Overrides augment, Invariants govern.** A consumer's Invariants are NOT overridable. If override content appears to contradict an Invariant, the Invariant wins; the consumer SHOULD flag the conflict to the user after execution so the override file can be corrected.
- **Local to the consuming command / skill / agent.** An override file affects only its own consumer. It cannot introduce new phases, gates, or mandatory checks that alter another command's behavior. Cross-command behavior changes go through this rule file, not through overrides.
- **Per-clone by default.** `.hq/` is included in `.gitignore` by `hq:bootstrap` Task 4, so override files are **per-clone / per-worktree** and NOT team-shared out of the box. Teams that want shared policy either (a) un-ignore specific override files and commit them, or (b) upstream the policy into this rule file. The former is experimental and risks per-member drift; the latter is the canonical path for team-wide rules.
- **Worktree propagation.** `plugin/v2/skills/worktree-setup/scripts/worktree-setup.sh` copies existing override files into a newly created worktree so the worktree inherits the same behavior without re-setup. New override file names introduced here MUST be added to that script's copy list.

### Language

Override content is free-form prose in the project's working language (typically the user's conversation language). No structural markers are required — the consumer reads the file body as guidance.

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

Runtime-generated content — `hq:task` / `hq:plan` / PR bodies — is authored in the **conversation language** (the language the user is speaking in this session). Workflow markers and prescribed structural headings stay in **English** regardless, so downstream tooling can parse them.

- **English (fixed)**:
  - Workflow markers: `Parent: #N`, `[auto]`, `[manual]`, `[primary]`, `Closes #<plan>`, `Refs #<task>`
  - Prescribed headings: `## Why`, `## Approach`, `## Editable surface`, `## Plan`, `## Acceptance`, `## Primary Verification (manual)`, `## Manual Verification`, `## Known Issues`, `## Summary`, `## Changes`, `## Notes`
  - Editable surface inline tags: `[新規]` / `[改修]` / `[削除]` / `[silent-break]` (the brackets and tag values are fixed; the latter three are romaji-free fixed strings even in English-only repos — they are structural markers, not translatable prose)
  - Plan item consumer suffix: `*(consumer: <name>)*` (the literal `consumer:` keyword is fixed; `<name>` is the consumer identifier)
  - File paths, identifiers, code fences, shell commands
- **Conversation language (content)**:
  - `hq:task` body content — prose inside `## Background` / `## What` / `## Scope` / `## Success Criteria`, plus the optional `## Phase Split` (see `## hq:task` below)
  - `hq:plan` body content — prose inside `## Why` / `## Approach`, each `## Editable surface` entry note (after the inline tag), each `## Plan` step description, each `## Acceptance` condition
  - PR body prose — text inside `## Summary` / `## Changes` / `## Notes` and free-form narrative under `## Known Issues`
  - Any free-form section headings the author introduces (e.g., `### 背景`, `### Requirements`)

This rule applies to every skill and command that generates Issue or PR content — `/hq:draft`, `/hq:start` (fallback drafting), and the `pr` skill.

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
  - `gh label create "hq:manual" --description "HQ PR marker — plan has [manual] [primary] acceptance (manual primary verification required)" --color "FFD700" 2>/dev/null || true`

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

The `hq:plan` body follows a **flat 5-section structure**: `## Why` + `## Approach` + `## Editable surface` + `## Plan` + `## Acceptance`. Emission rules:

- Angle-bracket `<placeholder>` tokens are substituted with real content.
- The `Parent:` line is emitted only when the plan has a parent `hq:task`; omit it entirely otherwise.
- Optional sub-content (figure / sample code in `## Approach`) is omitted entirely when empty. Never write `_None._` / `Not applicable` / padded prose as filler.

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
- [ ] [manual] <human-eye check, used sparingly>
```

### `## Why` *(required)*

The pain and why now. Gives the reader the "what problem is this solving" answer in seconds.

**Content rules**:

- Required: (a) the pain or opportunity, (b) why now / what triggers this plan.
- Anti-content (move to `## Approach` if present): file:line citations, error code enumerations, design judgment, comparison of alternatives, implementation hints.
- Volume guidance: a few sentences. The test is not a sentence count but whether every sentence answers (a) or (b) — if it doesn't, it is content type leak and belongs elsewhere.

### `## Approach` *(required)*

The chosen design + at least one rejected alternative with reason. This section is the single load-bearing field for "why this implementation" — generic phrasing here is the failure mode that wastes PR-reviewer cycles.

**Content rules**:

- Required: (a) chosen design summary, (b) at least one rejected alternative named and dismissed with a one-line reason. "We considered alternatives" without naming any is not enough.
- Optional figure: Mermaid or ASCII diagram, when the structural change reads better as a figure than as prose. GitHub renders Mermaid natively inside Issue bodies.
- Optional sample code: ≤ 10 lines, intent-conveying only. Use when the shape of the change is faster to communicate as code than as prose.
- Anti-content (move out): full implementation listings, complete signature enumerations, attribute-by-attribute spec dumps. Implementation detail belongs in the actual code, not in the plan.
- Volume guidance: prose ≤ 5 sentences (figure / sample code excluded from the count). If more independent decisions need to be articulated, see **plan-split signal** below.

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

### `## Acceptance`

Verifiable completion criteria. Each item carries an execution marker (`[auto]` or `[manual]`) and optionally a role marker (`[primary]`):

- **`[auto]`** — Claude can verify autonomously: unit / integration tests, type checks, builds, shell / CLI commands, API calls, file / directory / content checks, **and browser automation via `/hq:e2e-web` (Playwright)** — navigation, URL assertions, element / text presence, form submit flows, DOM state. Executed during `/hq:start` Acceptance phase.
- **`[manual]`** — requires human judgment tools cannot provide. Four conditions qualify: (1) **subjective** — aesthetics, UX feel; (2) **physical device or assistive tech** — touch gestures on real devices, screen reader flow; (3) **live production or sensitive credentials**; (4) **multi-session / cross-tab scenarios** Playwright cannot reliably orchestrate. Carried into the PR body and verified by the user during PR review.
- **`[primary]`** *(role marker, combines with `[auto]` by default)* — **exactly one** `## Acceptance` item per plan MUST carry `[primary]`. It designates the **single pass/fail signal** that tells the plan succeeded — the one check whose outcome the plan is ultimately judged by. All other `[auto]` items are **secondary** (no explicit marker). `[manual] [primary]` is **forbidden by default** — primary must be machine-verifiable so Acceptance Execution can evaluate it deterministically. **Exception**: the `#### [manual] [primary] escape hatch` subsection below permits `[manual] [primary]` under strict conditions (iOS / subjective UX where `[auto]` outcome signal is structurally infeasible) with required compensating controls.

**Choosing `[auto]` vs `[manual]`** — default to `[auto]`. A check is `[manual]` only when one of the four conditions above genuinely applies. **"It happens in a browser" alone does NOT justify `[manual]`** — `/hq:e2e-web` drives browser UI deterministically.

**Choosing primary** — the `[primary]` item answers: *"if this single check passes, is the plan done?"* It must be concrete and verifiable (commit count, file existence, specific string presence, API return code, URL transition, etc.) — not an abstract phrase like "plan works" or "implementation complete". Generic phrases dissolve the primary/secondary distinction and count as a drafting defect. When no `[auto]` outcome signal is structurally available (native mobile UI, subjective UX targets), consult the `#### [manual] [primary] escape hatch` subsection below — **never substitute a lazy `[auto]` such as "app launches without crash" for a real outcome signal**.

Examples:

| Check | Markers | Why |
|---|---|---|
| Final commit count ≤ 10 and each `## Plan` item appears in a commit subject | `[auto] [primary]` | Single machine-checkable signal of plan success |
| `pnpm test` passes | `[auto]` | Secondary — necessary but not sufficient |
| Click "Save" → page URL becomes `/issues/{id}` | `[auto]` | Playwright URL assertion |
| Form submit → DB row exists | `[auto]` | API / DB check |
| Back button's icon matches app's visual style | `[manual]` | Subjective / visual |
| Swipe-back gesture feels responsive on iOS Safari | `[manual]` | Physical device |
| Two browser tabs each show the correct tenant after login | `[manual]` | Multi-session orchestration |
| Back gesture swipe dismisses modal with native iOS animation on iPhone 16 simulator | `[manual] [primary]` ✓ | Escape hatch: iOS native UI — `[auto]` outcome infeasible. Observable target named. Requires `## Primary Verification (manual)` evidence block |
| "App works as intended" | `[manual] [primary]` ✗ | Rejected: abstract phrase, no single observable target. Escape hatch does not rescue lazy wording |

Each Acceptance item is a single concrete signal — not a vague goal.

#### `[manual] [primary]` escape hatch

The default rule forbids `[manual] [primary]`. This subsection is the sole exception. Abuse devalues the primary/secondary distinction — use only when **all three** conditions hold.

**Conditions (all must hold)**:

- **(a) `[auto]` outcome measurement is structurally infeasible** — the plan's domain has no `[auto]` signal that measures the feature's intended outcome. Build success, lint, and unit tests cover structural correctness but not the outcome. Canonical cases: native mobile UI behavior (iOS / Android touch interactions, platform-specific animations), subjective UX or visual design targets, multi-session scenarios outside Playwright's reach. **Web features where `/hq:e2e-web` can drive the outcome do NOT qualify** — the default rule stands.
- **(b) Primary names exactly one observable event with a concrete target** — the `[manual] [primary]` description MUST name one observable target (UI state name, interaction terminus, visual / sound target, named artifact). Abstract phrases ("works correctly", "user is satisfied", "feature is complete", "app launches") are rejected **even under the escape hatch** — they dissolve the primary/secondary distinction as much as a lazy `[auto]` would.
- **(c) `## Editable surface` is structurally bounded** — every entry has its inline tag (`[新規]` / `[改修]` / `[削除]` / `[silent-break]`) and a concrete one-line note. Under-declared surface lets an unmeasured primary hide behind unmeasured scope; the escape hatch requires the surface to be tight.

**Compensating controls (required whenever the escape hatch fires)**:

- **Evidence schema** — the PR body MUST carry a `## Primary Verification (manual)` section populated per the template in `## PR Body Structure` below. A screenshot or video link plus a reviewer checklist of ≥3 concrete observations decomposing the primary's observable into verifiable parts. A bare checkbox is not acceptable.
- **Label + gate** — the PR MUST carry the `hq:manual` label (applied by the `pr` skill at `/hq:start` Phase 7). The Phase 7 gate MUST assert the `## Primary Verification (manual)` section is present and populated; missing evidence blocks PR creation.

**Runtime behavior**:

- `/hq:start` Phase 5 does NOT execute `[manual] [primary]` (same as other `[manual]` items — the Phase 5 sweep ignores `[manual]`). Phase 9 Report surfaces the item as **`[primary deferred]`** — the sibling notice to `[primary failure]`, signalling the single most important signal is pending reviewer judgment rather than failed.
- Final pass/fail judgment happens at PR review. Reviewer uses the evidence block to verify the observable was actually achieved; merge approval is the explicit ack gate.

**Rollback path**: if `[manual] [primary]` usage drifts beyond the domains above (e.g., selected for web features where `/hq:e2e-web` was available), tighten condition (a) to enumerate permitted domains explicitly. No automated drift monitor is built into this workflow version — PR review is the safety net.

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
- Define **`## Why`** (pain + why now), **`## Approach`** (chosen design + ≥1 rejected alternative with reason), **`## Editable surface`** (positive scope set with inline tags `[新規]` / `[改修]` / `[削除]` / `[silent-break]`), **`## Plan`** (implementation steps, single-commit-grain), and **`## Acceptance`** (completion criteria, including exactly one `[primary]` item — `[auto] [primary]` by default, `[manual] [primary]` permitted under the escape hatch).
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
gh:
  task: .hq/tasks/<branch-dir>/gh/task.json
  plan: .hq/tasks/<branch-dir>/gh/plan.md
---
```

- `plan` — **MUST**. The `hq:plan` issue number driving current work.
- `source` — **optional**. The `hq:task` issue number this plan implements. Present when the plan has a parent `hq:task` (the normal case); **omitted when no parent exists** (plans created via `/hq:draft` without an `hq:task` argument).
- `branch` — **MUST**. The original git branch name (with slashes). Lets tooling check out the correct branch given a plan number (the directory name has `/` → `-` transformation which is not reliably invertible).
- `gh` — paths to the local GitHub issue cache (see Cache-First Principle below). `gh.plan` is always present; `gh.task` is present only when `source` is set (i.e. the plan has a parent `hq:task`).

**Lifecycle**:

- **On start** (`/hq:start`): write `.hq/tasks/<branch-dir>/context.md`. Save focus info to your memory (project type) — include the branch name and plan number, and the source number when the plan has a parent `hq:task` (omit source otherwise).
- **On status query**: read `.hq/tasks/<branch-dir>/context.md` → read the plan body from `.hq/tasks/<branch-dir>/gh/plan.md`. If cache not found, fall back to `gh issue view <plan> --json body --jq '.body'` → report status.
- **On completion**: when a PR is created and all Plan items + Acceptance `[auto]` items are checked, update your memory to indicate no active task. The PR's `Closes #<plan>` handles issue closure on merge. The `context.md` file is left in place — it travels with the task folder until `/hq:archive` moves it.

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

## PR Body Structure

The PR body produced by `/hq:start` (via the `pr` skill) follows this structure:

```markdown
## Summary
<brief summary of changes>

## Changes
- <bullet list>

## Primary Verification (manual)
- **Primary**: <[manual] [primary] item copied verbatim from plan>
- **Evidence**: <screenshot / video link>
- **Reviewer checklist** (≥3 concrete observations decomposing the primary into verifiable parts):
  - [ ] <observation 1>
  - [ ] <observation 2>
  - [ ] <observation 3>

## Manual Verification
- [ ] [manual] <unchecked [manual] item copied verbatim from plan.md>
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

- **`## Primary Verification (manual)`** — present **only** when the plan's `## Acceptance` has a `[manual] [primary]` item (escape hatch). Holds the evidence block required for reviewer to verify the escape hatch primary. Omitted entirely when the plan has `[auto] [primary]`.
- **`## Manual Verification`** — all unchecked `[manual]` items from the Acceptance section (excluding the `[manual] [primary]` item, which lives in its own section above), for user verification during PR review.
- **`## Known Issues`** — every Phase 4 / 5 / 6 FB that did not auto-resolve, organized into three action-priority categories (Must Address / Recommended / Optional) so PR reviewers can triage at a glance. The leading `**Triage summary**` line gives the count breakdown immediately; each entry carries both a severity tag (`[<Severity>]`) and an originating-agent tag (`[<originating-agent>]`). **This becomes the source of truth for residual problems.** The corresponding local FB files are moved to `feedbacks/done/` at PR creation time (see FB Lifecycle below).
- If either section is empty, omit it.

During PR review, use `/hq:triage <PR>` to process the `Known Issues` entries — each can be: (1) added to the `hq:plan` for follow-up work, (2) left as-is, or (3) carved out as an `hq:feedback` Issue.

### Invariants (NOT overridable by `.hq/pr.md`)

The following structural elements of the PR body are invariants of the HQ workflow. A project's `.hq/pr.md` (consumed by the `pr` skill) MAY customize prose style, language, title conventions, and optional sections — but it MUST NOT suppress, rename, reformat, or otherwise alter any item below:

- **`## Primary Verification (manual)` section presence** — whenever a `[manual] [primary]` item exists in the plan's `## Acceptance` section at PR creation time (escape hatch — see `### `## Acceptance`` § `#### [manual] [primary] escape hatch`), the PR body MUST contain a section literally named `## Primary Verification (manual)`. The section MUST include: the primary item verbatim, an evidence link (screenshot / video), and a reviewer checklist of ≥3 concrete observations. A bare checkbox without evidence or checklist is insufficient; the `/hq:start` Phase 7 gate blocks PR creation when this block is missing or incomplete.
- **`hq:manual` label** — whenever a `[manual] [primary]` item exists in the plan's `## Acceptance` section at PR creation time, the PR MUST carry the `hq:manual` label (in addition to `hq:pr`). Applied by the `pr` skill.
- **`## Manual Verification` section presence** — whenever unchecked `[manual]` items exist in the plan's `## Acceptance` section at PR creation time (excluding the `[manual] [primary]` item, which is covered by `## Primary Verification (manual)` above), they MUST appear verbatim under a section literally named `## Manual Verification`.
- **`## Known Issues` section presence** — whenever pending FB files exist at PR creation time, their titles + brief descriptions MUST appear under a section literally named `## Known Issues`.
- **`## Known Issues` structure** — when pending FBs exist at PR creation time, `## Known Issues` MUST contain: (a) a `**Triage summary**` line at the top stating the count breakdown across the three action categories (e.g., `**Triage summary**: 2 must address, 1 recommended, 5 optional. Process via /hq:triage <PR>.`), and (b) up to three category sub-sections in this order — `### Must Address (Critical / High)` / `### Recommended (Medium)` / `### Optional (Low)`. Each category sub-section is emitted **only when at least one FB falls in it**; empty categories are omitted entirely (no empty headings). Each entry under a category MUST carry **both** tags: a severity tag in the literal form `[<Severity>]` (one of `[Critical]` / `[High]` / `[Medium]` / `[Low]`, drawn from the FB file's frontmatter `severity:` field — no trailing colon) **and** an originating-agent tag in the form `[<originating-agent>]` (drawn from the FB file's frontmatter `skill:` field, normalized to the agent / source name — e.g., `code-reviewer` / `integrity-checker` / `security-scanner` / `self-review-gate` / `/hq:start`). Within each category, entries preserve **insertion order** (no secondary sort). `.hq/pr.md` MUST NOT suppress, rename, reformat, or reorder this structure.
- **FB atomic move to `feedbacks/done/`** — any FB file whose content is surfaced in `## Known Issues` MUST be moved to `feedbacks/done/` as part of the same PR-creation operation. Surfacing without moving (or moving without surfacing) is forbidden.
- **`Closes #<hq:plan>` trailer** — every PR body MUST end with this line.
- **`Refs #<hq:task>` trailer** — required when the `hq:plan` has a parent `hq:task`; the `Refs` line MUST follow `Closes`. Omitted entirely when no parent exists — the PR body then ends with only `Closes #<hq:plan>`.
- **`hq:pr` label** — every PR created by the `pr` skill (in either invocation mode — Standalone or via `/hq:start`) MUST carry the `hq:pr` label.
- **Milestone / project inheritance** *(only when the plan has a parent `hq:task`)* — if the source `hq:task` has a milestone or project(s), the PR MUST inherit them via `--milestone` / `--project` flags. When no parent exists, omit these flags entirely — there is nothing to inherit from.

A newly bootstrapped repository should understand these rules from this section alone — `.hq/pr.md` overrides are applied on top, never in place of, the invariants above.

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

**`covers_acceptance` frontmatter (optional, soft convention)** — FB files MAY include a `covers_acceptance: "<unique substring of an acceptance item>"` frontmatter field linking the FB to the specific `## Acceptance` item it covers. Populate this field in Phase 4/5-origin FBs (where the correspondence is 1:1 with an acceptance item by construction); leave it unset on Phase 6-origin FBs (Quality Review and self-review-gate findings that do not map 1:1 to an acceptance item). No hook or script enforces this field — it exists to make the audit trail linear for reviewers and to support the Phase 5 1-by-1 toggle rule. See [feedback.md](feedback.md) for the full schema.

### FB Lifecycle (for the root agent)

FB handling is **phase-dependent** — different phases generate FBs for different reasons, and the response differs accordingly:

- **Phase 4 (Execute) FBs** — continue-report on blocked / ambiguous / failed-twice steps. The root agent captures the residual as an FB so the work can continue, and the FB later escalates to the PR's `## Known Issues` (Phase 7).
- **Phase 5 (Acceptance) FBs** — continue-report on `[auto]` checks that exhausted the Phase 5 retry cap. Per `/hq:start § Phase 5`, the checkbox is toggled `[x]` anyway and the failure is tracked by the FB. The FB escalates to `## Known Issues` at Phase 7.
- **Phase 6 (Quality Review) FBs** — Phase 6 is **pure review, no auto-fix**. Every FB produced by the Quality Review (Self-Review Gate Step 0 minor gaps + agent-emitted findings from Step 2) flows **directly** to `## Known Issues` at Phase 7, regardless of severity (Critical through Low) and regardless of clarity (clearly-actionable through design-ambiguous). The root agent does NOT inline-fix Phase 6 FBs — the user (or `/hq:triage` post-merge) decides each FB's disposition.

**No batch-fix loop, no round counter, no severity gate.** Phase 6 is pure review: prior architecture's batch-fix loop, severity-based threshold gate, and Low-severity-specific exit rules are retired alongside the move to pure review. The motivation is that auto-fixing Quality Review FBs risks scope creep (重箱の隅をつく fix triggering unrelated regressions) — leaving the fix decision to the human aligns with the Karpathy-loop bounded-scope principle and is consistent across all severity levels.

**FB → `feedbacks/done/`** — an FB file moves to `feedbacks/done/` only when its content is surfaced in the PR body's `## Known Issues` (Phase 7's atomic write+move). There is no other path to `done/`. Files do not get modified or deleted at any other point.

**Atomicity** — escalation into `## Known Issues` and the move to `feedbacks/done/` are a single atomic operation. Surfacing an FB in the PR body without moving its file (or moving the file without surfacing the content) is forbidden. This atomicity cannot be skipped or weakened by project-level overrides such as `.hq/pr.md` — see `## PR Body Structure` § Invariants.

**Note**: FB escalation to `hq:feedback` Issues happens during PR review via `/hq:triage` — not from `/hq:start`, `/pr`, or `/hq:archive`. Local FB files are a **branch-internal** concept; the PR body's `## Known Issues` is the hand-off point.

## Retrospective

Per-run reflective analysis written by `/hq:start` Phase 8 (Retrospective) to a Markdown artifact at `.hq/retro/<branch-dir>/<plan>.md`. The artifact lets the run be re-examined after the fact — *was each Phase 6 (Quality Review) FB a valid detection? Could it have been prevented at implementation time? If so, by what lever?* — without re-reading session transcripts. The hypothesis is that a non-trivial fraction of Phase 6 FBs are preventable at implementation time, and structured per-FB analysis exposes the recurring levers.

`.hq/retro/` follows `.hq/` semantics: gitignored (covered by the existing `.hq` entry), per-clone, branch-local. Worktree copy is not propagated by `worktree-setup.sh` — retro is the run's frozen output, not project-wide configuration. Team-wide aggregation, if ever required, is a separate plan.

### File path

```
.hq/retro/<branch-dir>/<plan>.md
```

`<branch-dir>` = branch name with `/` → `-` (same convention as `.hq/tasks/<branch-dir>/`). `<plan>` = bare `hq:plan` issue number (e.g., `75`). One file per `/hq:start` run; auto-resume sessions overwrite the existing file because the artifact captures the latest run snapshot, not a per-session history.

### Fixed schema

The artifact has exactly **three** top-level Markdown sections, in this order:

1. **`## Run Summary`** — facts about the run, all derivable from existing JSONL events + git log + plan cache (no LLM judgment in this section). Fields:
   - plan id, branch name, run timestamp (UTC, ISO 8601)
   - phase wall-clock durations (read `.hq/tasks/<branch-dir>/phase-timings.jsonl` via `phase-timing.sh summary`)
   - total commits made on the branch (`git rev-list --count <base>..HEAD`)
   - Phase 6 Self-Review Gate result + Agent Selection mode and launched / skipped agents (read `.hq/tasks/<branch-dir>/quality-review-events.jsonl` via `quality-review.sh summary`)
   - Per-agent initial FB counts and severity breakdown
   - counts of FB files in `feedbacks/done/` and `feedbacks/` (residual)

2. **`## FB Analysis`** — one entry per FB file under `.hq/tasks/<branch-dir>/feedbacks/done/` at Phase 8 entry time. Under the post-refactor pure-review Phase 6, FBs reach `done/` via a single path: Phase 7's atomic `## Known Issues` write + `done/` move (per `## Feedback Loop`). There is no Phase 5 / Phase 6 in-branch resolution path anymore.

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

   When `feedbacks/done/` has no FB files at Phase 8 entry (which occurs when no FBs were generated across the entire run — Phase 4 / 5 / 6 all clean), `## FB Analysis` is still emitted with the literal body `(no FBs to analyze)` — do NOT omit the section. The fixed three-section structure is the primary acceptance gate, and an absent section breaks it.

3. **`## Reflection`** — free-form prose, ≤ 8 sentences. State what went well, what could improve, and any pattern visible across the FB Analysis entries (e.g., "many FBs marked `preventable_at_implementation: yes` with `prevention_lever: smaller-commit-grain` — next run should split implementation steps before committing"). Self-praise without a concrete pattern citation is the failure mode this section guards against — the LLM is the author and the analysis subject simultaneously, so explicit pattern citation is what keeps the section honest.

### Per-FB analysis fields

The per-FB block has **two parts**: (1) a YAML fence carrying **3 categorical axes** with closed enumerations, and (2) a `**Notes**` field below the fence — free-form Markdown, ≤ 2 sentences. The split is deliberate: the YAML axes are the aggregable structured surface (strict enumeration is what makes cross-run analysis tractable when an active loop is built later); the `Notes` field is the human-readable elaboration that does not need to fit a closed schema. Free-form prose MUST stay in `Notes`, never in axis values.

**YAML axes (closed enumerations):**

| Axis | Values | Meaning |
|---|---|---|
| `detection_validity` | `valid` / `invalid` / `borderline` | Was the QR detection itself sound? `valid` — yes, the FB names a real defect. `invalid` — false positive, the agent was wrong. `borderline` — defensible but the call could have gone either way. |
| `preventable_at_implementation` | `yes` / `no` / `partial` | Could this have been caught during Phase 4 (Execute) instead of surfacing in Phase 6? `yes` — clearly yes, a discipline gap. `no` — only QR's external lens could see it. `partial` — partially preventable; the underlying signal was reachable but the specific framing required QR. |
| `prevention_lever` | `stricter-acceptance` / `smaller-commit-grain` / `reuse-existing` / `better-pre-read` / `plan-discipline` / `n/a` | If preventable, by what change in workflow? `stricter-acceptance` — the plan's `## Acceptance` would have caught it if tightened. `smaller-commit-grain` — splitting the commit would have surfaced it. `reuse-existing` — reaching for an existing mechanism instead of new code would have avoided it. `better-pre-read` — reading the surrounding code more carefully before editing would have caught it. `plan-discipline` — the gap was a Phase 2 / Phase 4 plan-vs-diff discipline issue (over-declared `## Editable surface`, Boundary expansion protocol not invoked when stack-natural extension required it, speculative `(consumer: <name>)` declarations) — adhering to the workflow's plan/diff contract would have prevented Phase 6 from surfacing it. `n/a` — applies when `preventable_at_implementation` is `no`, OR when `detection_validity` is `invalid` (false positive — the question of prevention does not apply to a defect that did not exist). |

**Markdown field (free-form):**

- `**Notes**` — ≤ 2 sentences, factual elaboration. No rationalization. No praise. Lives below the YAML fence in the per-FB entry template; not part of the YAML block.

Adding axis values or introducing a new YAML axis is a deliberate change to this rule file; runtime composition MUST NOT invent values or add keys.

### Future active loop (out of scope here)

Reading retro files back into `/hq:draft` Phase 2 (Simplicity gate priors) or `/hq:start` Phase 1 (pre-flight priors) is **deliberately not implemented** in the current writer. The judgment is that the writer side should accumulate enough artifacts to evaluate before designing the consumer side. When the consumer is added, it ships as a **separate `hq:plan`**, not as an extension to this section.
