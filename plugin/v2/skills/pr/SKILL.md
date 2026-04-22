---
name: pr
description: Create a pull request for the current branch
---

## Project Overrides

- Overrides: !`cat .hq/pr.md 2>/dev/null || echo "none"`

If `.hq/pr.md` exists, its instructions are applied **only within the allowed override scope** defined below. The Invariants list below is fixed by the HQ workflow and cannot be overridden by `.hq/pr.md` or any project-level configuration — it applies to every PR this skill creates.

### Override scope (allowed)

Projects MAY use `.hq/pr.md` to customize:

- PR body prose style inside `## Summary`, `## Changes`, `## Notes` (tone, level of detail, bullet vs paragraph)
- Natural language used in those prose sections
- Title-line conventions (prefix style, length cap, wording)
- Ordering of **optional** sections (`## Notes` placement relative to other optional sections)
- Additional **project-specific optional sections** that do not conflict with the Invariants

### Invariants (NOT overridable)

The following are invariants of the HQ workflow. `.hq/pr.md` MUST NOT suppress, rename, reformat, or otherwise alter these — they must appear in every PR this skill creates whenever their triggering condition is met:

- **`## Primary Verification (manual)` section** — when a `[manual] [primary]` item exists in the plan's `## Acceptance` section at PR creation time (escape hatch per `hq:workflow § #### [manual] [primary] escape hatch`), the PR body MUST contain a section literally named `## Primary Verification (manual)` populated with: the primary item verbatim, an evidence link (screenshot / video — placeholder acceptable), and a reviewer checklist of ≥3 concrete observations.
- **`hq:manual` label** — when a `[manual] [primary]` item exists in the plan's `## Acceptance` section at PR creation time, the PR MUST carry the `hq:manual` label in addition to `hq:pr`.
- **`## Manual Verification` section** — when unchecked `[manual]` items exist in the plan's `## Acceptance` section at PR creation time (excluding the `[manual] [primary]` item, which lives in `## Primary Verification (manual)` above), they MUST be listed verbatim under a section literally named `## Manual Verification`.
- **`## Known Issues` section** — when pending FB files exist at PR creation time, their titles + brief descriptions MUST be listed under a section literally named `## Known Issues`.
- **FB atomic move to `feedbacks/done/`** — any FB file whose content is surfaced in `## Known Issues` MUST be moved to `feedbacks/done/` as part of the same PR-creation operation. Surfacing without moving (or moving without surfacing) is forbidden.
- **`Closes #<plan>` / `Refs #<task>` trailer** — every PR body MUST end with these two lines, pointing at the driving `hq:plan` and source `hq:task`.
- **`hq:pr` label** — every PR created by this skill MUST carry the `hq:pr` label.
- **Milestone / project inheritance** — if the source `hq:task` has a milestone or project(s), the PR MUST inherit them via `--milestone` / `--project` flags.

If `.hq/pr.md` content appears to contradict any Invariant, the Invariant wins. Flag the conflict to the user after PR creation so the override file can be corrected.

### Invocation mode

This skill has two modes. `.hq/pr.md` overrides apply differently in each:

- **Standalone** (user invokes `/pr` directly): the skill composes the full PR body from git + session context. `.hq/pr.md` overrides apply to the allowed scope above during composition. Invariants are still enforced.
- **From `/hq:start`** (Phase 7 PR Creation delegation): the caller has already assembled the PR body, including `## Manual Verification` and `## Known Issues` sections and the `Closes/Refs` trailer. The prepared body is treated as **immutable** — `.hq/pr.md` may influence **only** the title line; it MUST NOT rewrite, reformat, or strip any section of the prepared body. The skill's role in this mode is execution (push branch, call `gh pr create` with the right flags), not composition.

**`hq:workflow`** — shorthand for `${CLAUDE_PLUGIN_ROOT}/plugin/v2/rules/workflow.md` (plugin-internal source of truth). Read it with the Read tool when this skill starts so the body composer (Standalone mode) and the trailer / label / inheritance Invariants have PR Body Structure, Naming Conventions, Issue Hierarchy, etc. available. From `/hq:start` mode the rule was already loaded by the caller, but a defensive Read is harmless. All `hq:workflow § <name>` citations refer to sections of that file.

## Context

- Branch: !`git rev-parse --abbrev-ref HEAD`
- Base branch: `.hq/settings.json` `base_branch` → `git symbolic-ref refs/remotes/origin/HEAD` → default `main`
- Commits: run `git log --oneline <base-branch>..HEAD` using the Base branch above
- Changed files: run `git diff <base-branch>...HEAD --stat` using the Base branch above
- Uncommitted changes: !`git status --short`
- Focus: !`bash "${CLAUDE_PLUGIN_ROOT}/plugin/v2/scripts/read-context.sh"`
- Existing PR: !`gh pr view --json url,state 2>/dev/null || echo "none"`

## Instructions

### Mode detection (do this first)

Before running any step below, determine invocation mode:

- **From `/hq:start`** — the caller passes a fully prepared PR body, title, and milestone/project flags. In this mode, **skip Steps 4 and 5 entirely** (body composition is already done). Execute Steps 1, 2, 3, 6, 7, 8, 9 using the caller-provided body verbatim. `.hq/pr.md` overrides MAY influence only the title line; the prepared body is immutable. See `## Project Overrides` § Invocation mode.
- **Standalone** — invoked directly (user typed `/pr`, no prepared body available). Execute all steps. Compose the body in Step 5 per the template below, applying `.hq/pr.md` overrides within the allowed scope and enforcing the Invariants.

1. **Check preconditions**:
   - If there are uncommitted changes, warn the user and ask whether to proceed or commit first
   - If there are no commits ahead of the base branch, abort — nothing to PR
   - If a PR already exists, show the URL and ask the user what to do

2. **Push the branch** if it hasn't been pushed yet:
   - `git push -u origin HEAD`

3. **Resolve traceability** — read `.hq/tasks/<branch-dir>/context.md` (branch name: `/` → `-`). Extract `plan`, `source`, and `branch` fields. If not found, check your memory for focus info. If neither exists, ask the user for the `hq:plan` and `hq:task` issue numbers.

4. **(Standalone mode only)** **Compose PR body sections from local state**:

   - **`## Primary Verification (manual)`** — read the plan body from `.hq/tasks/<branch-dir>/gh/plan.md` and detect whether its `## Acceptance` section contains a `[manual] [primary]` item (escape hatch per `hq:workflow § #### [manual] [primary] escape hatch`). If yes, include a `## Primary Verification (manual)` section with: the primary item verbatim, an evidence link placeholder (reviewer fills it during PR review if executor cannot attach), and a reviewer checklist of ≥3 concrete observations decomposing the primary's single observable into verifiable parts. If no `[manual] [primary]` exists, omit this section entirely.

   - **`## Manual Verification`** — extract unchecked `[manual]` items from the plan's `## Acceptance` section, **excluding** the `[manual] [primary]` item (which lives in `## Primary Verification (manual)` above). If any remain, include them verbatim. If none, omit this section.

   - **`## Known Issues`** — check `.hq/tasks/<branch-dir>/feedbacks/` (pending only, not `done/`). For each FB file, include its title and a brief description. If none, omit this section.

   **FB files that are surfaced in `## Known Issues` MUST be moved to `feedbacks/done/`** as part of PR creation — the PR body becomes the source of truth for residual issues. Do NOT create `hq:feedback` Issues from this skill. Escalation to `hq:feedback` happens later via `/hq:triage` during PR review.

5. **(Standalone mode only)** **Draft the PR** based on the context above AND session context (what you know about why these changes were made):
   - **Title**: derive from the `hq:plan` title. Format: `<type>: <description>` (remove the `(plan)` scope from the `hq:plan` title). Keep under 70 characters.
   - **Body** in this format:

   ```
   ## Summary
   <1-3 sentences explaining what and why>

   ## Changes
   <bullet list of key changes>

   ## Notes
   <optional: caveats, design decisions, follow-up items>

   ## Primary Verification (manual)
   <present only when plan has [manual] [primary] — see Step 4>

   ## Manual Verification
   <unchecked [manual] items from the plan's Acceptance section (excluding [manual] [primary]) — omit section if none>

   ## Known Issues
   <escalated FB entries — omit section if none>

   ---
   Closes #<hq:plan issue number>
   Refs #<hq:task issue number>
   ```

   The `Closes #` and `Refs #` lines are mandatory. They link this PR to the `hq:plan` (auto-closed on merge) and the `hq:task` (cross-referenced). Omit optional sections (`## Notes`, `## Primary Verification (manual)`, `## Manual Verification`, `## Known Issues`) when empty.

   **Language**: prose inside `## Summary`, `## Changes`, `## Notes`, and free-form narrative under `## Known Issues` MUST be written in the current conversation language. Markers (`Closes #<plan>`, `Refs #<task>`) and prescribed headings (`## Summary`, `## Changes`, `## Notes`, `## Primary Verification (manual)`, `## Manual Verification`, `## Known Issues`) MUST stay in English. File paths, identifiers, and code fences stay as-is. See `hq:workflow` § Language.

6. **Resolve milestone and project** — read the cached task data from `.hq/tasks/<branch-dir>/gh/task.json`. Extract the milestone title and project title(s) from `projectItems`. If the cache file does not exist, fall back to `gh issue view <source> --json milestone,projectItems`. If a milestone exists, include `--milestone "<milestone>"` when creating the PR. If project(s) exist, include `--project "<project>"` (repeat for each).

7. **Create the PR**:

   ```
   gh pr create --title "<title>" --body "$(cat <<'EOF'
   <body>
   EOF
   )" --label "hq:pr" [--label "hq:manual"] --milestone "<milestone if exists>" --project "<project if exists>"
   ```

   Always apply the `hq:pr` label. Additionally apply `--label "hq:manual"` when the plan has a `[manual] [primary]` item in its `## Acceptance` section (escape hatch — detected during Step 4 composition, or signalled by the caller in `/hq:start` mode). Create any missing labels lazily (see `hq:workflow` § Issue Hierarchy) — `hq:manual` has a lazy-create entry there.

8. **Move escalated FB files to `done/`** — for each FB file referenced in the `## Known Issues` section of the PR body, move the corresponding file from `feedbacks/` to `feedbacks/done/`. This is atomic with PR creation: if the PR is created successfully with those entries in the body, the files MUST move.

9. **Return the PR URL**.

## Rules

- Derive "what changed" from git. Derive "why" from session context (conversation history, `hq:plan` issue if referenced).
- **Always explain WHY** — not just what was changed, but the motivation and reasoning behind the implementation decisions.
- **Write for newcomers** — assume the reader is joining the project for the first time. Provide enough context so the PR is self-explanatory.
- The `Closes #` and `Refs #` lines are required. If no issue numbers can be determined, ask the user before proceeding.
- If the source `hq:task` issue has a milestone, the PR must inherit it. `hq:feedback` issues do NOT inherit milestones (but `hq:feedback` is not created from this skill — only via `/hq:triage`).
- If the source `hq:task` issue has project(s), the PR must inherit them via `--project`.
- Match the language and tone of existing PRs in this repo.
- Do NOT fabricate changes not present in the diff.
- Keep the summary focused — details go in the Changes section.
- **No `hq:feedback` creation** — this skill does NOT create `hq:feedback` Issues. Residual problems flow to the PR body's `## Known Issues` section, to be triaged later via `/hq:triage`.
- **FB escalation is atomic** — if an FB file's content appears in the PR body, the file MUST be moved to `feedbacks/done/`.
- **Invariants are not overridable** — see `## Project Overrides` § Invariants. `.hq/pr.md` cannot override the `## Primary Verification (manual)` section (when the plan has `[manual] [primary]`), the `hq:manual` label (same trigger), the `## Manual Verification` or `## Known Issues` sections, the FB atomic move, the `Closes #<plan>` / `Refs #<task>` trailer, the `hq:pr` label, or milestone / project inheritance. In `/hq:start` invocation mode, the prepared body is immutable and overrides apply only to the title line.
