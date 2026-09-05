---
description: Fast-forward develop into main, create the tag and GitHub Release (dev)
argument-hint: <x.y.z> [--dry-run]
allowed-tools: Bash
---

Run this repository's release — a **dev command** (repo-local; not part of the distributed plugin). Respond in the conversation language.

All condition checks, the merge, the push, the tag, and the Release creation are performed by `.claude/scripts/release.sh`. **Do not re-implement its safety checks in prose.** Never run `git merge` / `git push` / `git tag` / `gh release create` directly yourself.

Arguments `$ARGUMENTS`:

- `<x.y.z>` — the version to release (tag name is `v<x.y.z>`)
- `--dry-run` — validation and release-notes extraction only. No merge / push / tag / Release.

## Preconditions (this command does not create them)

**The release-prep commit is on `develop`.** Concretely:

- `.claude-plugin/plugin.json` `version` is set to `<x.y.z>`
- `CHANGELOG.md` has a `## [<x.y.z>] - YYYY-MM-DD` section with content
- `develop` matches `origin` (pushed)

If not, the script stops with exit 2. **In that case do not attempt the release; report that the release-prep commit is required and stop.**

## Execution

**Always run `--dry-run` first, present its output (release plan and release notes) to the user, and get approval before the real run.** Never execute the real run without approval.

```bash
bash "$CLAUDE_PROJECT_DIR/.claude/scripts/release.sh" <x.y.z> --dry-run
```

After approval:

```bash
bash "$CLAUDE_PROJECT_DIR/.claude/scripts/release.sh" <x.y.z>
```

## Reporting

- **dry-run**: present the `release plan` (source/target SHAs, commit count, planned commands) and `release notes` verbatim, then ask whether to proceed.
- **exit 0 (real run)**: present the advanced `main` SHA, the created tag, and the Release URL. Add one line reminding to check that `CHANGELOG.md` has an empty `[Unreleased]` section for the next cycle.
- **non-zero**: present the script's stderr verbatim with a one-line reason for the stop. State exactly how far execution got (nothing changed / `main` pushed but tag not created, etc.) according to the stderr message. **Do not guess that things are "probably fine".**
