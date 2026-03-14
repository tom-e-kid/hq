---
name: reviewer
description: >
  This skill should be used when performing code review, either manually
  ("review code", "check for issues") or as part of the development workflow.
  Defines review criteria, security alert policy, and reporting standards.
---

# reviewer

Code review standards for the HQ plugin ecosystem. This skill is the single source of truth for review criteria, security alerts, and reporting format.

**Prerequisite**: This skill assumes `dev-core` skill conventions (commit format, backlog, etc.).

## Review Context & Scope

- If `.hq/settings.json` exists and contains `base_branch`, use that value; otherwise default to `main`
- Compare against the merge-base with the resolved base branch
- Exclude the following from review:
  - `node_modules/`
  - Build artifacts (e.g., `.next/`, `dist/`, `coverage/`)
  - Auto-updated lock files (`bun.lock`, `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`)

## What To Check

- **Readability & conciseness**: Identify verbose or unnecessary code and simplify where possible
- **Correctness**: Check for spec deviations, potential bugs, and missed edge cases
- **Performance**: Look for redundant computations, unnecessary re-renders, heavy operations, and inefficient data processing. Fix where possible
- **Security**: Check for insufficient input validation, XSS/injection risks, credential leaks, and permission gaps. Fix where possible

## Security Alert Policy

This section is independent of the Security item in "What To Check". No fixes or judgments are required — only detection and reporting.

Regardless of severity classification, **always report** any occurrence of the following. Do not judge whether it is intentional or safe — just find and report. At the end of this section, explicitly state either **"Alerts found"** or **"No alerts found"**.

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
- If no clear justification can be inferred, flag it explicitly as: `Reason: unclear — human review required` and provide a detailed description of the concern

## Fix Policy

- Fix minor, safely applicable issues directly
- For high-impact issues, propose a dedicated task instead of forcing a fix
- Do not commit fixes. Leave changes as unstaged diffs in the working tree

## Reporting Format

- Report findings by severity: Critical / High / Medium / Low
- Each item must include:
  - Target file and line number
  - Description of the issue
  - Impact
  - Action taken (fixed / not fixed with reason / proposed as task)
- Security alerts are reported in a dedicated `### Security Alerts` subsection, separate from severity-based findings
- End with a summary:
  - List of modified files
  - Remaining issues (with ticket proposals if needed)
  - Verification results (lint/build)

## Validation

- If clear verification targets exist at the start of review, run those checks first and reflect results in the review
- Lint and build are expected to pass before code review (enforced by `dev-core` Verification Gates). If failures are found during review, flag them but do not fix — report as findings

## Constraints

- Respect existing architecture and coding conventions
- Do not add unnecessary dependencies or perform large-scale refactors without clear justification
