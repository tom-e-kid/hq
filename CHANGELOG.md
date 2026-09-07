# Changelog

All notable changes to the `hq` Claude Code plugin.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Maintenance and release procedures live in `AGENTS.md` § Releasing (the
source of truth). Two rules matter day to day:

- **Append to `[Unreleased]` in the same PR as the change** (do not batch-write at
  release time). Granularity is what changed for the plugin user, not commits.
- Each version's section is used verbatim as the GitHub Release notes by
  `.claude/scripts/release.sh`; the release aborts if the section is missing or empty.

## [Unreleased]

## [0.1.0] - 2026-09-07

### Added

- **The initial public tree.** A Claude Code plugin that runs one branch's
  development cycle as separate commands — `plan`, `implement`, `review`,
  `triage`, `pr`, `archive`, `xcodebuild-config` — with `loop` calling them in
  turn. Two agents (a builder and a verifier), gates that intercept tool calls
  where the question is decidable, and telemetry appended to a stream outside
  the repository. `docs/design.md` is the canon and carries, per module, the
  list of things nothing guarantees; it is written to be read without reaching
  outside this repository, so it cites no pull request number, date or row
  count that a reader here cannot resolve.

  This repository begins at the tree as it stood; the work that led here was
  done elsewhere and its history is not carried over. Nothing in `plugin/` is
  frozen or versioned — there is one plugin directory and it is the live one.

- **A commit-time sweep for content that must not be published**
  (`.claude/scripts/secrets-check.sh`, wired through `githooks/pre-commit` and
  the repository gate). Refuses private keys, provider tokens, absolute home
  paths, addresses, and terms named in a blocklist kept outside the repository.

[Unreleased]: https://github.com/tom-e-kid/hq/compare/v0.1.0...develop
[0.1.0]: https://github.com/tom-e-kid/hq/releases/tag/v0.1.0
