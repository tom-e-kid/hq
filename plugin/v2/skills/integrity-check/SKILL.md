---
name: integrity-check
description: >
  Detect end-to-end integrity gaps created by a diff — downstream references that were
  not updated, half-shipped features, and diffs that touch surfaces absent from the plan's
  `## Editable surface` (the single AI agent fence). Explicitly looks **beyond** the hunks:
  extracts changed symbols / file paths / command / rule names from the diff and greps the
  whole repo for stale references.
---

## Project Overrides

- Overrides: !`cat .hq/integrity-check.md 2>/dev/null || echo "none"`

If `.hq/integrity-check.md` exists, its instructions take precedence over the defaults below (e.g., extra reference patterns, additional scope-boundary heuristics, excluded paths). Apply overrides on top of this skill's base flow.

## Why This Skill Exists

`code-review` looks at the hunks. `security-scan` looks at the hunks. Nothing looks at the files the hunks depend on. When a diff renames a helper, removes a command flag, or changes a rule name, downstream references that were **not touched** by the diff stay stale, and the feature ships half-wired. The plan's `## Editable surface` is the **positive set** — the single agent fence — but its complement (implicit out of scope) is precisely where these gaps hide: the diff updates the surface listed in the plan, but a downstream file that depends on that surface is not on the list and stays stale, and no reviewer objects because reviewers honor scope.

This skill's job is to break that blind spot. It reads the diff, pulls every referenceable token out of the changed side, and greps the repo to verify downstream consumers are consistent. Violations are reported as FBs even when they fall outside the plan's `## Editable surface` — completing a half-shipped feature is what matters, not honoring an under-declared positive set.

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
- **Rule / section names** — structural heading names (`## Why`, `## Approach`, `## Editable surface`, `## Plan`, `## Acceptance`, `## Known Issues`, …), Editable surface inline tags (`[新規]` / `[改修]` / `[削除]` / `[silent-break]`), Plan consumer suffix marker (`*(consumer: <name>)*`), FB field names, workflow-rule section names (`hq:workflow § <section>`), label names (`hq:plan`, `hq:pr`, …).
- **Config keys** — JSON/YAML/TOML keys added or removed (e.g., `base_branch`, `allowed-tools`), environment variable names.
- **Public API shape** — exported symbols whose signature (arguments, return type, frontmatter schema) changed. The token did not move, but its contract did — callers may silently break.

## Review Criteria

The baseline criteria below capture the skill's historical three-class model. The `integrity-checker` agent overrides these at runtime with a narrower scope: reconciliation of the `hq:plan` `## Editable surface` + `## Plan` against the diff (declared-but-missing / diff-but-undeclared). When invoked interactively via `/integrity-check` without an active plan context, fall back to the three-class model below.

### 1. Plan / diff reconciliation (primary — agent override)

When a plan's `## Editable surface` (with inline tags) and `## Plan` are available, evaluate these two failure modes:

- **Declared-but-missing** — a `## Editable surface` entry promises a change at a named surface (the inline tag `[新規]` / `[改修]` / `[削除]` / `[silent-break]` indicates the change class), but the diff shows no corresponding change. OR a `## Plan` item carries a `*(consumer: <name>)*` suffix, but the diff does not visit the named consumer. Either the diff is incomplete or the declaration was aspirational.
- **Diff-but-undeclared** — the diff reaches a surface that does not appear in `## Editable surface`. The positive set is the single agent fence; the complement is implicit out of scope by definition, so any touched surface absent from the list is scope creep. (Per the Boundary expansion protocol in `hq:workflow § ## hq:plan § ## Editable surface`, stack-natural extensions must be added to `## Editable surface` *before* the diff touches them. An after-the-fact diff against an unmodified list is a defect, not a permitted expansion.)

If the `## Editable surface` section is absent from the plan, the agent cannot perform reconciliation — apply § Without-plan fallback (exit cleanly with a "no plan context" report).

If a `## Editable surface` entry is present but **lacks an inline tag**, emit a "tag-less surface entry" FB at Medium severity. The plan reached Phase 6 with a Phase 2 convergence defect — flag it so the author can either add the tag or remove the entry.

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
- **Under-declared `## Editable surface` is not a defense** — if a gap exists at a downstream surface that the plan failed to list, report the gap and recommend updating `## Editable surface` (via the Boundary expansion protocol) to complete the feature, not narrowing the diff to honor the under-declared list
- **Prefer under-reporting false positives over suppressing real gaps** — if integrity cannot be verified (grep is inconclusive), escalate to an FB with the evidence gathered

## Reporting Format

Report findings grouped by the Review Criteria class they belong to. When operating under the primary (plan / diff reconciliation) criterion, group entries by failure mode (declared-but-missing / diff-but-undeclared). When operating under the fallback criteria (no plan context), group by downstream reference integrity / end-to-end feature completeness. Within each group, sort by severity: Critical / High / Medium / Low.

Each item must include:

- **Changed token** — the symbol / path / command / rule name that triggered the check, and the direction (added / removed / renamed / signature-changed)
- **Stale location(s)** — file and line numbers of surviving references (or the missing-consumer site, for end-to-end gaps)
- **Description** — what is inconsistent, in one or two sentences
- **Impact** — what breaks, or what misleads, because of this
- **Severity** — Critical / High / Medium / Low
- **Scope note** — if the gap falls at a surface absent from the plan's `## Editable surface`, say so and recommend either updating `## Editable surface` (Boundary expansion protocol) or completing the missing downstream work

End with a summary:

- Total issues by severity
- Count of diff-but-undeclared findings (subset of the above — surfaces touched without `## Editable surface` declaration)
- Informational items (no action needed)
