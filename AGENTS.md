# hq

A repository that develops a plugin for running AI-assisted development cycles
across projects.

**This file is the convention for working *in* this repository. It does not
travel with the plugin.** The plugin's own contract lives in `plugin/` and
`docs/design.md`. So the gate, the branch model and the language policy below
are this repository's, not the plugin's — the plugin derives its base branch
and its working directory from wherever it is installed, and knows none of
these values.

## Layout

- **`.claude-plugin/plugin.json`** — the manifest. It registers `plugin/` and
  nothing else.
- **`plugin/`** — the plugin itself. **No design documents live under it**: the
  plugin is the deliverable, and it does not read the design.
- **`AGENTS.md`** (this file) — the conventions. **The content lives here and
  `CLAUDE.md` is one `@AGENTS.md` import.** Only `CLAUDE.md` supports imports,
  so the other direction leaves an agent that reads only `AGENTS.md` with a
  sentence pointing elsewhere.
- **`docs/design.md`** — the canon: goals, architecture, modules, and a table
  per module of what nothing guarantees. Forward-looking contracts only.
- **`docs/postmortems.md`** — defects this project shipped or nearly shipped,
  with the measurements. Information, not rules: nothing here depends on it,
  and the guarantees are the checks `docs/design.md` § 設計原則 defines. It
  exists because these patterns cost real rework.
- **`.claude/scripts/`** — this repository's own gate. Not part of the plugin.

**Nothing is frozen and nothing is versioned.** There is one `plugin/`
directory and it is the live one.

**There is no build step** — the source is the deliverable. It is not only
markdown: `plugin/scripts/` holds bash and its tests.

## The gate

There is no CI. Running it locally is the only gate.

```
bash .claude/scripts/check.sh
```

**One entry point, because two get half-remembered.** It runs the plugin suite,
this directory's suites, the document checks and the sweep for content that
must not be published, and exits 0 when all of them pass.

**Two granularities.** Mid-change, the `*.test.sh` beside the script you
touched is enough — `docs-check.sh` for prose. Run the whole gate once when a
change is complete.

## Releasing

Users install from `main`; development happens on `develop`.

- **`main`** — the distribution branch and the GitHub default. It only ever
  fast-forwards from `develop`. **Never push to it, push a tag, or create a
  Release by hand**: `/hq-release` and `.claude/scripts/release.sh` hold the
  preconditions and the approval.
- **`develop`** — topic branches (`feat/*`, `fix/*`, `chore/*`, `docs/*`,
  `refactor/*`) take this as their pull request base, never `main`.
- No `release/*` or `hotfix/*`. One deliverable, so a release *is* an update
  to `main`.

**The changelog is written per pull request**, into `## [Unreleased]`, at the
granularity of what changed for a plugin user rather than per commit. Each
version's section becomes the GitHub Release notes verbatim.

**Releasing edits `CHANGELOG.md` in three places**: rename `## [Unreleased]` to
`## [<x.y.z>] - <YYYY-MM-DD>`, open an empty `## [Unreleased]` above it, and
update the link references at the end. Land that with the `version` bump in
`.claude-plugin/plugin.json` on a `chore/release-<x.y.z>` branch before running
`/hq-release`.

## Naming hygiene

**Every example in the plugin's own content** — the commands, agents, hooks and
scripts under `plugin/` — **uses invented identifiers**: class names, file
paths, ticket numbers and document ids that do not exist, and placeholder
domains (`example.com`). Do not name a real company, a commercial product or
service, a customer's project, or another repository on this machine. The names
of tools this plugin actually integrates with (GitHub, Xcode, Copilot) and
ordinary open-source tool names are fine.

**The same applies to `docs/`, because this repository is public.** There used
to be an exemption on the grounds that `docs/` never left the repository;
publishing ended that. Design documents still rest on measurements, but **only
on facts that are public** — this repository's own pull request numbers and
commits are fair game. Someone else's repository, a customer's project, or
another deliverable on this machine is not, in `docs/` either.

## The commit-time sweep

Two checks run before a commit, and they miss different things:

- `.claude/scripts/secrets-check.sh` — patterns and a named list. The list of
  terms lives outside the repository, at `~/.hq/blocklist`.
- `.claude/scripts/semantic-check.sh` — asks a model whether the commit names a
  company, a customer, a person or another project, applying § Naming hygiene
  above, read at run time rather than copied.

**Why each one is shaped the way it is, and what it does not hold, is in the
header of that script.** Both name their own hole; read them before trusting
either.

Turn the hook on once per clone. **This line is the first hole**: a clone
without it commits unchecked, which is why the pattern half also runs from the
gate.

```
git config core.hooksPath githooks
```

## Language

The axis is **who reads it**, not whether it ships — `plugin/` is entirely
deliverable, so that second axis would put the first and third rows below on
the same side.

- **Instructions an LLM reads at run time** — the commands and agents under
  `plugin/`, and whatever the hooks and scripts emit (comments, `--help`,
  diagnostics): English.
- **Files placed in the installing repository and injected**
  (`.hq/knowledge.md`): English. Not under `plugin/`, same readers.
- **What a reader of this repository reads** (this file, `README`,
  `CHANGELOG`): English. The changelog becomes release notes verbatim.
- **Design and record** (`docs/`): Japanese.
- **The session's conversation**: whatever the user is speaking.

## Reference

For the plugin's own structure — `plugin.json`, commands, agents, skills,
hooks — read the official documentation rather than inferring from this tree:
https://code.claude.com/docs/en/plugins
