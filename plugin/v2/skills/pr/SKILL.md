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
- Focus: !`cat "$HOME/.claude/projects/$(pwd | sed 's|[/.]|-|g')/memory/focus.md" 2>/dev/null || echo "none"`
- Existing PR: !`gh pr view --json url,state 2>/dev/null || echo "none"`

## Instructions

1. **Check preconditions**:
   - If there are uncommitted changes, warn the user and ask whether to proceed or commit first
   - If there are no commits ahead of the base branch, abort — nothing to PR
   - If a PR already exists, show the URL and ask the user what to do

2. **Push the branch** if it hasn't been pushed yet:
   - `git push -u origin HEAD`

3. **Resolve traceability** — read `focus.md` from Claude Code memory directory. Extract `plan` and `source` (GitHub issue numbers). Fallback: `.hq/tasks/<branch>/context.md` (branch path: `/` → `-`). If neither exists, ask the user for the `hq:plan` and `hq:task` issue numbers.

4. **Escalate unresolved FB** — check `.hq/tasks/<branch>/feedbacks/` for pending FB files (not in `done/`):
   - If unresolved FBs exist, show the list to the user
   - Ask whether to create `hq:feedback` issues on GitHub for each
   - If yes — for each FB: `gh issue create --title "<FB title>" --body "<FB content>\n\nRefs #<plan>" --label "hq:feedback"`
   - Move escalated FB files to `feedbacks/done/`

5. **Draft the PR** based on the context above AND session context (what you know about why these changes were made):
   - **Title**: concise, under 70 characters
   - **Body** in this format:

   ```
   ## Summary
   <1-3 sentences explaining what and why>

   ## Changes
   <bullet list of key changes>

   ## Notes
   <optional: caveats, known issues, follow-up items>

   ---
   Closes #<hq:plan issue number>
   Refs #<hq:task issue number>
   ```

   The `Closes #` and `Refs #` lines are mandatory. They link this PR to the `hq:plan` (auto-closed on merge) and the `hq:task` (cross-referenced).

6. **Show the draft** to the user and ask for confirmation before creating.

7. **Resolve milestone** — check the source `hq:task` issue for a milestone: `gh issue view <source> --json milestone --jq '.milestone.title'`. If one exists, include `--milestone "<milestone>"` when creating the PR.

8. **Create the PR**:

   ```
   gh pr create --title "<title>" --body "$(cat <<'EOF'
   <body>
   EOF
   )" --milestone "<milestone if exists>"
   ```

9. **Return the PR URL**.

## Rules

- Derive "what changed" from git. Derive "why" from session context (conversation history, `hq:plan` issue if referenced).
- **Always explain WHY** — not just what was changed, but the motivation and reasoning behind the implementation decisions.
- **Write for newcomers** — assume the reader is joining the project for the first time. Provide enough context so the PR is self-explanatory.
- The `Closes #` and `Refs #` lines are required. If no issue numbers can be determined, ask the user before proceeding.
- If the source `hq:task` issue has a milestone, the PR must inherit it. `hq:feedback` issues do NOT inherit milestones.
- Match the language and tone of existing PRs in this repo.
- Do NOT fabricate changes not present in the diff.
- Keep the summary focused — details go in the Changes section.
