---
name: pr
description: Create a pull request for the current branch
---

## Project Overrides

- Overrides: !`cat .hq/pr.md 2>/dev/null || echo "none"`

If `.hq/pr.md` exists, its instructions govern the **narrative layer** of the PR body (see § Override scope below). The **workflow-layer Invariants** are fixed by the HQ workflow and cannot be overridden by `.hq/pr.md` or any project-level configuration — they apply to every PR this skill creates whenever their triggering condition holds.

### Override scope (allowed)

The PR body has two layers — a **narrative layer** authored from `.hq/pr.md` (or defaults) and a **workflow sections layer** auto-injected by `/hq:start` Phase 8. See `hq:workflow § PR Body Structure` for the 2-layer model.

Projects MAY use `.hq/pr.md` to redefine the **narrative layer** in full:

- Narrative section heading names (e.g., `## 概要` / `## 変更` / `## メモ` instead of the default `## Summary` / `## Changes` / `## Notes`)
- Narrative section structure (number of sections, ordering, addition of project-specific sections, removal of defaults)
- Natural language of the narrative (Japanese / English / any conversation language)
- Prose style inside narrative sections (tone, level of detail, bullet vs paragraph)
- Title-line conventions (prefix style, length cap, wording)

If `.hq/pr.md` gives only prose-style hints (no heading redefinitions), the pr skill keeps the default narrative headings and applies the hints inside them. Either authoring style is valid — `.hq/pr.md` is guidance for narrative composition, not a strict template specification.

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

This skill has two modes. In **both modes** the pr skill is the **narrative composer** — it renders the narrative layer from `.hq/pr.md` (or defaults) and the Invariants are enforced. The difference is who supplies the workflow sections:

- **Standalone** (user invokes `/pr` directly): the skill composes the **entire** PR body from git + session context — narrative (from `.hq/pr.md` or defaults) plus workflow sections (from the plan cache's `## Acceptance` / `feedbacks/`) plus trailer. Apply `.hq/pr.md` to the narrative layer per § Override scope.
- **From `/hq:start`** (Phase 8 PR Creation delegation): the caller passes a **workflow sections pack** — pre-rendered `## Primary Verification (manual)` block (when escape hatch applies), `## Manual Verification` block, `## Known Issues` block, `Closes` / `Refs` trailer lines, and label flags (`hq:pr`, optionally `hq:manual`). The pr skill renders the **narrative** from `.hq/pr.md` (or defaults), then **appends the workflow sections pack verbatim**, then runs `gh pr create` with the resolved labels and flags. `.hq/pr.md` is applied to the narrative layer per § Override scope; the workflow sections pack is invariant by construction (the caller built it from the plan and FB files).

**`hq:workflow`** — shorthand for `${CLAUDE_PLUGIN_ROOT}/plugin/v2/rules/workflow.md` (plugin-internal source of truth). Read it with the Read tool when this skill starts so the body composer (Standalone mode) and the trailer / label / inheritance Invariants have PR Body Structure, Naming Conventions, Issue Hierarchy, etc. available. From `/hq:start` mode the rule was already loaded by the caller, but a defensive Read is harmless. All `hq:workflow § <name>` citations refer to sections of that file.

## Context

- Branch: !`git rev-parse --abbrev-ref HEAD`
- Base branch: resolve per `hq:workflow § Branch Rules` — `.hq/tasks/<branch-dir>/context.md` `base_branch:` → `.hq/settings.json` `base_branch` → `git symbolic-ref --short refs/remotes/origin/HEAD` → `main`. `<branch-dir>` is the current branch with `/` → `-`. The `context.md` step is the **authoritative per-branch record** captured at branch creation time and is the load-bearing input for `gh pr create --base <base>` in Step 7 — without it, stacked PRs and worktree-parallel runs silently target the wrong base.
- Commits: run `git log --oneline <base-branch>..HEAD` using the Base branch above
- Changed files: run `git diff <base-branch>...HEAD --stat` using the Base branch above
- Uncommitted changes: !`git status --short`
- Focus: !`bash "${CLAUDE_PLUGIN_ROOT}/plugin/v2/scripts/read-context.sh"`
- Existing PR: !`gh pr view --json url,state 2>/dev/null || echo "none"`

## Instructions

### Mode detection (do this first)

Before running any step below, determine invocation mode:

- **From `/hq:start`** — the caller passes a **workflow sections pack** (pre-rendered `## Primary Verification (manual)` when applicable, `## Manual Verification`, `## Known Issues`, `Closes` / `Refs` trailer, and label / milestone / project flags). The pr skill **skips Step 4** (workflow-section composition — already prepared by the caller) and executes Steps 1, 2, 3, 5, 6, 7, 8, 9. In Step 5 it renders the **narrative** from `.hq/pr.md` (or defaults) and **appends the caller's workflow sections pack verbatim**. See `## Project Overrides` § Invocation mode.
- **Standalone** — invoked directly (user typed `/pr`, no caller pack available). Execute all steps. Step 4 builds the workflow sections from the local plan cache + `feedbacks/`; Step 5 renders the narrative and assembles narrative + workflow sections + trailer.

1. **Check preconditions**:
   - If there are uncommitted changes, warn the user and ask whether to proceed or commit first
   - If there are no commits ahead of the base branch, abort — nothing to PR
   - If a PR already exists, show the URL and ask the user what to do

2. **Push the branch** if it hasn't been pushed yet:
   - `git push -u origin HEAD`

3. **Resolve traceability** — read `.hq/tasks/<branch-dir>/context.md` (branch name: `/` → `-`). Extract `plan`, `source`, and `branch` fields. If not found, check your memory for focus info. If neither exists, ask the user for the `hq:plan` and `hq:task` issue numbers.

4. **(Standalone mode only — From `/hq:start` receives these as the workflow sections pack)** **Compose workflow sections from local state**:

   - **`## Primary Verification (manual)`** — read the plan body from `.hq/tasks/<branch-dir>/gh/plan.md` and detect whether its `## Acceptance` section contains a `[manual] [primary]` item (escape hatch per `hq:workflow § #### [manual] [primary] escape hatch`). If yes, include a `## Primary Verification (manual)` section with: the primary item verbatim, an evidence link placeholder (reviewer fills it during PR review if executor cannot attach), and a reviewer checklist of ≥3 concrete observations decomposing the primary's single observable into verifiable parts. If no `[manual] [primary]` exists, omit this section entirely.

   - **`## Manual Verification`** — extract unchecked `[manual]` items from the plan's `## Acceptance` section, **excluding** the `[manual] [primary]` item (which lives in `## Primary Verification (manual)` above). If any remain, include them verbatim. If none, omit this section.

   - **`## Known Issues`** — check `.hq/tasks/<branch-dir>/feedbacks/` (pending only, not `done/`). For each FB file, read the frontmatter `severity:` field (one of `Critical` / `High` / `Medium` / `Low`) and emit an entry of the form `- [<Severity>]: <title> — <brief description>`. Sort the emitted entries in severity **descending** order (`Critical` → `High` → `Medium` → `Low`); within the same severity preserve insertion order (no secondary sort). The severity prefix and sort order are invariant — see `hq:workflow § ## PR Body Structure § Invariants`. If no pending FBs, omit this section.

   **FB files that are surfaced in `## Known Issues` MUST be moved to `feedbacks/done/`** as part of PR creation — the PR body becomes the source of truth for residual issues. Do NOT create `hq:feedback` Issues from this skill. Escalation to `hq:feedback` happens later via `/hq:triage` during PR review.

5. **Render narrative + assemble final body** (both invocation modes):

   - **Title**: derive from the `hq:plan` title. Format: `<type>: <description>` (remove the `(plan)` scope from the `hq:plan` title). Keep under 70 characters. `.hq/pr.md` MAY adjust title conventions per § Override scope.
   - **Narrative layer**: read `.hq/pr.md` (already loaded into context above) and render the narrative section accordingly:
     - If `.hq/pr.md` defines explicit narrative section headings (e.g., `## 概要` / `## 変更`), use those headings, language, and structure verbatim.
     - If `.hq/pr.md` gives only prose-style hints (no heading redefinitions), use the **default narrative** with the hints applied inside it:

       ```
       ## Summary
       <1-3 sentences explaining what and why>

       ## Changes
       <bullet list of key changes>

       ## Notes
       <optional: caveats, design decisions, follow-up items — omit section if empty>
       ```

     - If `.hq/pr.md` is absent (`none`), use the default narrative as shown.
     - The narrative is authored in the **conversation language** by default — `.hq/pr.md` may override the language.
   - **Workflow sections**:
     - **From `/hq:start`**: take the caller-provided **workflow sections pack** verbatim — `## Primary Verification (manual)` (when present), `## Manual Verification` (when present), `## Known Issues` (when present), and the `Closes` / `Refs` trailer. Do NOT edit or recompose these.
     - **Standalone**: use the sections built in Step 4 (`## Primary Verification (manual)`, `## Manual Verification`, `## Known Issues`) and append a trailer line of `Closes #<hq:plan>` plus `Refs #<hq:task>` when the plan has a parent (omit `Refs` when no parent exists).
   - **Final assembly**:

     ```
     <narrative layer — heading set and language from .hq/pr.md or defaults>

     ## Primary Verification (manual)  <!-- omitted unless plan has [manual] [primary] -->
     ...

     ## Manual Verification  <!-- omitted when no unchecked [manual] items -->
     ...

     ## Known Issues  <!-- omitted when no pending FBs -->
     ...

     ---
     Closes #<hq:plan issue number>
     Refs #<hq:task issue number>  <!-- omitted when plan has no parent hq:task -->
     ```

     Omit empty workflow sections. The `Closes #` line is always mandatory; the `Refs #` line is mandatory only when the plan has a parent `hq:task`.

   **Language**: the **narrative** follows `.hq/pr.md` (or the conversation language by default). The **workflow section headings** (`## Primary Verification (manual)` / `## Manual Verification` / `## Known Issues`) and **markers** (`Closes #<plan>`, `Refs #<task>`) MUST stay in English (each has an injection or parse contract — see `hq:workflow` § Language). File paths, identifiers, and code fences stay as-is.

6. **Resolve milestone and project** — read the cached task data from `.hq/tasks/<branch-dir>/gh/task.json`. Extract the milestone title and project title(s) from `projectItems`. If the cache file does not exist, fall back to `gh issue view <source> --json milestone,projectItems`. If a milestone exists, include `--milestone "<milestone>"` when creating the PR. If project(s) exist, include `--project "<project>"` (repeat for each).

7. **Create the PR** — pass the resolved base branch explicitly via `--base <base>`. Resolution chain (per `hq:workflow § Branch Rules`): `.hq/tasks/<branch-dir>/context.md` `base_branch:` → `.hq/settings.json` `base_branch` → `git symbolic-ref --short refs/remotes/origin/HEAD` → `main`. Omitting `--base` makes `gh pr create` default to origin's HEAD, which silently targets `main` even for stacked PRs / non-main bases — always pass the flag explicitly.

   ```
   gh pr create --base "<base>" --title "<title>" --body "$(cat <<'EOF'
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
- **Always pass `--base <base>` to `gh pr create`** — base resolution follows `hq:workflow § Branch Rules` (`.hq/tasks/<branch-dir>/context.md` `base_branch:` first). Omitting the flag makes `gh pr create` fall back to origin's default HEAD, which silently mis-targets stacked PRs / non-main bases. This is the failure mode the per-branch `context.md` `base_branch:` field is designed to eliminate; the explicit `--base` flag closes the loop.
- **Workflow-layer Invariants are not overridable** — see `## Project Overrides` § Invariants. `.hq/pr.md` cannot override the `## Primary Verification (manual)` section (when the plan has `[manual] [primary]`), the `hq:manual` label (same trigger), the `## Manual Verification` or `## Known Issues` sections, the FB atomic move, the `Closes #<plan>` / `Refs #<task>` trailer, the `hq:pr` label, or milestone / project inheritance. The **narrative layer**, by contrast, is fully overridable by `.hq/pr.md` — heading names, language, structure, and prose are all in scope (see § Override scope). In `/hq:start` invocation mode the caller passes a workflow sections pack which is appended verbatim by Step 5; only the narrative layer is composed by the pr skill in that mode.
