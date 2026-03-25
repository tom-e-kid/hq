---
name: code-review
description: >
  Review code changes on the current branch against the base branch.
  Reports findings with severity classification and outputs FB files
  for all actionable issues. Does not modify code directly.
allowed-tools: Read, Grep, Glob, Bash(git *), Write(.hq/tasks/*)
---

## Project Overrides

- Overrides: !`cat .hq/code-review.md 2>/dev/null || echo "none"`

If `.hq/code-review.md` exists, its instructions take precedence over the defaults below (e.g., review focus areas, excluded paths). Apply overrides on top of this skill's base flow.

## Context

- Project root: !`git rev-parse --show-toplevel`
- Current branch: !`git rev-parse --abbrev-ref HEAD`
- Base branch: resolve by reading `.hq/settings.json` field `base_branch`, or `git symbolic-ref refs/remotes/origin/HEAD`, or default `main`
- Commits: run `git log --oneline <base-branch>..HEAD` using the Base branch above
- Changed files: run `git diff <base-branch>...HEAD --stat` using the Base branch above
- Uncommitted changes: !`git status --short`
- Focus: !`cat memory/focus.md 2>/dev/null || echo "none"`

## Instructions

### 1. Validate Preconditions

- If on the base branch (`main`, `master`, `develop`): abort with error
- If there are no commits ahead of the base branch: abort — nothing to review
- If uncommitted changes exist: warn the user and ask whether to commit first or continue (uncommitted changes won't be included in the review diff)

### 2. Gather Diff

Run in parallel:

1. `git log <base>..HEAD --oneline` — commit list
2. `git diff <base>...HEAD --stat` — file change summary
3. `git diff <base>...HEAD` — full diff

Exclude from review:

- `node_modules/`
- Build artifacts (`.next/`, `dist/`, `coverage/`, `build/`)
- Lock files (`bun.lock`, `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`)

### 3. Gather Review Context

- **Focus**: check `memory/focus.md` — if it exists, extract the `source` and `taskfile` fields from its frontmatter. Read the referenced taskfile to understand planned goals, approach, and gates. If no focus, check `.hq/tasks/<branch>/context.md` as fallback
- **Requirements**: if `docs/requirements.md` exists, use as reference
- **Project overrides**: if `.hq/code-review.md` exists, apply its instructions

### 4. Review

Review the diff against the **Review Criteria** below.

### 5. Report & Output

Report findings using the **Reporting Format** below.

For each actionable issue, output an FB file following the workflow's FB Output Rules. Set `skill: /code-review` in the frontmatter. Set `source` and `taskfile` from `memory/focus.md` (fallback: `.hq/tasks/<branch>/context.md`).

---

## Review Criteria

- **Readability & conciseness**: Identify verbose or unnecessary code and simplify where possible
- **Correctness**: Check for spec deviations, potential bugs, and missed edge cases
- **Performance**: Look for redundant computations, unnecessary re-renders, heavy operations, and inefficient data processing
- **Security**: Check for insufficient input validation, XSS/injection risks, credential leaks, and permission gaps

## Fix Policy

- **Do not modify code directly** — all issues are reported via FB files
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
- FB files created (with paths)
- Informational items (no FB needed)
