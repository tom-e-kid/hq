---
name: code-review
description: >
  Review code changes against quality criteria.
  Reports findings with severity classification. Does not modify code directly.
---

## Project Overrides

- Overrides: !`cat .hq/code-review.md 2>/dev/null || echo "none"`

If `.hq/code-review.md` exists, its instructions take precedence over the defaults below (e.g., review focus areas, excluded paths). Apply overrides on top of this skill's base flow.

## Diff Scope

Target:

- `git log <base>..HEAD --oneline` — commit list
- `git diff <base>...HEAD --stat` — file change summary
- `git diff <base>...HEAD` — full diff

Exclude from review:

- `node_modules/`
- Build artifacts (`.next/`, `dist/`, `coverage/`, `build/`)
- Lock files (`bun.lock`, `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`)

## Review Criteria

- **Readability & conciseness**: Identify verbose or unnecessary code and simplify where possible
- **Correctness**: Check for spec deviations, potential bugs, and missed edge cases
- **Performance**: Look for redundant computations, unnecessary re-renders, heavy operations, and inefficient data processing
- **Security**: Check for insufficient input validation, XSS/injection risks, credential leaks, and permission gaps

## Fix Policy

- **Do not modify code directly** — all issues are reported, not fixed
- Respect existing architecture and coding conventions
- Do not propose unnecessary dependencies or large-scale refactors

## Reporting Format

Report findings by severity: Critical / High / Medium / Low

Each item must include:

- Target file and line number
- Description of the issue
- Impact
- Severity classification

End with a summary:

- Total issues by severity
- Informational items (no action needed)
