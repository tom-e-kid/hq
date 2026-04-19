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

## Commit Policy

`/hq:start` commits as work progresses, not at the end. Commits are the unit of work — they make `/hq:start` resume-safe, keep the PR reviewable, and ensure the working tree is clean by the time the PR is created.

Commit granularity by phase:

- **Phase 4 (Execute)** — **one commit per `## Plan` item**. After implementing a step and checking its cache checkbox, create a commit whose subject matches the Plan item. Use Conventional Commits types (`feat`/`fix`/`refactor`/`docs`/`chore`/`test`).
- **Phase 5 (Simplify)** — if `/simplify` produces changes, create a **single commit** `refactor: simplify <short summary>`. If no changes, no commit.
- **Phase 6 (Acceptance)** — if an `[auto]` check fails and is fixed, create a `fix: <what was wrong>` commit per fix. No commit for pure test runs.
- **Phase 7 (Quality Review)** — one commit per resolved FB. Subject derived from the FB title (e.g., `fix: <FB subject>`).
- **Phase 8 (PR Creation)** — no new commits. The working tree MUST be clean at this point; the `pr` skill will not prompt about uncommitted changes.

All commits must pass `## Before Commit` (format + build). Do not skip hooks.

If you discover mid-phase that an earlier commit needs fixing, prefer a new `fix:` commit over `--amend` to keep history linear and resume-safe.

## Terminology

- **`hq:workflow`** — shorthand for `.claude/rules/workflow.local.md` (the project-local copy of the workflow rule file, produced by `/hq:bootstrap`). Skills and commands cite sections as `hq:workflow § <section>` instead of repeating the full path.
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
  - Workflow markers: `Parent: #N`, `[auto]`, `[manual]`, `Closes #<plan>`, `Refs #<task>`
  - Prescribed headings: `## Plan`, `## Acceptance`, `## Context`, `## Approach`, `## Manual Verification`, `## Known Issues`, `## Summary`, `## Changes`, `## Notes`
  - File paths, identifiers, code fences, shell commands
- **Conversation language (content)**:
  - `hq:task` body (background / requirements / scope / success criteria)
  - `hq:plan` body content — `## Context` / `## Approach` prose, each `## Plan` step description, each `## Acceptance` condition
  - PR body prose — text inside `## Summary` / `## Changes` / `## Notes` and free-form narrative under `## Known Issues`
  - Any free-form section headings the author introduces (e.g., `### 背景`, `### Requirements`)

This rule applies to every skill and command that generates Issue or PR content — `/hq:draft` (Plan agent output), `/hq:start` (fallback drafting), and the `pr` skill.

## Issue Hierarchy

```
Milestone (GitHub built-in, optional)
  └── hq:task Issue  — requirement ("what")
        └── hq:plan Issue  — implementation plan ("how")
              ├── ← Closes → PR
              │     └── ← /hq:triage → hq:feedback Issue(s)  (residual, Refs #plan)
              └── (or escalated during PR review via /hq:triage)
```

- `hq:task` and `hq:plan` are separate issues (separation of concerns)
- `hq:plan` is created as a **sub-issue** of its parent `hq:task` (GitHub sub-issues API)
- PR uses `Closes #<hq:plan>` to auto-close the plan issue on merge
- PR uses `Refs #<hq:task>` to maintain a link to the requirement
- **Traceability inheritance** — if the source `hq:task` has a milestone or project(s), all generated items (`hq:plan`, PR, `hq:feedback`) must inherit them via `--milestone` / `--project` flags. Exception: `hq:feedback` issues do NOT inherit milestones.
- Labels are created lazily at first use:
  - `gh label create "hq:task" --description "HQ requirement (what to do)" --color "39FF14" 2>/dev/null || true`
  - `gh label create "hq:plan" --description "HQ implementation plan (how to do it)" --color "00D4FF" 2>/dev/null || true`
  - `gh label create "hq:feedback" --description "HQ unresolved feedback" --color "FF073A" 2>/dev/null || true`
  - `gh label create "hq:doc" --description "HQ informational note / research findings (not a direct task)" --color "5319E7" 2>/dev/null || true`
  - `gh label create "hq:pr" --description "HQ PR associated with an hq:plan" --color "8A2BE2" 2>/dev/null || true`
  - `gh label create "hq:wip" --description "HQ work in progress — automation gate / drafting marker" --color "FFA500" 2>/dev/null || true`

## `hq:plan`

An `hq:plan` issue is the implementation plan that drives work on a branch. The issue body IS the source of truth for what needs to be done and how completion is verified.

The `hq:plan` issue body **must** follow this structure:

```markdown
Parent: #<hq:task issue number>

## Context
<optional — when present, use the labeled blocks below>

**Problem** — <pain / why now>

**In scope**
- <what's touched>

**Out of scope** *(optional — include only when scope is ambiguous or at risk of creep)*
- <explicit exclusions>

**Constraints** *(optional)*
- <hard dependencies / prerequisites / assumptions>

## Approach
<optional — when present, use the labeled blocks below>

**Core decision** — <key architectural choice>

**<Aspect label>** — <short detail inline>
or
**<Aspect label>**
- <bullet>
- <bullet>

**Alternatives considered** *(optional)*
- <rejected option> — <reason>

## Plan
- [ ] implementation step 1
- [ ] implementation step 2
- [ ] implementation step 3

## Acceptance
- [ ] [auto] <self-verifiable check, e.g., `pnpm test` passes>
- [ ] [auto] <e.g., `/api/auth/login` returns 200>
- [ ] [manual] <requires user confirmation, e.g., browser UI check>
```

- **`## Context`** *(optional)* — why this plan exists: motivation, scope boundary, constraints. Captures the reasoning behind the plan that would otherwise evaporate from the `/hq:draft` conversation. When present, use these bold-labeled blocks:
  - `**Problem**` *(required)* — the pain and why now (1-3 sentences)
  - `**In scope**` *(required)* — bullets of what's touched (files, features, screens)
  - `**Out of scope**` *(optional)* — bullets of explicit exclusions. Include only when scope is genuinely ambiguous or at real risk of creep; otherwise omit the block entirely
  - `**Constraints**` *(optional)* — hard dependencies, prerequisites, or assumptions
- **`## Approach`** *(optional)* — high-level implementation direction and key design decisions. Complements the concrete `## Plan` steps by explaining the method. When present, use these bold-labeled blocks:
  - `**Core decision**` — 1-2 sentences on the key architectural choice. Required when `## Approach` is present; if there is no real design decision to highlight, prefer to omit `## Approach` entirely (with `_Intentionally omitted: <reason>._`)
  - `**<Aspect label>**` *(free-form, as many as needed)* — one block per distinct component or concern (new helper, API change, mapping, etc.). Short content inline after an en-dash; long content uses a bullet sublist
  - `**Alternatives considered**` *(optional)* — rejected options with a one-line reason each
- **`## Plan`** — implementation steps (ToDo list). All items must be checked before PR creation. Progress is visible in the GitHub UI.
- **`## Acceptance`** — verifiable completion criteria. Each item is tagged with an execution marker:
  - **`[auto]`** — Claude can verify autonomously using available tools. This includes unit / integration test runs, type checks, builds, shell / CLI commands, API calls, file and directory checks, **and browser automation via `/hq:e2e-web` (Playwright)** — navigation, URL assertions, element / text presence, form submit flows, DOM state checks. Executed during `/hq:start` verification phase.
  - **`[manual]`** — requires human judgment that tools cannot provide. Four conditions qualify: (1) **subjective** — aesthetics, UX feel, "does this look right"; (2) **physical device or assistive tech** — touch gestures on real devices, screen reader flow, real-world accessibility audits; (3) **live production or sensitive credentials** — checks that require prod auth or customer data Claude should not handle; (4) **multi-session / cross-tab scenarios** Playwright cannot reliably orchestrate. Carried into the PR body and verified by the user during PR review.

**Choosing `[auto]` vs `[manual]`** — default to `[auto]`. A check is `[manual]` only when one of the four conditions above genuinely applies. **"It happens in a browser" alone does NOT justify `[manual]`** — `/hq:e2e-web` drives browser UI deterministically via Playwright. When unsure, mark as `[auto]` and let `/hq:start` Phase 6 execution surface the gap if the check is not actually automatable.

Examples:

| Check | Marker | Why |
|---|---|---|
| Click "Save" → page URL becomes `/issues/{id}` | `[auto]` | Playwright URL assertion |
| Form submit → DB row exists | `[auto]` | API / DB check |
| Back button on direct-loaded `/issues/{id}/edit` navigates to `/issues/{id}` | `[auto]` | Playwright navigation |
| `pnpm test` passes | `[auto]` | Shell command |
| Back button's icon matches app's visual style | `[manual]` | Subjective / visual |
| Swipe-back gesture feels responsive on iOS Safari | `[manual]` | Physical device |
| Two browser tabs each show the correct tenant after login | `[manual]` | Multi-session orchestration |

**Principle — clarity first, not form-filling.** The labeled blocks above are scaffolding to structure thinking and make the plan scannable. They are **not** a form to fill. If a field would contain fabricated or padded content, omit it:

- **Optional fields** (`Out of scope`, `Constraints`, `Alternatives considered`) — leave them out entirely. No label, no placeholder.
- **Required fields** (`Problem`, `In scope`, `Core decision`) that feel genuinely empty — rethink whether the parent section (`## Context` / `## Approach`) applies at all. If not, omit the whole section with `_Intentionally omitted: <reason>._`. If the section genuinely applies but a required field is still empty, the plan likely needs more thought rather than a placeholder.

Never write filler like `_None._` or "Not applicable" as a substitute for thinking.

**Optional section omission** — when `## Context` or `## Approach` is omitted, do NOT silently drop the heading. Keep the heading and write a single italic line stating the reason, e.g.:

```markdown
## Approach
_Intentionally omitted: <one-line reason>._
```

This signals the author considered the section and chose to leave it empty (vs. forgot it). The preferred form is always "heading present + explicit omission"; silently dropping the heading is discouraged.

After creating an `hq:plan` issue, register it as a sub-issue of the parent `hq:task`:

```bash
PLAN_ID=$(gh api /repos/{owner}/{repo}/issues/<plan> --jq '.id')
gh api --method POST /repos/{owner}/{repo}/issues/<task>/sub_issues --field sub_issue_id="$PLAN_ID"
```

Every `hq:plan` must:

- Be **self-contained** — it survives session clears (it's on GitHub, not local)
- Define **Plan** (implementation steps) and **Acceptance** (completion criteria)
- Follow the **Language** rule above — content in the conversation language, markers and prescribed headings in English
- Use the **explicit omission** form (`_Intentionally omitted: <reason>._`) when `## Context` or `## Approach` is left empty
- Before finalizing Acceptance checks, run `/simplify` to eliminate redundant or unnecessary code

### Round 2 Retry

When Round 1 of `/hq:start` (Phases 4 → 7) completes with pending FBs still on disk, `/hq:start` appends a `## Round 2` section to the `hq:plan` body and re-enters Phases 4 → 7 with that section as the new plan. Round 2 is a **one-shot extension** — there is no Round 3. Anything still unresolved after Round 2 flows to the PR's `## Known Issues`.

The `## Round 2` section structure:

```markdown
## Round 2

### Follow-ups from Round 1

**<FB id>: <FB title>**
- Root cause: <what went wrong in Round 1>
- Approach: <what Round 2 will do differently>
- Addressed by: `### Plan (Round 2)` item N, `### Acceptance (Round 2)` item M

(one block per pending FB)

### Plan (Round 2)
- [ ] follow-up implementation step 1
- [ ] follow-up implementation step 2

### Acceptance (Round 2)
- [ ] [auto] follow-up check 1
- [ ] [auto] follow-up check 2
```

Rules:

- `### Follow-ups from Round 1` is the narrative bridge: **one block per pending FB**, each stating what failed, the root cause inferred from Round 1, the Round 2 approach, and which Round 2 items address it.
- `### Plan (Round 2)` and `### Acceptance (Round 2)` follow the same conventions as the Round 1 counterparts (checkbox, `[auto]`/`[manual]` markers, Commit Policy applies per item).
- Phase 8 Gate treats Round 2 items identically to Round 1 — all `- [ ]` under both sections must be `[x]` before PR creation.
- Round 2 drafting is authored by the `/hq:start` root agent (not the Plan agent) from FB contents and Phase 7 review outputs — `/hq:draft` is not re-invoked.
- **Round 1 FB ownership ends at drafting** — as soon as Round 1 FB content is absorbed into `### Follow-ups from Round 1`, the corresponding FB files MUST be moved to `feedbacks/done/` atomically. Only FBs produced during Round 2 remain pending for the Phase 8 Known Issues section.

If Round 1 produces zero pending FBs, skip Round 2 entirely and proceed to Phase 8 PR Creation.

### Focus

**Focus** is a pointer to the `hq:plan` issue currently driving work. It is stored in two places:

1. **`.hq/tasks/<branch-dir>/context.md`** — deterministic file (branch name: `/` → `-`). Agents and skills resolve focus from this file.
2. **Memory** — a project-type memory entry for cross-session awareness. Lets new sessions know what was in progress.

**context.md format** (frontmatter YAML — no free-text body):

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
- `source` — **MUST**. The `hq:task` issue number this plan implements. Focus cannot be set without a source.
- `branch` — **MUST**. The original git branch name (with slashes). Lets tooling check out the correct branch given a plan number (the directory name has `/` → `-` transformation which is not reliably invertible).
- `gh` — paths to the local GitHub issue cache (see Cache-First Principle below).

**Lifecycle**:

- **On start** (`/hq:start`): write `.hq/tasks/<branch-dir>/context.md`. Save focus info to your memory (project type) — include the branch name, plan number, and source number.
- **On status query**: read `.hq/tasks/<branch-dir>/context.md` → read the plan body from `.hq/tasks/<branch-dir>/gh/plan.md`. If cache not found, fall back to `gh issue view <plan> --json body --jq '.body'` → report status.
- **On completion**: when a PR is created and all Plan items + Acceptance `[auto]` items are checked, update your memory to indicate no active task. The PR's `Closes #<plan>` handles issue closure on merge. The `context.md` file is left in place — it travels with the task folder until `/hq:archive` moves it.

### Focus Resolution

When the user gives a **vague instruction** (e.g., "the auth task", "issue 42"), resolve the focus by searching in order:

1. **context.md** — check `.hq/tasks/<current-branch-dir>/context.md` for the current branch. If it exists, use it and confirm with the user: "Restored focus: plan=#X, source=#Y. Correct?" If the user says no, continue to the steps below.
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
| Push (cache → GitHub) | After Phase 6 (Verification) complete | Push Acceptance `[auto]` checkbox updates |
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

## Manual Verification
- [ ] [manual] <unchecked [manual] item copied verbatim from plan.md>
- [ ] [manual] <another [manual] item>

## Known Issues
- <unresolved FB title and brief description>
- <another known issue>

Closes #<hq:plan>
Refs #<hq:task>
```

- **`## Manual Verification`** — all unchecked `[manual]` items from the Acceptance section, for user verification during PR review.
- **`## Known Issues`** — unresolved issues that `/hq:start` could not auto-fix. **This becomes the source of truth for residual problems.** The corresponding local FB files are moved to `feedbacks/done/` at PR creation time (see FB Lifecycle below).
- If either section is empty, omit it.

During PR review, use `/hq:triage <PR>` to process the `Known Issues` entries — each can be: (1) added to the `hq:plan` for follow-up work, (2) left as-is, or (3) carved out as an `hq:feedback` Issue.

### Invariants (NOT overridable by `.hq/pr.md`)

The following structural elements of the PR body are invariants of the HQ workflow. A project's `.hq/pr.md` (consumed by the `pr` skill) MAY customize prose style, language, title conventions, and optional sections — but it MUST NOT suppress, rename, reformat, or otherwise alter any item below:

- **`## Manual Verification` section presence** — whenever unchecked `[manual]` items exist in the plan's `## Acceptance` section at PR creation time, they MUST appear verbatim under a section literally named `## Manual Verification`.
- **`## Known Issues` section presence** — whenever pending FB files exist at PR creation time, their titles + brief descriptions MUST appear under a section literally named `## Known Issues`.
- **FB atomic move to `feedbacks/done/`** — any FB file whose content is surfaced in `## Known Issues` MUST be moved to `feedbacks/done/` as part of the same PR-creation operation. Surfacing without moving (or moving without surfacing) is forbidden.
- **`Closes #<hq:plan>` / `Refs #<hq:task>` trailer** — every PR body MUST end with these two lines.
- **`hq:pr` label** — every PR created by the `pr` skill (in either invocation mode — Standalone or via `/hq:start`) MUST carry the `hq:pr` label.
- **Milestone / project inheritance** — if the source `hq:task` has a milestone or project(s), the PR MUST inherit them via `--milestone` / `--project` flags.

A newly bootstrapped repository should understand these rules from this section alone — `.hq/pr.md` overrides are applied on top, never in place of, the invariants above.

## Acceptance Execution

Verifies the `hq:plan` is complete — that the implementation satisfies every `[auto]` item in the `## Acceptance` section. This is the primary completion gate of an `hq:plan`.

For each unchecked `[auto]` item:

1. Execute the check autonomously. Kind depends on the item:
   - Shell command, test run, type check, build
   - API / file / directory check
   - Browser automation via `/hq:e2e-web` for navigation, URL assertion, element/text presence, form submit, DOM state
2. **On pass**: toggle the checkbox via `plan-check-item.sh` (cache only).
3. **On fail**: try to fix the underlying problem (counts against the 2-round FB limit in `## Feedback Loop`).
4. **On persistent failure (survives the 2-round cap)**: create **one FB per failed item** describing the failure, **toggle the checkbox to `[x]` anyway**, and move on. The failure is now tracked by the FB — carrying an unchecked `[auto]` forward would deadlock the Phase 8 PR gate.

`[manual]` items are NOT executed here — they remain unchecked and flow to the PR body's `## Manual Verification` section.

Acceptance must be satisfied (all `[auto]` items `[x]` — either truly passing, or `[x]` with a pending FB) before the Quality Review step runs — reviewing quality on a plan that isn't functionally complete is wasted effort.

## Quality Review

Runs after Acceptance is satisfied. Verifies the diff meets the project's quality and security bar, independent of whether the plan was met.

### Step 1: Static Analysis (parallel)

Launch `security-scanner` and `code-reviewer` agents **simultaneously** via the Agent tool. Both run autonomously and return summaries with report/FB file paths.

- **security-scanner** — security alert detection → report file
- **code-reviewer** — quality review → report + FB files

Wait for both agents to complete before proceeding.

### Step 2: Fix FB Issues

Read pending FB files from both agents. Fix issues, run `format` and `build`, then re-run the originating agent to verify. Follow the FB Handling Rules in `## Feedback Loop` (2-round cap).

### Fallback: Interactive Mode

If you need fine-grained control or mid-scan user interaction, use the skills directly instead of agents:

1. `/security-scan` — pauses on credential detection for user confirmation
2. `/code-review` — warns about uncommitted changes

If any step produces unresolved issues, do not skip ahead. Fix or get user confirmation before continuing.

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

### FB Lifecycle (for the root agent after a skill run)

- Read pending FB files and assess each: fix only those that are clearly actionable (bugs, typos, logic errors). Leave design-level or scope-ambiguous FBs as-is for user judgment.
- Run `format` and `build` commands after fixes
- Re-run the originating skill (full review) to verify fixes and catch regressions
- When an FB item is **resolved in-branch**, move its file to `feedbacks/done/`
- When an FB item is **escalated to the PR body's `## Known Issues`** at PR creation time, move its file to `feedbacks/done/` as well — its role has shifted to the PR body (now the source of truth for residual problems)
- Maximum **2 rounds** of the fix → re-verify cycle. After 2 rounds, escalate the remainder to the PR body and move those FB files to `done/`.
- Do not modify or delete FB files — only move resolved/escalated ones to `done/`

**Atomicity** — escalation into `## Known Issues` and the move to `feedbacks/done/` are a single atomic operation. Surfacing an FB in the PR body without moving its file (or moving the file without surfacing the content) is forbidden. This atomicity cannot be skipped or weakened by project-level overrides such as `.hq/pr.md` — see `## PR Body Structure` § Invariants.

**Note**: FB escalation to `hq:feedback` Issues happens during PR review via `/hq:triage` — not from `/hq:start`, `/pr`, or `/hq:archive`. Local FB files are a **branch-internal** concept; the PR body's `## Known Issues` is the hand-off point.
