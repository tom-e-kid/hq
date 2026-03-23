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
    - "Commit first" — ask for a commit message, stage relevant files, commit,
      then proceed to Step 5 (the new commit will be included in the review diff)
    - "Continue without committing" — warn that uncommitted changes won't be included in the review diff

### 5. Gather diff

Run these as separate Bash calls (parallelizable):

1. `git log $BASE..HEAD --oneline` — commit list
2. `git diff $BASE...HEAD --stat` — file change summary
3. `git diff $BASE...HEAD` — full diff

Exclude the following from review:

- `node_modules/`
- Build artifacts (e.g., `.next/`, `dist/`, `coverage/`)
- Auto-updated lock files (`bun.lock`, `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`)

### 6. Review context

**Task file integration**: Derive the task filename by taking the current branch name and replacing `/` with `-`. Check if `$GIT_ROOT/.hq/tasks/<branch>.md` exists. If found, read it to understand:

- Planned goal and context
- Implementation approach and key decisions
- Completion status of planned steps

**Requirements**: If `$GIT_ROOT/docs/requirements.md` exists, use it as a reference for project requirements.

### 7. Security Alert Scan

Scan the full diff against all categories defined in the **Security Alert Policy** section of `plugin/skills/reviewer/SKILL.md`. Do not judge whether findings are intentional or safe — just find and report. At the end of this step, explicitly state either **"Alerts found"** or **"No alerts found"**.

**Command-specific rules**:

- `.env` changes should be reported under Out-of-Scope Changes, not under Credentials & Secrets
- Appending to `$GIT_ROOT/.hq/tasks/<branch>.md` at the end of this command is an explicitly permitted out-of-scope change. Do not raise an alert for this operation.

**If Credentials & Secrets are detected**: warn the user with the file name and line number. Use AskUserQuestion to confirm whether to continue the review.

### 8. Review and report

Review the diff against the criteria in the **What To Check** section of `plugin/skills/reviewer/SKILL.md`. Apply the **Fix Policy** and **Reporting Format** from the same skill.

**Command-specific override**: Do NOT commit fixes — leave changes as unstaged diffs.

Security alerts from Step 7 are reported in a dedicated `### Security Alerts` subsection, separate from severity-based findings.

**Task file update**: If `$GIT_ROOT/.hq/tasks/<branch>.md` exists, append the review results as a `## Code Review <YYYY-MM-DD HH:MM>` section. Summarize findings concisely within this section.
