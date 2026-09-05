---
name: archive
description: After the merge — record what the outside reviewer found for every shipped pull request, then remove the merged branch's run directory and its local branch
allowed-tools: Bash(bash:*), Bash(git:*), Bash(date:*), Read, Grep, Glob, TaskCreate, TaskUpdate
---

# ARCHIVE — record the residual, then close the run

Pillar B is a per-pull-request measure: every merged pull request gets a
residual record — what an outside reviewer found in it, or that no outside
reviewer looked. Nothing else writes these rows. **You are the party that
writes.** There is no subagent here — the facts come from the user, one pull
request at a time.

This module runs after the merge, outside the loop, and does two things in a
fixed order: record first, remove second.

## Context

- Branch: !`git branch --show-current 2>/dev/null || echo "(detached)"`
- Base: !`bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/lib.sh" hq_resolve_base 2>/dev/null || echo "(unresolved)"`
- Merged pull requests with no residual record: !`bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/archive.sh" missing 2>&1 || echo "(unavailable)"`

**Each line of the list is `<number><TAB><branch>`** — the pull request the
telemetry holds no residual row for, newest first, and the branch its merge
subject names (a derivation for step 4; for a pull request from a fork it may
name a branch this clone does not have). The list walks the base's whole
merge history and caps itself at 20 lines; the cap bounds what is printed,
not how far back it looks, so a backlog deeper than one list surfaces on the
next run.

**An empty list means nothing is owed.** There is still work here: step 4, for
any merged branch whose run directory or local branch is still around.

**`(unavailable)` is not an empty list.** The script could not look — no
repository, a detached HEAD, a base that does not resolve, no JSON parser.
Say what the line said and stop.

**A line beginning `archive.sh:` beside the list is a third state.** The
stream was read, and part of it could not be — lines that are not JSON, rows
that name no pull request. Treat the list as partial and say so in the report.

## Procedure

**1. Take the start time.**

```bash
date +%s
```

Keep the number. Step 3 subtracts it; the shell does the arithmetic, not you.

**2. Record one row per reviewer per pull request.**

For each pull request in § Context: settle with the user which outside
reviewer looked at it and what came of that — the user is the one who
launched it, or the one who knows nobody did. Then record:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/record.sh" residual \
  pr='<PR>' reviewer='<REVIEWER>' state='<STATE>' finding='<CLASS>:<CATEGORY>'
```

All of these are placeholders rather than shell variables, and the command
does not run until they are gone. `<PR>` is the number from the list.
`<REVIEWER>` names the reviewer as earlier rows named it (`ext-review`, a
person's handle) — one row per reviewer, so a pull request two parties looked
at gets two rows. `<STATE>` is `reviewed` or `not_reviewed`.

**A pull request nobody outside reviewed is still recorded** — state
`not_reviewed`, and drop `finding=` entirely (the recorder refuses findings
on that state).

`finding='<CLASS>:<CATEGORY>'` repeats once per finding the reviewer made,
and is dropped when there were none. The accepted values are
`record.sh --help`'s to state, not this page's, and they do not all answer the
same question. Most of them answer one — had the loop already detected this
before the pull request was opened, and if so, where did it stop.
`false_positive` answers a different one: the finding was not true at all. A
finding the user says the reviewer got wrong belongs there and nowhere else,
since every other category takes the finding as real and answers only the
question above.

**3. Record the pass.**

```bash
bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/record.sh" module name=archive \
  duration_s=$(( $(date +%s) - <START> ))
```

Replace `<START>` with the number from step 1 — it is a placeholder, not a
shell variable, and the command does not run until you have.

This row goes in BEFORE the removal: the recorder derives the current
branch's run identifier, and written after a cleanup that just removed this
very branch's directory, it would mint a fresh identifier into the directory
the removal ended, and the run would never close.

**4. Close out the merged branches.**

```bash
bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/archive.sh" cleanup '<BRANCH>'
```

Once per merged branch: the second column of the § Context list, and any
other merged branch the user names as shipped and already recorded.

**That one call removes two things, and it reports each on its own line**: the
branch's run directory, and the local branch itself. Either can be there
without the other — a branch whose local ref the merge already took still has
a directory, and a directory cleared by an earlier run still leaves the
branch — so neither absence is an error and neither stands in for the other.
**The remote branch is never touched.** **Both removals are irreversible, and
the directory's ends the branch's run identifier** — the next work on a branch
of that name starts a new cycle with a fresh id.

**It may move this shell to the base branch**, and says so when it does: a
branch cannot be deleted while it is the one checked out. That happens before
either removal, so a run that could not move has removed nothing.

**Exit 1 is a refusal**, and the script names the condition it hit on stderr.
Which conditions those are is the script's to state — this page does not list
them, because a list here has no way to be compared against the script's and
goes quietly stale when a path is added. Read the reason it gave.

**Every refusal but one comes before anything is removed.** The exception:
when git will not delete the local branch — another worktree of this
repository has it checked out, most often — the run directory has already
gone, and the call still exits 1. Its stdout names what was removed.

**A refusal is an answer.** Report it with the reason the script gave; do not
delete by hand what it refused. For that last one, report the removal too — a
report that says nothing was removed would be false there. Running the same
call again retries the branch on its own.

**A branch this face has fully cleaned in a clone that has no remote ref for
it stops resolving**, so a second call on it is refused — nothing left to
prove merged — rather than reported as nothing to do. That is an answer, not
a fault to work around.

**5. Report.**

- per pull request: the rows written — reviewer, state, how many findings
- what step 4 removed — directories and local branches, each named — every
  refusal with the script's own reason, and whether this shell was moved to
  the base
- whether the § Context list was partial (the `archive.sh:` lines)
- what is left: pull requests the user could not answer for, directories
  that stay

**Layer 2 does not reach this module** — it launches no subagent, so nothing
injects the repository's own notes. Read `.hq/knowledge.md` if this repository
has one.
