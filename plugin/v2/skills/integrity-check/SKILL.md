---
name: integrity-check
description: >
  Detect end-to-end integrity gaps created by a diff — downstream references that were
  not updated, half-shipped features, and hidden violations of the plan's `## Out of scope`.
  Explicitly looks **beyond** the hunks: extracts changed symbols / file paths / command /
  rule names from the diff and greps the whole repo for stale references.
---

## Project Overrides

- Overrides: !`cat .hq/integrity-check.md 2>/dev/null || echo "none"`

If `.hq/integrity-check.md` exists, its instructions take precedence over the defaults below (e.g., extra reference patterns, additional scope-boundary heuristics, excluded paths). Apply overrides on top of this skill's base flow.

## Why This Skill Exists

`code-review` looks at the hunks. `security-scan` looks at the hunks. Nothing looks at the files the hunks depend on. When a diff renames a helper, removes a command flag, or changes a rule name, downstream references that were **not touched** by the diff stay stale, and the feature ships half-wired. Plans try to guard this via `## Out of scope`, but scope carve-outs are frequently where the gaps hide: the plan says "X is out of scope," the change depends on X, X is not updated, and no reviewer objects because reviewers honor scope too strictly.

This skill's job is to break that blind spot. It reads the diff, pulls every referenceable token out of the changed side, and greps the repo to verify downstream consumers are consistent. Violations are reported as FBs even when they fall outside the plan's `## In scope`.

## Diff Scope

Target:

- `git log <base>..HEAD --oneline` — commit list
- `git diff <base>...HEAD --stat` — changed-file summary
- `git diff <base>...HEAD` — full diff (both sides; rename sources matter)

Exclude from analysis:

- `node_modules/`
- Build artifacts (`.next/`, `dist/`, `coverage/`, `build/`)
- Lock files (`bun.lock`, `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`)

## Extraction Targets

From the diff, extract every item that can be referenced from elsewhere. For each, record the token and the direction of change (added / removed / renamed / signature-changed).

- **Symbols** — function / method / type / constant / enum-variant names introduced, removed, or renamed. Include language-level identifiers from added/removed declarations on both sides of the hunk.
- **File paths** — paths that were created, deleted, moved, or renamed. Include both the old and the new path for renames.
- **Command / subcommand names** — new or removed slash-commands (`/hq:<name>`), CLI subcommands, npm/bun scripts, mise tasks, make targets.
- **Rule / section names** — structural heading names (`## Out of scope`, `## Known Issues`, `## Context`, `## Acceptance`, …), FB field names, workflow-rule section names (`hq:workflow § <section>`), label names (`hq:plan`, `hq:pr`, …).
- **Config keys** — JSON/YAML/TOML keys added or removed (e.g., `base_branch`, `allowed-tools`), environment variable names.
- **Public API shape** — exported symbols whose signature (arguments, return type, frontmatter schema) changed. The token did not move, but its contract did — callers may silently break.

## Review Criteria

The baseline criteria below capture the skill's historical three-class model. The `integrity-checker` agent overrides these at runtime with a narrower scope: reconciliation of the `hq:plan` `## Context` (especially `**Impact**`) against the diff (declared-but-missing / diff-but-undeclared). When invoked interactively via `/integrity-check` without an active plan context, fall back to the three-class model below.

### 1. Plan / diff reconciliation (primary — agent override)

When a plan's `## Context` with `**Impact**` is available, evaluate these two failure modes:

- **Declared-but-missing** — an Impact entry lists a surface / consumer / contradiction, but the diff shows no corresponding change. Either the diff is incomplete or the Impact was aspirational.
- **Diff-but-undeclared** — the diff reaches a surface or consumer that Impact does not list, and no `## Out of scope` carve-out excuses it. Scope creep hiding in the implementation.

Backward compat: if the plan has no `**Impact**` block (pre-Impact plans), skip this criterion entirely and exit cleanly without FBs.

### 2. Downstream reference integrity (fallback)

Used when no plan context is available. For each **removed / renamed / signature-changed** token, grep the whole repo (respecting exclusions) for surviving references. Any hit outside the diff that still uses the old name / old signature is a stale reference.

- Same-repo references in code and markdown
- Workflow-rule citations (`hq:workflow § <section>`) that refer to renamed sections
- Documentation that describes removed commands, flags, or files

### 3. End-to-end feature completeness (fallback)

Used when no plan context is available. Mentally trace the path from entrypoint to effect for each changed feature. Look for:

- New entrypoint (command / route / agent) that is not wired in from any caller
- New config key that nothing reads, or removed key that something still reads
- New rule / section / heading whose consumers still look for the old one
- Producer / consumer mismatch across layers (e.g., new frontmatter field, old validator; new label, old filter; new marker, old parser)

If a feature cannot reach from its declared entrypoint to its declared effect using the current codebase, it is half-shipped. Report as an FB.

## Severity Classification

- **Critical** — the feature is broken end-to-end (entrypoint missing, consumer reads a non-existent key, removed name is still the only API surface)
- **High** — stale reference survives and will misdirect users/tools (doc references a renamed command, rule file cites a deleted section)
- **Medium** — inconsistency that is recoverable but will confuse (two names for the same thing coexist; one side updated, other side stale)
- **Low** — cosmetic drift (wording mismatch, stale example with no behavioral consequence)

## Fix Policy

- **Do not modify code directly** — all issues are reported via FB files; the root agent decides what to fix
- **Scope carve-outs are not a defense** — if the plan's `## Out of scope` is the reason a gap exists, report the gap and call out the scope violation explicitly
- **Prefer under-reporting false positives over suppressing real gaps** — if integrity cannot be verified (grep is inconclusive), escalate to an FB with the evidence gathered

## Reporting Format

Report findings grouped by the three Review Criteria classes (Downstream reference integrity / Scope boundary integrity / End-to-end feature completeness). Within each group, sort by severity: Critical / High / Medium / Low.

Each item must include:

- **Changed token** — the symbol / path / command / rule name that triggered the check, and the direction (added / removed / renamed / signature-changed)
- **Stale location(s)** — file and line numbers of surviving references (or the missing-consumer site, for end-to-end gaps)
- **Description** — what is inconsistent, in one or two sentences
- **Impact** — what breaks, or what misleads, because of this
- **Severity** — Critical / High / Medium / Low
- **Scope note** — if the gap falls inside a `## Out of scope` area of the plan, say so and recommend adjusting scope or completing the feature

End with a summary:

- Total issues by severity
- Count of `## Out of scope` violations (subset of the above)
- Informational items (no action needed)
