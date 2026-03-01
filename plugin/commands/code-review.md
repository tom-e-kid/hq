---
description: "Review code changes on the current branch against the base branch"
---

Review code changes on the current branch. Follow these steps strictly.

## Steps

### 1. Resolve git root

Run `git rev-parse --show-toplevel` and store the result as `GIT_ROOT`. Use this as the base for all subsequent path lookups.

### 2. Verify branch

Run `git branch --show-current`.

- If on `main` or `master`: report error "Cannot review from main/master branch" and stop

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
    - "Continue without committing" — warn that uncommitted changes won't be included in the review diff

### 5. Gather diff

Run these as separate Bash calls (parallelizable):

1. `git log {BASE}..HEAD --oneline` — commit list
2. `git diff {BASE}...HEAD --stat` — file change summary
3. `git diff {BASE}...HEAD` — full diff

Exclude the following from review:

- `node_modules/`
- Build artifacts (e.g., `.next/`, `dist/`, `coverage/`)
- Auto-updated lock files (`bun.lock`, `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`)

### 6. Sensitive data check

Scan the diff output for the following patterns:

- API keys / secrets (`AKIA`, `sk-`, `ghp_`, `Bearer` etc.)
- `.env` file changes
- Hardcoded passwords / tokens

If detected: warn the user with the file name and line number. Use AskUserQuestion to confirm whether to continue the review.

### 7. Code simplification check

Launch the `code-simplifier` subagent targeting the files changed in the diff. Let it check for verbosity, unnecessary code, and simplification opportunities. If it produces fixes, apply them but do NOT commit.

### 8. Build verification

Detect and run the project's build command (e.g., `bun run build`, `npm run build`). If errors or warnings are found that can be fixed without spec clarification or user judgment, fix them directly but do NOT commit.

Also run the linter if available (e.g., `bun run lint`).

### 9. Review context

**Task file integration**: Derive the task filename by taking the current branch name and replacing `/` with `-`. Check if `$GIT_ROOT/.hq/tasks/<branch>.md` exists. If found, read it to understand:

- Planned goal and context
- Implementation approach and key decisions
- Completion status of planned steps

**Requirements**: If `$GIT_ROOT/docs/requirements.md` exists, use it as a reference for project requirements.

### 10. Review and report

Review the diff against these criteria:

- **Readability & conciseness**: Identify verbose or unnecessary code and simplify where possible
- **Correctness**: Check for spec deviations, potential bugs, and missed edge cases
- **Performance**: Look for redundant computations, unnecessary re-renders, heavy operations, and inefficient data processing. Fix where possible
- **Security**: Check for insufficient input validation, XSS/injection risks, credential leaks, and permission gaps. Fix where possible

**Fix policy**:
- Fix minor, safely applicable issues directly (do NOT commit — leave as unstaged diffs)
- For high-impact issues, propose a dedicated task instead of forcing a fix

**Report findings by severity**: Critical / High / Medium / Low. Each item must include:

- Target file and line number
- Description of the issue
- Impact
- Action taken (fixed / not fixed with reason / proposed as task)

**Summary** at the end:

- List of modified files (by the review itself)
- Remaining issues (with ticket proposals if needed)
- Verification results (lint/build)

**Task file update**: If `$GIT_ROOT/.hq/tasks/<branch>.md` exists, append the review results as a `## Code Review <YYYY-MM-DD HH:MM>` section. Summarize findings concisely within this section.
