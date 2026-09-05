# hq

A Claude Code plugin that walks one branch from idea to pull request — plan,
build, verify, triage, fix, ship. Run the steps one at a time, or chain them
into a single loop.

**One idea underneath it:** whoever checks the work is not whoever wrote it.
Most of the design falls out of that.

## Why you might want it

You already know the shape of the problem if you have watched an agent finish a
change and then tell you it looks good. hq splits that into parts:

- **You agree what "done" means before anything is built** — as outcomes, not
  as a task list, so the design stays open.
- **A different agent reads the diff afterwards** and has to point at where
  each outcome is actually satisfied. If it cannot find it, that is a finding.
- **Nothing claims a guarantee it does not have.** Where a check is impossible,
  the docs say so instead of implying otherwise.

If you just want a faster autocomplete, this is not that.

### What "as outcomes" looks like

The part of a plan you actually agree to is a table. Each row is one thing that
has to become true, next to who confirms it:

| # | what must be true | how anyone confirms it |
|---|---|---|
| R1 | a request that failed on a timeout is retried, at most three times | [review] trace the bound in the built code, and the test that asserts it |
| R2 | a request that failed on a 4xx is not retried | [review] the same, over the status codes this row names |
| R3 | signing in normally looks no different than before | [manual] sign in and look |

R1 survives whatever design you pick. "Put the retry bound in `http-client`"
would not — that is a decision, and it belongs to whoever builds it. Telling
those two apart is most of what `/hq:plan` is for.

(The format itself is defined in `plugin/commands/plan.md`; the three rows here
are only an illustration.)

## What a cycle looks like

```
/hq:loop add a retry to the login path
```

| step | what it does |
|---|---|
| `/hq:plan` | Settles with you what has to be true when this is done, and how anyone would confirm it. Surveys what the change touches. **It does not decide how to build it.** |
| `/hq:implement` | Picks up the repo's current style from recent history, designs, writes its work items, then builds them one commit at a time. |
| `/hq:review` | A separate agent reads the diff, tries to break the claims the change makes, and traces each required outcome to real code. |
| `/hq:triage` | Sorts the findings: fix now, defer with what is blocking it, or reject with a reason. |
| `/hq:pr` | Runs the build, types, linter and tests, then opens the pull request. |
| `/hq:archive` | After the merge: records what an outside reviewer caught, then cleans up. Deliberately outside the loop. |

`/hq:loop` runs these in order and only stops where a person has to decide.
Each command also works on its own.

There is one more, outside the cycle: `/hq:xcodebuild-config` works out with
you how an Xcode project builds and runs, and writes it down so the rest of the
cycle uses the same commands.

## Install

```
/plugin marketplace add tom-e-kid/hq
/plugin install hq@tom-e-kid
```

Then, in a repository you want to work in:

```
mkdir -p .hq && printf '{"base_branch": "main"}\n' > .hq/settings.json
```

That is the only file it needs. Add `.hq/knowledge.md` if you want — whatever
you put there is handed to every agent the plugin starts, which is a good place
for the things your docs never say out loud.

Plans, findings and reports are kept in `~/.hq`, outside your repo, so none of
it shows up in your diff.

## How it works

**Things that can be checked, are.** A plan's shape is checked as it is
written. An agent will not start without the repo's context in its prompt. The
set of files a change may touch is compared against the diff after every
commit. These are hooks and scripts rather than instructions — an instruction
is something an agent can talk itself out of.

**Things that cannot be checked, are not pretended to be.** Whether the change
is any *good* is a judgment. So a separate agent goes looking for ways the
change is wrong and reports only what it could actually show. And what an
outside reviewer catches after the merge gets recorded — that record, not any
test in here, is what says whether the checking is working.

`docs/design.md` carries a table, per module, of exactly what nothing
guarantees. It is the most useful page in the repo if you are deciding how much
to trust a given step.

## Layout

| path | what it is |
|---|---|
| `.claude-plugin/` | the plugin manifest and the marketplace entry |
| `plugin/commands/` | the steps, one file each |
| `plugin/agents/` | two agents: the builder and the verifier |
| `plugin/hooks/` | the gates that intercept tool calls |
| `plugin/scripts/` | the deterministic parts, each with a test beside it |
| `docs/design.md` | the design canon, including what is not guaranteed |
| `docs/postmortems.md` | bugs this project actually shipped, with the numbers |
| `.claude/scripts/` | this repo's own gate — not part of the plugin |

## Contributing

There is no CI; `bash .claude/scripts/check.sh` is the whole gate. Conventions,
branch model and the commit-time checks are in [AGENTS.md](AGENTS.md) — worth
reading before a first pull request, because a couple of those checks refuse
commits rather than warn.

## Status

Early, and the version says so. It runs end to end and gets daily use, but
interfaces still move. The design record is more candid about the gaps than a
release note would be, so start there.

## License

MIT. See [LICENSE](LICENSE).
