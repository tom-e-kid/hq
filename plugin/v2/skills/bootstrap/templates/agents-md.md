# AGENTS.md

Instructions for AI coding agents performing code review and security scanning on this repository.

## Scope

When reviewing code changes on a branch, compare against the base branch using the merge-base (`git diff <base>...HEAD`).

Exclude the following from review:

- `node_modules/`
- Build artifacts (`.next/`, `dist/`, `coverage/`, `build/`)
- Lock files (`bun.lock`, `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`)

## Feedback Output

Code review findings must be output as feedback files (FB) so they can be tracked and resolved through a shared workflow.

### Directory

Branch name in the path: replace `/` with `-` (e.g., `feat/auth` → `feat-auth`).

```
.hq/tasks/<branch>/feedbacks/              # pending — files here need action
.hq/tasks/<branch>/feedbacks/done/         # resolved
```

### Numbering

Check existing files in `feedbacks/` and `feedbacks/done/` to determine the next number. Format: `FB001.md`, `FB002.md`, etc. (zero-padded to 3 digits).

### FB File Format

```markdown
---
source: <origin of the work, e.g. docs/milestones.md#M9>
agent: <agent name, e.g. copilot, cursor, codex>
run_at: <ISO 8601 timestamp>
---

# <concise description of the issue>

- **File**: <target file and line number>
- **Severity**: Critical / High / Medium / Low
- **Description**: <what is wrong>
- **Impact**: <why it matters>
- **Expected**: <what the code should do>
- **Actual**: <what the code currently does or risks>
```

One FB file per issue. Do not bundle multiple issues into one file.

## Code Review

Review changed code against the following criteria. Do not modify code — report findings only.

### Review Criteria

- **Readability & conciseness**: Identify verbose or unnecessary code and simplify where possible
- **Correctness**: Check for spec deviations, potential bugs, and missed edge cases
- **Performance**: Look for redundant computations, unnecessary re-renders, heavy operations, and inefficient data processing
- **Security**: Check for insufficient input validation, XSS/injection risks, credential leaks, and permission gaps

### Output

For each actionable finding, output an FB file following the **Feedback Output** section above.

Also report a summary to the user by severity: Critical / High / Medium / Low, with total counts and list of FB files created.

### Constraints

- Do not modify code directly — output FB files only
- Respect existing architecture and coding conventions
- Do not propose unnecessary dependencies or large-scale refactors

## Security Scan

Scan changed code for the following security-sensitive patterns. Detection only — do not judge whether findings are intentional or safe. Just find and report.

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
- If no clear justification can be inferred, flag explicitly as: `Reason: unclear — human review required`

### Output

Security scan findings are **not** output as FB files — they require human judgment, not automated fixes.

Save the report to `.hq/tasks/<branch>/reports/security-scan-<YYYY-MM-DD-HHMM>.md`. Branch name: replace `/` with `-`.

Group findings by category. Each item must include:

- Target file and line number
- Matched pattern or description
- One-line context explanation

End with: **"Alerts found"** or **"No alerts found"**
