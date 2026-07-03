---
name: security-scan
description: >
  Scan code changes for security-sensitive patterns.
  Detection only — no judgment, no fixes. Reports findings for human review.
---

## Project Overrides

- Overrides: !`cat .hq/security-scan.md 2>/dev/null || echo "none"`

If `.hq/security-scan.md` exists, its instructions take precedence over the defaults below (e.g., known-safe patterns to suppress, additional scan categories). Apply overrides on top of this skill's base flow.

## Diff Scope

Target: `git diff <base>...HEAD` (full diff between base branch and HEAD)

Exclude from scan:

- `node_modules/`
- Build artifacts (`.next/`, `dist/`, `coverage/`, `build/`)
- Lock files (`bun.lock`, `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`)

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

## Scan Rules

- Scan the full diff against ALL categories above
- `.env` changes → report under Out-of-Scope Changes, not Credentials & Secrets
- For each alert item, include a one-line explanation of **why this code exists** based on context (Explainability)
- If no clear justification can be inferred, flag explicitly as: `Reason: unclear — human review required` with a detailed description
- This skill does **not** output FB files — findings require human judgment

## Reporting Format

Group findings by alert category. Each item must include:

- Target file and line number
- Matched pattern or description
- One-line context explanation

End with:

- Total alerts by category
- **"Alerts found"** or **"No alerts found"**
