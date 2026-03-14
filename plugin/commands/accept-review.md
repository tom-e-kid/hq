---
description: "Evaluate code review results, commit accepted fixes, and extract follow-up issues"
---

Evaluate the latest code review on the current branch. Judge review quality, commit good fixes, extract follow-up issues, and report results. Follow these steps strictly.

## Steps

### 1. Resolve git root

Run `git rev-parse --show-toplevel` and store the result as `GIT_ROOT`. Use this as the base for all subsequent path lookups.

### 2. Verify branch

Run `git branch --show-current`.

- If on `main` or `master`: report error "Cannot accept review from main/master branch" and stop

### 3. Locate taskfile

Derive the task filename by taking the current branch name and replacing `/` with `-`. Check if `$GIT_ROOT/.hq/tasks/<branch>.md` exists.

- If missing: report error "No taskfile found for this branch" and stop

### 4. Read latest Code Review section

Read the taskfile and find the last `## Code Review <YYYY-MM-DD HH:MM>` section. Parse:

- Findings grouped by severity (Critical / High / Medium / Low)
- Each finding's target file, line, description, impact, and action taken
- Summary (modified files, remaining issues, verification results)

If no `## Code Review` section exists: report error "No code review found in taskfile" and stop.

### 5. Check uncommitted changes

Run `git status --porcelain` and `git diff` as separate Bash calls (parallelizable).

- If `git status --porcelain` output is empty: report "No uncommitted changes from reviewer — skipping commit steps" and skip to step 9
- If staged changes already exist (lines starting with `M `, `A `, `D ` etc. in the index column): warn the user and use AskUserQuestion:
  - "Continue" — proceed with both staged and unstaged changes
  - "Abort" — stop

### 6. Evaluate review & changes

Launch a subagent (Agent tool, subagent_type: general-purpose) with:

- The full code review section text from step 4
- The `git diff` output from step 5

The subagent must evaluate:

- **Review quality**: Are findings specific (file, line, description, impact)? Is severity appropriate?
- **Code changes**: Are they safe, correct, minimal, and following project conventions?
- Return a structured result:
  - Per-file verdict: `accept` or `reject` with a one-line reason
  - Overall assessment: one-line summary of the review quality

### 7. User approval gate

Present a summary table of the subagent's evaluation:

```
| File | Verdict | Reason |
|------|---------|--------|
| src/foo.ts | accept | Correctly fixes null check |
| src/bar.ts | reject | Change alters public API behavior |
```

Also show the proposed commit message (default: `refactor: apply code review fixes`).

Use AskUserQuestion with options:

- "Accept all" — commit all changed files
- "Accept approved only" — commit only `accept` files, run `git checkout -- <rejected files>` to discard rejected changes
- "Reject all" — run `git checkout -- .` to discard all changes, skip to step 9
- "Abort" — stop immediately

### 8. Commit accepted changes

1. **Pre-commit format** (same rules as the `dev-core` skill):
   - Get changed files: `git diff --name-only --diff-filter=AM`
   - Detect project type and run the appropriate formatter on changed files only:

     | Indicator | Platform | Command |
     |---|---|---|
     | `go.mod` | Go | `gofmt -w <changed .go files>` |
     | `package.json` | Web | Run `format` script if defined (detect pkg manager from lock file) |
     | `.xcworkspace` / `.xcodeproj` | iOS | `swift-format -i <changed .swift files>` (skip if not installed) |

   - If no formatter detected, skip silently
2. Stage accepted files: `git add <accepted files>`
3. Commit with the user-provided message from step 7 (default: `refactor: apply code review fixes`). Follow the commit format defined in the `dev-core` skill.

### 9. Extract follow-up issues

Scan the code review section for:

- Items with action "proposed as task"
- Unfixed Critical or High severity items

For each item found:

1. `mkdir -p $GIT_ROOT/.hq/backlog/`
2. List existing `CR-*.md` files in that directory to determine the next available number (start at 001)
3. Write `$GIT_ROOT/.hq/backlog/CR-<NNN>.md` using the backlog template defined in the `dev-core` skill's **Backlog** section. Set `source` to the current branch name.

If no items qualify: skip this step and report "No follow-up issues to extract".

### 10. Quick-fix triage

Review the issues extracted in step 9. For each issue, judge whether it can be resolved on the spot with 1–few user confirmations. Criteria for "quick fix":

- The fix approach is clear from the review description (no open design questions)
- Scope is small (single file or a few lines)
- No architectural decisions or spec clarification required

For each quick-fix candidate, present:

- Issue title and severity
- Target file(s) and line(s)
- Proposed fix approach (from the review or your own assessment)

Then use AskUserQuestion:

- "Fix now" — implement the fix, run pre-commit format (same as step 8), stage, and commit with message `fix: <concise description>`. Update the issue file: set `status: resolved` in frontmatter
- "Skip" — leave as open issue, move to the next candidate

After processing all candidates (or if none qualify), continue to step 11.

### 11. Update taskfile

Append a new section to the taskfile:

```markdown
## Review Accepted <YYYY-MM-DD HH:MM>

### Committed
- <list of committed files, or "None">

### Rejected
- <list of rejected files with reasons, or "None">

### Issues Extracted
- <list of created issue files with severity, or "None">

### Quick-fixed
- <list of issues resolved on the spot with commit hashes, or "None">
```

### 12. Report results

Output a final summary:

- **Committed**: file count + commit hash (or "None")
- **Rejected**: file count + reasons (or "None")
- **Issues created**: list with severity and title (or "None")
- **Quick-fixed**: list with title and commit hash (or "None")
- **Taskfile updated**: confirmation
