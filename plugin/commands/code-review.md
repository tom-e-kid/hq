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

This step is independent of the Security item in Step 10. No fixes or judgments are required — only detection and reporting.

Scan the full diff for **all** of the following categories. Do not judge whether findings are intentional or safe — just find and report. At the end of this step, explicitly state either **"Alerts found"** or **"No alerts found"**.

#### Credentials & Secrets

- API keys / secrets (`AKIA`, `sk-`, `ghp_`, `Bearer`, etc.)
- Reading environment variables whose names contain: `KEY`, `SECRET`, `TOKEN`, `PASSWORD`, `CREDENTIAL`
- Hardcoded strings that resemble secrets or tokens
- Credentials written to logs or sent externally

#### External Communication

- HTTP/HTTPS requests, WebSocket connections
- DNS resolution or references to external hosts
- Outbound integrations (email, Slack, webhooks, etc.)

#### File & System Operations

- File access outside the project directory
- File deletion or unconditional overwrite
- Permission or ownership changes

#### Dynamic Code Execution

- `eval()`, `exec()`, `Function()`, `subprocess`, `os.system()`, or equivalent
- Dynamic imports resolved at runtime
- Serialization/deserialization of untrusted data (e.g., `pickle`, `JSON.parse` on external input)

#### Out-of-Scope Changes

- Modifications to files outside the reviewed diff
- Addition or version change of dependencies
- Changes to configuration files (`.env`, `*.config.*`, `*.yaml`, etc.)
  — `.env` changes should be reported here, not under Credentials & Secrets
- Note: Appending to `$GIT_ROOT/.hq/tasks/<branch>.md` at the end of this command is an explicitly permitted out-of-scope change. Do not raise an alert for this operation.

#### Explainability

- For each alert item, include a one-line explanation of **why this code exists** based on context.
- If no clear justification can be inferred, flag it explicitly as: `Reason: unclear — human review required` and provide a detailed description of the concern.

**If Credentials & Secrets are detected**: warn the user with the file name and line number. Use AskUserQuestion to confirm whether to continue the review.

### 8. Code simplification check

Launch the `code-simplifier` subagent targeting only the files changed in the diff. Let it check for verbosity, unnecessary code, and simplification opportunities. If it produces fixes, apply them but do NOT commit.

Constraints for the subagent:

- Target only files present in the diff from Step 5
- Do not modify files outside the diff scope
- Respect the implementation approach and priorities described in the task file (if found in Step 6)

### 9. Build verification

Detect and run the project's build command (e.g., `bun run build`, `npm run build`). If errors or warnings are found that can be fixed without spec clarification or user judgment, fix them directly but do NOT commit.

Also run the linter if available (e.g., `bun run lint`).

### 10. Review and report

Review the diff against these criteria:

- **Readability & conciseness**: Identify verbose or unnecessary code and simplify where possible
- **Correctness**: Check for spec deviations, potential bugs, and missed edge cases
- **Performance**: Look for redundant computations, unnecessary re-renders, heavy operations, and inefficient data processing. Fix where possible
- **Security**: Check for insufficient input validation, XSS/injection risks, and permission gaps. Fix where possible

**Fix policy**:

- Fix minor, safely applicable issues directly (do NOT commit — leave as unstaged diffs)
- For high-impact issues, propose a dedicated task instead of forcing a fix

**Report findings by severity**: Critical / High / Medium / Low. Each item must include:

- Target file and line number
- Description of the issue
- Impact
- Action taken (fixed / not fixed with reason / proposed as task)

Security alerts from Step 7 are reported in a dedicated `### Security Alerts` subsection, separate from severity-based findings.

**Summary** at the end:

- List of modified files (by the review itself)
- Remaining issues (with ticket proposals if needed)
- Verification results (lint/build)

**Task file update**: If `$GIT_ROOT/.hq/tasks/<branch>.md` exists, append the review results as a `## Code Review <YYYY-MM-DD HH:MM>` section. Summarize findings concisely within this section.
