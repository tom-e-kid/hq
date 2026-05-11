---
name: integrity-check
description: >
  Detect external integrity gaps created by a diff — `[削除]` residuals lingering elsewhere
  in the repo, unmatched `*(consumer: <name>)*` declarations whose target needs external
  verification, and (in interactive fallback mode) downstream references / half-shipped
  features that survive a rename / removal. Explicitly looks **beyond** the hunks: extracts
  changed symbols / file paths / command / rule names from the diff and greps the whole repo
  for stale references.
---

## Project Overrides

- Overrides: !`cat .hq/integrity-check.md 2>/dev/null || echo "none"`

If `.hq/integrity-check.md` exists, its instructions take precedence over the defaults below (e.g., extra reference patterns, additional scope-boundary heuristics, excluded paths). Apply overrides on top of this skill's base flow.

## Why This Skill Exists

`code-review` looks at the hunks. `security-scan` looks at the hunks. Nothing looks at the files the hunks depend on. When a diff renames a helper, removes a command flag, or changes a rule name, downstream references that were **not touched** by the diff stay stale, and the feature ships half-wired. Mechanical `## Editable surface` ↔ diff set-diff (orchestrator-side at Phase 6 Self-Review) catches half of this — diff-but-undeclared and declared-but-missing within the diff file list — but the **other half** lives in external paths the diff never touches: a deleted symbol still referenced by a doc page, a named consumer in a Plan suffix that ought to have been visited but wasn't.

This skill's job is to break that blind spot via external grep. The agent-mode scope (under `/hq:start` Phase 7) is intentionally narrow — `[削除]` residuals + unmatched consumer verification — because the orchestrator's Phase 6 Self-Review already covers everything mechanical within the diff. The interactive `/integrity-check` mode (no plan context) falls back to a broader downstream-reference / feature-completeness sweep.

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

The baseline criteria below capture the skill's three-class model — used when `/integrity-check` is invoked interactively (no plan context). The `integrity-checker` agent overrides these at runtime with a narrower **external-grep-only** scope: `[削除]` residual grep + unmatched consumer external visits. Mechanical Editable surface ↔ diff reconciliation is no longer performed by the agent — it is owned by the `/hq:start` orchestrator at Phase 6 (Self-Review).

### 1. External grep gaps (agent override — primary)

When invoked by `/hq:start` Phase 7 Step 2, the agent restricts itself to two failure modes that mechanical orchestrator-side checks cannot catch:

- **`[削除]` residuals** — for each `## Editable surface` entry tagged `[削除]`, whole-repo grep for residual references. Hits outside the diff = stale references.
- **Unmatched consumer external visits** — for `*(consumer: <name>)*` suffixes whose named consumer is not in the diff file list, read / grep the named path to verify the coordinated update landed.

Other tag classes (`[新規]` / `[改修]` / `[silent-break]`) and in-diff consumer presence are out of scope for the agent — orchestrator's Phase 6 Self-Review covers them.

### 2. Downstream reference integrity (interactive fallback)

Used when no plan context is available (e.g., `/integrity-check` run interactively). For each **removed / renamed / signature-changed** token, grep the whole repo (respecting exclusions) for surviving references. Any hit outside the diff that still uses the old name / old signature is a stale reference.

- Same-repo references in code and markdown
- Workflow-rule citations (`hq:workflow § <section>`) that refer to renamed sections
- Documentation that describes removed commands, flags, or files

### 3. End-to-end feature completeness (interactive fallback)

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

Report findings grouped by the Review Criteria class they belong to. When operating under the primary (agent override — external grep) criterion, group entries by failure mode (`[削除]` residuals / unmatched consumer external visits). When operating under the fallback criteria (no plan context), group by downstream reference integrity / end-to-end feature completeness. Within each group, sort by severity: Critical / High / Medium / Low.

Each item must include:

- **Changed token** — the symbol / path / command / rule name that triggered the check, and the direction (added / removed / renamed / signature-changed)
- **Stale location(s)** — file and line numbers of surviving references (or the unmatched-consumer site)
- **Description** — what is inconsistent, in one or two sentences
- **Impact** — what breaks, or what misleads, because of this
- **Severity** — Critical / High / Medium / Low

End with a summary:

- Total issues by severity
- Informational items (no action needed)
