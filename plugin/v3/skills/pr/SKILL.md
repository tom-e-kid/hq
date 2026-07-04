---
name: pr
description: Create a pull request for the current branch
---

## Project Overrides

- Overrides: !`cat .hq/pr.md 2>/dev/null || echo "none"`

If `.hq/pr.md` exists, its instructions govern the **narrative layer** of the PR body (see § Override scope below). The **workflow-layer Invariants** are fixed by the HQ workflow and cannot be overridden by `.hq/pr.md` or any project-level configuration — they apply to every PR this skill creates whenever their triggering condition holds.

### Design premise — what a PR body is for

The PR body serves the **human reviewer**, who should spend attention on the essence: the motivation, the chosen approach (including what changed against the original intent during implementation), and the changes. It is NOT a dump of the agent's task list — the plan file stays a local work artifact and is never embedded. When `.hq/pr.md` supplies format instructions, follow them; the refocus premise governs the default composition, not the project's own format authority.

### Override scope (allowed)

The PR body has two layers — a **narrative layer** authored from `.hq/pr.md` (or defaults) and a **workflow sections layer** injected at creation time. Projects MAY use `.hq/pr.md` to redefine the narrative layer in full:

- Narrative section heading names (e.g., `## 概要` / `## 変更` / `## メモ` instead of the defaults)
- Narrative section structure (number of sections, ordering, additions, removals)
- Natural language of the narrative (Japanese / English / any conversation language)
- Prose style inside narrative sections; title-line conventions (prefix style, length cap, wording)

If `.hq/pr.md` gives only prose-style hints (no heading redefinitions), keep the default narrative headings and apply the hints inside them.

### Invariants (NOT overridable)

- **`hq:pr` label** — every PR created by this skill carries it.
- **`hq:manual` label + `## Manual Verification` section** — when the plan has `## Manual Verification` items at PR creation time, they MUST appear verbatim under a section literally named `## Manual Verification`, and the PR MUST carry the `hq:manual` label.
- **`## Known Issues` section** — when the caller passes triaged residual entries (accepted limitations / pending escalations), they MUST appear under a section literally named `## Known Issues`, unmodified.
- **`Refs #<task>` trailer** — required when the plan has a parent `hq:task` (`context.md` `source:`); omitted entirely when no parent exists.
- **Milestone / project inheritance** — if the source `hq:task` has a milestone or project(s), the PR MUST inherit them via `--milestone` / `--project` flags.
- **No plan embed** — the plan file's checklist is never copied into the PR body; its motivation/approach content reaches the reviewer through the narrative.

If `.hq/pr.md` content appears to contradict an Invariant, the Invariant wins. Flag the conflict to the user after PR creation so the override file can be corrected.

### Invocation mode

- **From `/hq:loop`** (Stage 5 Ship — the normal path): the caller (root agent) composes the narrative itself (J6 — motivation / approach incl. build-time deviations / changes, honoring `.hq/pr.md`) and passes a **workflow sections pack**: the `## Manual Verification` block (when the plan has reviewer-owned checks), the `## Known Issues` block (post-triage residual), the `Refs` trailer (when a parent task exists), and the label / milestone / project flags. This skill validates the Invariants, assembles narrative + pack, and runs `gh pr create`. Do NOT edit or recompose the pack.
- **Standalone** (user invokes `/pr` directly on an ad-hoc branch): compose the entire body from git + session context — narrative per `.hq/pr.md` or defaults; workflow sections from local state where it exists (`.hq/tasks/<branch-dir>/plan.md` `## Manual Verification`; pending `feedbacks/` entries listed under `## Known Issues` with `[<Severity>] [<origin>]` tags); `Refs #<task>` when `context.md` has `source:`.

**`hq:workflow`** — shorthand for `${CLAUDE_PLUGIN_ROOT}/plugin/v3/rules/workflow.md`. Read it when this skill starts (PR Body Structure, Naming Conventions, Language). All `hq:workflow § <name>` citations refer to it.

## Context

- Branch: !`git rev-parse --abbrev-ref HEAD`
- Base branch: resolve per `hq:workflow § Branch Rules` — `.hq/tasks/<branch-dir>/context.md` `base_branch:` → `.hq/settings.json` `base_branch` → `git symbolic-ref --short refs/remotes/origin/HEAD` → `main`. The `context.md` step is the **authoritative per-branch record** captured at branch creation — the load-bearing input for `gh pr create --base <base>`; without it, stacked PRs and worktree-parallel runs silently target the wrong base.
- Commits: run `git log --oneline <base-branch>..HEAD` using the Base branch above
- Changed files: run `git diff <base-branch>...HEAD --stat` using the Base branch above
- Uncommitted changes: !`git status --short`
- Focus: !`bash "${CLAUDE_PLUGIN_ROOT}/plugin/v3/scripts/read-context.sh"`
- Existing PR: !`gh pr view --json url,state 2>/dev/null || echo "none"`

## Instructions

1. **Check preconditions** — uncommitted changes → warn and ask (From-loop mode: the caller guarantees a clean tree; a dirty tree is a caller bug — stop and report). No commits ahead of base → abort. PR already exists → show the URL and stop.

2. **Push the branch** if not yet pushed: `git push -u origin HEAD`.

3. **Resolve traceability** — read `.hq/tasks/<branch-dir>/context.md`: `source` (optional parent `hq:task`), `branch`. Missing file on an ad-hoc branch → no traceability; skip `Refs` and inheritance.

4. **Compose the body**:

   - **Title**: `<type>: <description>` — from the plan title (the plan file's `# ` heading, `(plan)` scope removed) when a plan exists; otherwise derive from the commits. ≤ 70 chars. `.hq/pr.md` MAY adjust conventions.
   - **Narrative layer** (default headings; `.hq/pr.md` may redefine per § Override scope):

     ```
     ## Summary
     <what this PR achieves and why — the pain and the motivation, readable by someone new to the area>

     ## Approach
     <the chosen design and why; rejected alternatives worth naming; deviations from the original plan discovered during implementation, with reasons>

     ## Changes
     <bullet list of key changes>
     ```

     Conversation language by default. Write for newcomers; explain WHY, not just what.
   - **Workflow sections** (English-fixed headings; From-loop: the caller's pack verbatim):

     ```
     ## Manual Verification   <!-- only when the plan has [manual] items -->
     - [ ] [manual] <item, verbatim from the plan>

     ## Known Issues          <!-- only when triaged residual exists -->
     - [<Severity>] [<origin>] <title> — accepted: <reason>
     - [<Severity>] [<origin>] <title> — escalation pending user confirmation

     ---
     Refs #<task>             <!-- only when a parent hq:task exists -->
     ```

     `## Known Issues` entries are **post-triage residual** — accepted limitations and pending escalations. There is no "process me later" backlog; escalation lines are finalized by the loop's Stage 7 (`escalated: #N` after the user confirms, or `accepted: escalation declined by user`).

5. **Resolve milestone and project** *(only when `source` is set)* — from `.hq/tasks/<branch-dir>/gh/task.json`, falling back to `gh issue view <source> --json milestone,projectItems`. Include `--milestone` / `--project` flags accordingly.

6. **Create the PR** — always pass `--base "<base>"` explicitly (omitting it makes `gh` default to origin's HEAD and silently mis-target stacked PRs):

   ```
   gh pr create --base "<base>" --title "<title>" --body "$(cat <<'EOF'
   <body>
   EOF
   )" --label "hq:pr" [--label "hq:manual"] [--milestone "<m>"] [--project "<p>" ...]
   ```

   Create missing labels lazily (`hq:workflow § Issue Hierarchy`).

7. **Return the PR URL.**

## Rules

- Derive "what changed" from git; derive "why" from the plan's `## Why` / `## Approach` and the run's decision context — never fabricate changes not in the diff.
- The narrative is the reviewer's surface: motivation and approach first, mechanics second. The plan checklist is not reviewer material.
- `Refs #` only with a resolvable parent task; ask before proceeding if `source` is set but unresolvable.
- `hq:feedback` Issues are never created here.
- Always pass `--base` explicitly.
- Workflow-layer Invariants are not overridable; the narrative layer is fully `.hq/pr.md`-overridable.
