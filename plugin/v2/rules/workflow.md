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

Runtime-generated content — `hq:task` / `hq:plan` / PR bodies — is authored in the **conversation language** (the language the user is speaking in this session). Workflow markers and prescribed structural headings stay in **English** regardless, so downstream tooling can parse them.

- **English (fixed)**:
  - Workflow markers: `Parent: #N`, `[auto]`, `[manual]`, `[primary]`, `Closes #<plan>`, `Refs #<task>`
  - Prescribed headings: `## Plan Sketch`, `## Plan`, `## Acceptance`, `## Primary Verification (manual)`, `## Manual Verification`, `## Known Issues`, `## Summary`, `## Changes`, `## Notes`
  - File paths, identifiers, code fences, shell commands
- **Conversation language (content)**:
  - `hq:task` body (background / requirements / scope / success criteria)
  - `hq:plan` body content — `## Plan Sketch` prose (Problem / Editable surface / Read-only surface / Impact table cells / Core decision / Constraints), each `## Plan` step description, each `## Acceptance` condition
  - PR body prose — text inside `## Summary` / `## Changes` / `## Notes` and free-form narrative under `## Known Issues`
  - Any free-form section headings the author introduces (e.g., `### 背景`, `### Requirements`)

This rule applies to every skill and command that generates Issue or PR content — `/hq:draft`, `/hq:start` (fallback drafting), and the `pr` skill.

## Issue Hierarchy

```
Parented mode:
  Milestone (GitHub built-in, optional)
    └── hq:task Issue  — requirement ("what")
          └── hq:plan Issue  — implementation plan ("how")
                ├── ← Closes → PR  (Refs #hq:task)
                │     └── ← /hq:triage → hq:feedback Issue(s)  (residual, Refs #plan)
                └── (or escalated during PR review via /hq:triage)

Standalone mode (no parent hq:task):
  hq:plan Issue  — implementation plan ("how"); top-level, requirement captured in ## Plan Sketch / **Problem**
    ├── ← Closes → PR  (no Refs trailer)
    │     └── ← /hq:triage → hq:feedback Issue(s)  (residual, Refs #plan)
    └── (or escalated during PR review via /hq:triage)
```

- `hq:task` and `hq:plan` are separate issues (separation of concerns)
- **`hq:task` is optional** — an `hq:plan` can be created without a parent `hq:task` via `/hq:draft` **standalone mode**. Use this when the requirement already lives in an external tracker, or for 1:1 cases where a separate requirement Issue is pure overhead. In standalone mode, the plan's `## Plan Sketch` / `**Problem**` becomes the sole source of truth for the requirement.
- `hq:plan` is created as a **sub-issue** of its parent `hq:task` (GitHub sub-issues API) — **parented mode only**. Standalone-mode plans are top-level Issues with no parent.
- PR uses `Closes #<hq:plan>` to auto-close the plan issue on merge
- PR uses `Refs #<hq:task>` to maintain a link to the requirement — **parented mode only**; omitted when the plan has no parent `hq:task`
- **Traceability inheritance** — if the source `hq:task` has a milestone or project(s), all generated items (`hq:plan`, PR, `hq:feedback`) must inherit them via `--milestone` / `--project` flags. Exception: `hq:feedback` issues do NOT inherit milestones. In standalone mode there is no `hq:task` to inherit from, so milestone / project are left unset.
- Labels are created lazily at first use:
  - `gh label create "hq:task" --description "HQ requirement (what to do)" --color "39FF14" 2>/dev/null || true`
  - `gh label create "hq:plan" --description "HQ implementation plan (how to do it)" --color "00D4FF" 2>/dev/null || true`
  - `gh label create "hq:feedback" --description "HQ unresolved feedback" --color "FF073A" 2>/dev/null || true`
  - `gh label create "hq:doc" --description "HQ informational note / research findings (not a direct task)" --color "5319E7" 2>/dev/null || true`
  - `gh label create "hq:pr" --description "HQ PR associated with an hq:plan" --color "8A2BE2" 2>/dev/null || true`
  - `gh label create "hq:wip" --description "HQ work in progress — automation gate / drafting marker" --color "FFA500" 2>/dev/null || true`
  - `gh label create "hq:manual" --description "HQ PR marker — plan has [manual] [primary] acceptance (manual primary verification required)" --color "FFD700" 2>/dev/null || true`

## `hq:plan`

An `hq:plan` issue is the implementation plan that drives work on a branch. The issue body IS the source of truth for what needs to be done and how completion is verified.

The `hq:plan` body follows a 3-section structure: `## Plan Sketch` + `## Plan` + `## Acceptance`. Emission rules:

- Angle-bracket `<placeholder>` tokens are substituted with real content.
- The `Parent:` line is emitted only in **parented mode** (when the plan has a parent `hq:task`); omit it entirely in **standalone mode**.
- Optional fields with no substantive content are **omitted entirely** — no label, no placeholder line. Never write `_None._` / `Not applicable` / padded prose as filler.

```markdown
Parent: #<hq:task issue number>

## Plan Sketch

**Problem** — <1-3 sentences: pain and why now>

**Change Map** *(optional — Mermaid or ASCII figure showing before/after shape; include only when a figure clarifies structure more than prose)*

**Editable surface**
- <file / symbol that this plan MAY modify>

**Read-only surface**
- <file / symbol that this plan MUST NOT modify>

**Impact**

| Direction | Surface | Kind | Note |
|---|---|---|---|
| Add | <new surface> | <field / marker / section / command / ...> | <short note> |
| Update | <changed surface> | <...> | <what changes> |
| Delete | <removed surface> | <...> | <...> |
| Contradict | <semantically-shifted surface> | <...> | <how existing callers may break silently> |
| Downstream | <consumer needing coordinated update> | <file / section> | <...> |

**Core decision** — <1-2 sentences: the key architectural choice>

**Constraints** *(optional)*
- <hard dependency / prerequisite / assumption>

## Plan
- [ ] <implementation step — single meaningful commit unit>

## Acceptance
- [ ] [auto] [primary] <the single concrete pass/fail signal that tells the plan succeeded>
- [ ] [auto] <secondary verifiable check>
- [ ] [manual] <human-eye check, used sparingly>
```

### `## Plan Sketch`

`## Plan Sketch` is the single scannable section that captures motivation, scope boundaries, surface-level impact, and the core design decision. All fields below are bold-labeled blocks within this one heading.

- **`**Problem**`** *(required)* — the pain and why now. 1-3 sentences.
- **`**Change Map**`** *(optional)* — a Mermaid or ASCII figure showing the before/after shape, included only when the structure of the change reads better as a figure than as prose. GitHub renders Mermaid natively in issue bodies. Omit when a figure would be forced.
- **`**Editable surface**`** *(required)* — files or symbols this plan MAY modify. Declared explicitly so the implementation phase has an unambiguous "may touch" list.
- **`**Read-only surface**`** *(required)* — files or symbols this plan MUST NOT modify. The symmetric counterpart to `**Editable surface**` — together they close the set of "what's in play" vs "what stays put". Include adjacent surfaces a reader might assume are in scope but are not.
- **`**Impact**`** *(required whenever any non-trivial surface is touched)* — a 4-column table: `Direction` / `Surface` / `Kind` / `Note`. The `Direction` column uses a closed set of 5 values:
  - **`Add`** — a new surface is introduced (new function / field / command / config key / section / label / file path).
  - **`Update`** — an existing surface's contract changes (arguments, return shape, emission rules, accepted values).
  - **`Delete`** — an existing surface is removed.
  - **`Contradict`** — the surface's signature is stable but its semantics shift, potentially breaking existing callers silently. These are the highest-risk entries — flag them clearly in the `Note` column.
  - **`Downstream`** — a consumer of the edited surface needs a coordinated update (docs, tests, other commands / skills / agents, README, templates, distribution artifacts).

  Omit rows for directions that do not apply. If all 5 directions would be empty, the change is trivial and the `**Impact**` block itself can be skipped.
- **`**Core decision**`** *(required)* — 1-2 sentences on the key architectural choice. If there is no genuine decision to highlight, the plan probably does not need a `## Plan Sketch` at all.
- **`**Constraints**`** *(optional)* — hard dependencies, prerequisites, or assumptions. Omit when genuinely empty.

### `## Plan`

Implementation steps as a checkbox list. Every item must be `[x]` before PR creation.

**Granularity — ideal 1-5 items, upper bound 10.** Each item is a **single meaningful commit unit** — something that reads as one independent change in `git log` afterward:

- If two consecutive items would edit the same file in the same editing session, they are **one item**, not two.
- If an item would produce a half-working intermediate state, it is split wrong — merge upward with its neighbor.
- 1-item plans are valid (atomic change).
- 6-10 items is acceptable when the change genuinely spans that many independent concerns.
- Past 10 items is a drafting defect to fix, not a ceiling to plan up to. 10+ items signals the plan is being written as a step-by-step instruction manual rather than a commit-grain list.

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
- **(c) `**Impact**` table is structurally bounded** — the Impact table declares every populated `Direction` row for the change. Under-declared Impact lets an unmeasured primary hide behind unmeasured scope; the escape hatch requires the surface to be tight.

**Compensating controls (required whenever the escape hatch fires)**:

- **Evidence schema** — the PR body MUST carry a `## Primary Verification (manual)` section populated per the template in `## PR Body Structure` below. A screenshot or video link plus a reviewer checklist of ≥3 concrete observations decomposing the primary's observable into verifiable parts. A bare checkbox is not acceptable.
- **Label + gate** — the PR MUST carry the `hq:manual` label (applied by the `pr` skill at `/hq:start` Phase 7). The Phase 7 gate MUST assert the `## Primary Verification (manual)` section is present and populated; missing evidence blocks PR creation.

**Runtime behavior**:

- `/hq:start` Phase 5 does NOT execute `[manual] [primary]` (same as other `[manual]` items — the Phase 5 sweep ignores `[manual]`). Phase 8 Report surfaces the item as **`[primary deferred]`** — the sibling notice to `[primary failure]`, signalling the single most important signal is pending reviewer judgment rather than failed.
- Final pass/fail judgment happens at PR review. Reviewer uses the evidence block to verify the observable was actually achieved; merge approval is the explicit ack gate.

**Rollback path**: if `[manual] [primary]` usage drifts beyond the domains above (e.g., selected for web features where `/hq:e2e-web` was available), tighten condition (a) to enumerate permitted domains explicitly. No automated drift monitor is built into this workflow version — PR review is the safety net.

### Registration

After creating an `hq:plan` issue **in parented mode**, register it as a sub-issue of the parent `hq:task`:

```bash
PLAN_ID=$(gh api /repos/{owner}/{repo}/issues/<plan> --jq '.id')
gh api --method POST /repos/{owner}/{repo}/issues/<task>/sub_issues --field sub_issue_id="$PLAN_ID"
```

In **standalone mode** (no parent `hq:task`), skip sub-issue registration entirely.

### Self-contained invariant

Every `hq:plan` must:

- Be **self-contained** — it survives session clears (it lives on GitHub, not locally).
- Define **`## Plan`** (implementation steps) and **`## Acceptance`** (completion criteria, including exactly one `[auto] [primary]` item).
- Follow the **Language** rule above — content in the conversation language, markers and prescribed headings in English.
- Keep Acceptance checks atomic and verifiable — each `[auto]` item maps to a single concrete signal (pass/fail).

### Focus

**Focus** is a pointer to the `hq:plan` issue currently driving work. It is stored in two places:

1. **`.hq/tasks/<branch-dir>/context.md`** — deterministic file (branch name: `/` → `-`). Agents and skills resolve focus from this file.
2. **Memory** — a project-type memory entry for cross-session awareness. Lets new sessions know what was in progress.

**context.md format** (frontmatter YAML — no free-text body). In parented mode all keys below are present; `source` and `gh.task` are **omitted entirely in standalone mode** (see field descriptions).

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
- `source` — **optional**. The `hq:task` issue number this plan implements. Present in parented mode (the normal case); **omitted in standalone mode** (plans created via `/hq:draft` without an `hq:task` argument).
- `branch` — **MUST**. The original git branch name (with slashes). Lets tooling check out the correct branch given a plan number (the directory name has `/` → `-` transformation which is not reliably invertible).
- `gh` — paths to the local GitHub issue cache (see Cache-First Principle below). `gh.plan` is always present; `gh.task` is present only when `source` is set (parented mode).

**Lifecycle**:

- **On start** (`/hq:start`): write `.hq/tasks/<branch-dir>/context.md`. Save focus info to your memory (project type) — include the branch name, plan number, and source number (omit source when the plan has no parent `hq:task`).
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
- <unresolved FB title and brief description>
- <another known issue>

Closes #<hq:plan>
Refs #<hq:task>
```

The `Refs #<hq:task>` line is emitted **only in parented mode** — when the `hq:plan` has a parent `hq:task`. In standalone mode, omit the line entirely; the trailer block then contains only `Closes #<hq:plan>`.

- **`## Primary Verification (manual)`** — present **only** when the plan's `## Acceptance` has a `[manual] [primary]` item (escape hatch). Holds the evidence block required for reviewer to verify the escape hatch primary. Omitted entirely when the plan has `[auto] [primary]`.
- **`## Manual Verification`** — all unchecked `[manual]` items from the Acceptance section (excluding the `[manual] [primary]` item, which lives in its own section above), for user verification during PR review.
- **`## Known Issues`** — unresolved issues that `/hq:start` could not auto-fix. **This becomes the source of truth for residual problems.** The corresponding local FB files are moved to `feedbacks/done/` at PR creation time (see FB Lifecycle below).
- If either section is empty, omit it.

During PR review, use `/hq:triage <PR>` to process the `Known Issues` entries — each can be: (1) added to the `hq:plan` for follow-up work, (2) left as-is, or (3) carved out as an `hq:feedback` Issue.

### Invariants (NOT overridable by `.hq/pr.md`)

The following structural elements of the PR body are invariants of the HQ workflow. A project's `.hq/pr.md` (consumed by the `pr` skill) MAY customize prose style, language, title conventions, and optional sections — but it MUST NOT suppress, rename, reformat, or otherwise alter any item below:

- **`## Primary Verification (manual)` section presence** — whenever a `[manual] [primary]` item exists in the plan's `## Acceptance` section at PR creation time (escape hatch — see `### `## Acceptance`` § `#### [manual] [primary] escape hatch`), the PR body MUST contain a section literally named `## Primary Verification (manual)`. The section MUST include: the primary item verbatim, an evidence link (screenshot / video), and a reviewer checklist of ≥3 concrete observations. A bare checkbox without evidence or checklist is insufficient; the `/hq:start` Phase 7 gate blocks PR creation when this block is missing or incomplete.
- **`hq:manual` label** — whenever a `[manual] [primary]` item exists in the plan's `## Acceptance` section at PR creation time, the PR MUST carry the `hq:manual` label (in addition to `hq:pr`). Applied by the `pr` skill.
- **`## Manual Verification` section presence** — whenever unchecked `[manual]` items exist in the plan's `## Acceptance` section at PR creation time (excluding the `[manual] [primary]` item, which is covered by `## Primary Verification (manual)` above), they MUST appear verbatim under a section literally named `## Manual Verification`.
- **`## Known Issues` section presence** — whenever pending FB files exist at PR creation time, their titles + brief descriptions MUST appear under a section literally named `## Known Issues`.
- **FB atomic move to `feedbacks/done/`** — any FB file whose content is surfaced in `## Known Issues` MUST be moved to `feedbacks/done/` as part of the same PR-creation operation. Surfacing without moving (or moving without surfacing) is forbidden.
- **`Closes #<hq:plan>` trailer** — every PR body MUST end with this line.
- **`Refs #<hq:task>` trailer** — required when the `hq:plan` has a parent `hq:task` (parented mode); the `Refs` line MUST follow `Closes`. Omitted entirely when the plan is in standalone mode (no parent) — the PR body then ends with only `Closes #<hq:plan>`.
- **`hq:pr` label** — every PR created by the `pr` skill (in either invocation mode — Standalone or via `/hq:start`) MUST carry the `hq:pr` label.
- **Milestone / project inheritance** *(parented mode only)* — if the source `hq:task` has a milestone or project(s), the PR MUST inherit them via `--milestone` / `--project` flags. In standalone mode (no parent `hq:task`), omit these flags entirely — there is nothing to inherit from.

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

**`covers_acceptance` frontmatter (optional, soft convention)** — FB files MAY include a `covers_acceptance: "<unique substring of an acceptance item>"` frontmatter field linking the FB to the specific `## Acceptance` item it covers. Populate this field in Phase 4/5-origin FBs (where the correspondence is 1:1 with an acceptance item by construction); leave it unset on Phase 6-origin FBs (code-reviewer / integrity-checker findings that do not map 1:1 to an acceptance item). No hook or script enforces this field — it exists to make the audit trail linear for reviewers and to support the Phase 5 1-by-1 toggle rule. See [feedback.md](feedback.md) for the full schema.

### FB Lifecycle (for the root agent after a skill run)

- Read pending FB files and assess each: fix only those that are clearly actionable (bugs, typos, logic errors). Leave design-level or scope-ambiguous FBs as-is for user judgment.
- Run `format` and `build` commands after fixes
- Re-run the originating agent only to verify the specific FB is gone. Do NOT re-run the full agent set — cross-agent regression is accepted as a trade-off for review token cost
- When an FB item is **resolved in-branch**, move its file to `feedbacks/done/`
- When an FB item is **escalated to the PR body's `## Known Issues`** at PR creation time, move its file to `feedbacks/done/` as well — its role has shifted to the PR body (now the source of truth for residual problems)
- The fix → re-verify cycle runs up to the caller's **FB retry cap**, applied **per FB independently** (FB A's failed retries do not consume FB B's budget). `/hq:start` defines its cap in its `## Settings` section (default `2`); other callers MUST supply their own. When the cap is exhausted on a given FB, escalate that FB to the PR body and move its file to `done/`.
- Do not modify or delete FB files — only move resolved/escalated ones to `done/`

**Atomicity** — escalation into `## Known Issues` and the move to `feedbacks/done/` are a single atomic operation. Surfacing an FB in the PR body without moving its file (or moving the file without surfacing the content) is forbidden. This atomicity cannot be skipped or weakened by project-level overrides such as `.hq/pr.md` — see `## PR Body Structure` § Invariants.

**Note**: FB escalation to `hq:feedback` Issues happens during PR review via `/hq:triage` — not from `/hq:start`, `/pr`, or `/hq:archive`. Local FB files are a **branch-internal** concept; the PR body's `## Known Issues` is the hand-off point.
