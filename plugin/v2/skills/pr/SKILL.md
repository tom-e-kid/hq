---
name: pr
description: Create a pull request for the current branch
---

## Project Overrides

- Overrides: !`cat .hq/pr.md 2>/dev/null || echo "none"`

If `.hq/pr.md` exists, its instructions take precedence over the defaults below (e.g., PR body format, language, title conventions). Apply overrides on top of this skill's base flow.

## Context

- Branch: !`git rev-parse --abbrev-ref HEAD`
- Base branch: resolve by reading `.hq/settings.json` field `base_branch`, or `git symbolic-ref refs/remotes/origin/HEAD`, or default `main`
- Commits: run `git log --oneline <base-branch>..HEAD` using the Base branch above
- Changed files: run `git diff <base-branch>...HEAD --stat` using the Base branch above
- Uncommitted changes: !`git status --short`
- Focus: !`"${CLAUDE_PLUGIN_ROOT}/plugin/v2/scripts/read-memory.sh" focus.md`
- Existing PR: !`gh pr view --json url,state 2>/dev/null || echo "none"`

## Instructions

1. **Check preconditions**:
   - If there are uncommitted changes, warn the user and ask whether to proceed or commit first
   - If there are no commits ahead of the base branch, abort — nothing to PR
   - If a PR already exists, show the URL and ask the user what to do

2. **Push the branch** if it hasn't been pushed yet:
   - `git push -u origin HEAD`

3. **Resolve source** — read `focus.md` from your Claude Code memory directory:
   - If focus exists and has a `source:` field, use it
   - If no focus, check `.hq/tasks/<branch>/context.md` (branch name: replace `/` with `-`)
   - If neither exists, ask the user

4. **Draft the PR** based on the context above AND session context (what you know about why these changes were made):
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
   source: <source>#<unique-identifier>
   ```

   The `source:` line at the end is mandatory. It links this PR to the originating requirement.

5. **Show the draft** to the user and ask for confirmation before creating.

6. **Create the PR**:

   ```
   gh pr create --title "<title>" --body "$(cat <<'EOF'
   <body>
   EOF
   )"
   ```

7. **Return the PR URL**.

## Rules

- Derive "what changed" from git. Derive "why" from session context (conversation history, taskfile if referenced).
- **Always explain WHY** — not just what was changed, but the motivation and reasoning behind the implementation decisions.
- **Write for newcomers** — assume the reader is joining the project for the first time. Provide enough context so the PR is self-explanatory.
- The `source:` line is required. If no source can be determined, ask the user before proceeding.
- Match the language and tone of existing PRs in this repo.
- Do NOT fabricate changes not present in the diff.
- Keep the summary focused — details go in the Changes section.
