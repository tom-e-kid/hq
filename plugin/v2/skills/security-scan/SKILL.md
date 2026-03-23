---
name: security-scan
description: >
  Scan code changes on the current branch for security-sensitive patterns.
  Detection only — no judgment, no fixes. Reports findings for human review.
allowed-tools: Read, Grep, Glob, Bash(git *), Write(.hq/tasks/*)
---

## Project Overrides

- Overrides: !`cat .hq/security-scan.md 2>/dev/null || echo "none"`

If `.hq/security-scan.md` exists, its instructions take precedence over the defaults below (e.g., known-safe patterns to suppress, additional scan categories). Apply overrides on top of this skill's base flow.

## Context

- Project root: !`git rev-parse --show-toplevel`
- Current branch: !`git rev-parse --abbrev-ref HEAD`
- Base branch: !`cat .hq/settings.json 2>/dev/null | grep -o '"base_branch"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"base_branch"[[:space:]]*:[[:space:]]*"//;s/"//' | grep . || git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo "main"`
- Commits: !`base=$(cat .hq/settings.json 2>/dev/null | grep -o '"base_branch"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"base_branch"[[:space:]]*:[[:space:]]*"//;s/"//' | grep . || git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo "main"); git log --oneline "$base"..HEAD 2>/dev/null`
- Changed files: !`base=$(cat .hq/settings.json 2>/dev/null | grep -o '"base_branch"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"base_branch"[[:space:]]*:[[:space:]]*"//;s/"//' | grep . || git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo "main"); git diff "$base"...HEAD --stat 2>/dev/null`

## Instructions

### 1. Validate Preconditions

- If on the base branch (`main`, `master`, `develop`): abort with error
- If there are no commits ahead of the base branch: abort — nothing to scan

### 2. Gather Diff

`git diff <base>...HEAD` — full diff

Exclude:

- `node_modules/`
- Build artifacts (`.next/`, `dist/`, `coverage/`, `build/`)
- Lock files (`bun.lock`, `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`)

### 3. Scan

Scan the full diff against all categories in the **Alert Policy** below. Do not judge whether findings are intentional or safe — just detect and report.

**Exceptions**:

- `.env` changes → report under Out-of-Scope Changes, not Credentials & Secrets

If Credentials & Secrets are detected: warn immediately with file and line, ask user whether to continue.

### 4. Report

Output the report using the **Reporting Format** below. End with explicit **"Alerts found"** or **"No alerts found"**.

Save the report to `.hq/tasks/<branch>/reports/security-scan-<YYYY-MM-DD-HHMM>.md`. Branch name: replace `/` with `-`.

This skill does **not** output FB files. Findings require human judgment, not automated fixes.

---

## Alert Policy

Regardless of severity, **always report** any occurrence of the following. Do not judge whether it is intentional or safe — just find and report.

### Credentials & Secrets

- API keys / secrets (`AKIA`, `sk-`, `ghp_`, `Bearer`, etc.)
- Reading environment variables whose names contain: `KEY`, `SECRET`, `TOKEN`, `PASSWORD`, `CREDENTIAL`
- Hardcoded strings that resemble secrets or tokens
- Credentials written to logs or sent externally

### External Communication

- HTTP/HTTPS requests, WebSocket connections
- DNS resolution or references to external hosts
- Outbound integrations (email, Slack, webhooks, etc.)

### File & System Operations

- File access outside the project directory
- File deletion or unconditional overwrite
- Permission or ownership changes

### Dynamic Code Execution

- Dynamic evaluation functions and their equivalents across languages
- Dynamic imports resolved at runtime
- Serialization/deserialization of untrusted data (e.g., unsafe deserializers, `JSON.parse` on external input)

### Out-of-Scope Changes

- Modifications to files outside the reviewed diff
- Addition or version change of dependencies
- Changes to configuration files (`.env`, `*.config.*`, `*.yaml`, etc.)

### Explainability

- For each alert item, include a one-line explanation of **why this code exists** based on context
- If no clear justification can be inferred, flag explicitly as: `Reason: unclear — human review required` with a detailed description

## Reporting Format

Group findings by alert category. Each item must include:

- Target file and line number
- Matched pattern or description
- One-line context explanation (see Explainability)

End with:

- Total alerts by category
- **"Alerts found"** or **"No alerts found"**
