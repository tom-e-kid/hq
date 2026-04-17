---
name: pr
description: Create a pull request for the current branch
---

## Project Overrides

- Overrides: !`cat .hq/pr.md 2>/dev/null || echo "none"`

If `.hq/pr.md` exists, its instructions take precedence over the defaults below (e.g., PR body format, language, title conventions). Apply overrides on top of this skill's base flow.

## Context

- Branch: !`git rev-parse --abbrev-ref HEAD`
- Base branch: `.hq/settings.json` `base_branch` → `git symbolic-ref refs/remotes/origin/HEAD` → default `main`
- Commits: run `git log --oneline <base-branch>..HEAD` using the Base branch above
- Changed files: run `git diff <base-branch>...HEAD --stat` using the Base branch above
- Uncommitted changes: !`git status --short`
- Focus: !`bash "${CLAUDE_PLUGIN_ROOT}/plugin/v2/scripts/read-context.sh"`
- Existing PR: !`gh pr view --json url,state 2>/dev/null || echo "none"`

## Instructions

1. **Check preconditions**:
   - If there are uncommitted changes, warn the user and ask whether to proceed or commit first
   - If there are no commits ahead of the base branch, abort — nothing to PR
   - If a PR already exists, show the URL and ask the user what to do

2. **Push the branch** if it hasn't been pushed yet:
   - `git push -u origin HEAD`

3. **Resolve traceability** — read `.hq/tasks/<branch-dir>/context.md` (branch name: `/` → `-`). Extract `plan`, `source`, and `branch` fields. If not found, check your memory for focus info. If neither exists, ask the user for the `hq:plan` and `hq:task` issue numbers.

4. **Compose PR body sections from upstream context**:

   - **`## 動作確認をお願いします`** — when invoked as part of `/hq:start`, the caller provides the list of unchecked `[manual]` items from the plan's `## Acceptance` section. Include them verbatim. When invoked standalone, skip this section if no `[manual]` items are available.

   - **`## 制限事項 / Known Issues`** — when invoked as part of `/hq:start`, the caller provides the list of unresolved FB files to escalate into the PR body. Each entry should include the FB title and a brief description. When invoked standalone, check `.hq/tasks/<branch-dir>/feedbacks/` (pending only, not `done/`): if any exist, include them here.

   **FB files that are surfaced in `## 制限事項` MUST be moved to `feedbacks/done/`** as part of PR creation — the PR body becomes the source of truth for residual issues. Do NOT create `hq:feedback` Issues from this skill. Escalation to `hq:feedback` happens later via `/hq:triage` during PR review.

5. **Draft the PR** based on the context above AND session context (what you know about why these changes were made):
   - **Title**: derive from the `hq:plan` title. Format: `<type>: <description>` (remove the `(plan)` scope from the `hq:plan` title). Keep under 70 characters.
   - **Body** in this format:

   ```
   ## Summary
   <1-3 sentences explaining what and why>

   ## Changes
   <bullet list of key changes>

   ## Notes
   <optional: caveats, design decisions, follow-up items>

   ## 動作確認をお願いします
   <unchecked [manual] items from the plan's Acceptance section — omit section if none>

   ## 制限事項 / Known Issues
   <escalated FB entries — omit section if none>

   ---
   Closes #<hq:plan issue number>
   Refs #<hq:task issue number>
   ```

   The `Closes #` and `Refs #` lines are mandatory. They link this PR to the `hq:plan` (auto-closed on merge) and the `hq:task` (cross-referenced). Omit optional sections (`## Notes`, `## 動作確認をお願いします`, `## 制限事項 / Known Issues`) when empty.

6. **Resolve milestone and project** — read the cached task data from `.hq/tasks/<branch-dir>/gh/task.json`. Extract the milestone title and project title(s) from `projectItems`. If the cache file does not exist, fall back to `gh issue view <source> --json milestone,projectItems`. If a milestone exists, include `--milestone "<milestone>"` when creating the PR. If project(s) exist, include `--project "<project>"` (repeat for each).

7. **Create the PR**:

   ```
   gh pr create --title "<title>" --body "$(cat <<'EOF'
   <body>
   EOF
   )" --milestone "<milestone if exists>" --project "<project if exists>"
   ```

8. **Move escalated FB files to `done/`** — for each FB file referenced in the `## 制限事項 / Known Issues` section of the PR body, move the corresponding file from `feedbacks/` to `feedbacks/done/`. This is atomic with PR creation: if the PR is created successfully with those entries in the body, the files MUST move.

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
- **No `hq:feedback` creation** — this skill does NOT create `hq:feedback` Issues. Residual problems flow to the PR body's `## 制限事項 / Known Issues` section, to be triaged later via `/hq:triage`.
- **FB escalation is atomic** — if an FB file's content appears in the PR body, the file MUST be moved to `feedbacks/done/`.
