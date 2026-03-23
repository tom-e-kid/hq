---
description: "Create or update a GitHub Pull Request for the current branch"
---

Create or update a GitHub Pull Request for the current branch. Follow these steps strictly.

## Steps

### 1. Resolve git root

Run `git rev-parse --show-toplevel` and store the result as `GIT_ROOT`. Use this as the base for all subsequent path lookups.

### 2. Verify branch

Run `git branch --show-current`.

- If on `main` or `master`: report error "Cannot create PR from main/master branch" and stop

### 3. Detect base branch

1. Check `$GIT_ROOT/.hq/settings.json` — if `base_branch` is set, use it as `BASE`
2. If not set, run `gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name'`
3. If the command also fails, fall back to `main`
- Store the result as `BASE`

### 4. Check uncommitted changes

Run `git status --porcelain`.

- If output is empty: skip to step 5
- If changes exist:
  - Show the list of changed files
  - Use AskUserQuestion: "You have uncommitted changes. What would you like to do?"
    - "Commit first" — ask for a commit message, stage relevant files, commit
    - "Continue without committing" — warn that uncommitted changes won't be included in the PR

### 5. Push if needed

Run `git status -sb` to check remote tracking status.

- No upstream set → run `git push -u origin HEAD`
- Ahead of remote → run `git push`
- Up to date → skip

### 6. Check existing PR

Run `gh pr view --json number,title,url,state,body`.

- If a PR exists and state is `OPEN` → enter **update flow** (step 9 will show current vs proposed)
- If no PR exists → enter **create flow**
- Store the result for later use

### 7. Gather context

Run these as separate Bash calls (parallelizable):

1. `git log {BASE}..HEAD --oneline` — commit list
2. `git diff {BASE}...HEAD --stat` — file change summary
3. `git diff {BASE}...HEAD` — full diff (for very large diffs, rely on stat + commits instead)

**Task file integration**: Derive the task filename by taking the current branch name and replacing `/` with `-`. Check if `$GIT_ROOT/.hq/tasks/<branch>.md` exists. If found, read it to extract:

- Planned goal and context (the "why")
- Implementation approach and key decisions
- Completion status of planned steps

This enriches the PR description beyond what raw diffs provide.

### 8. Check PR template

Check if `$GIT_ROOT/.hq/templates/pr.md` exists.

- If found: read it and follow its instructions/format for generating the PR body
- If not found: use the default format in step 9

### 9. Generate PR content

**Title**: Concise imperative summary, under 70 chars. Do NOT use Conventional Commits prefix.

**Default body format** (write in the project's primary language; if uncertain, match the user's conversation language):

```markdown
## Summary

[1-3 sentences: what this PR does and why. Leverage task file context if available.
A developer who just joined the project should understand the purpose.]

## Changes

- [Key change 1 — what and why if not obvious]
- [Key change 2]
- [Group related changes. Omit trivial ones unless they're the main point.]

## Notes

[Optional. Include only if relevant:]
[- Breaking changes / migration steps]
[- Dependencies added/removed]
[- Areas needing careful review]
[Omit this section entirely if nothing noteworthy.]
```

**For create flow**: Show the generated title and body. Use AskUserQuestion:
- "Create PR" — proceed
- "Edit title" — ask for a new title, then show again
- "Edit body" — ask for changes, then show again
- "Cancel" — stop

**For update flow**: Show current title/body vs proposed title/body. Use AskUserQuestion:
- "Update" — proceed
- "Edit title" — ask for a new title, then show again
- "Edit body" — ask for changes, then show again
- "Cancel" — stop

### 10. Create or update PR

- **Create**: `gh pr create --title "..." --base {BASE} --body "$(cat <<'EOF' ... EOF)"`
- **Update**: `gh pr edit {NUMBER} --title "..." --body "$(cat <<'EOF' ... EOF)"` (only update changed fields)

### 11. Report result

Output the result: "PR created: {URL}" or "PR updated: {URL}"
