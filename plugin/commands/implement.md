---
name: implement
description: Build what this branch's plan says to build, then check the diff against what the plan declared
argument-hint: "[the directives file /hq:triage wrote, or one directive — omit to work the plan]"
allowed-tools: Bash(bash:*), Bash(git:*), Read, Agent, TaskCreate, TaskUpdate
---

# IMPLEMENT — build the plan, inside the fence it declared

You are the caller. The building is done by the `implementer` agent, and you do
not do it yourself: what you hold is the launch, the record, and the one
question the builder cannot answer about its own work — did the diff stay inside
what the plan declared.

## Context

- Branch: !`git branch --show-current 2>/dev/null || echo "(detached)"`
- Base: !`bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/lib.sh" hq_resolve_base 2>/dev/null || echo "(unresolved)"`
- Plan for this branch: !`bash -c 'd=$(bash "$1/plugin/scripts/lib.sh" hq_task_dir 2>/dev/null) || { echo unknown; exit 0; }; [ -f "$d/plan.md" ] && echo "$d/plan.md" || echo none' _ "${CLAUDE_PLUGIN_ROOT}"`
- Directives for this branch: !`bash -c 'd=$(bash "$1/plugin/scripts/lib.sh" hq_task_dir 2>/dev/null) || { echo unknown; exit 0; }; l=none; for f in "$d/directives"/triage-*.md; do [ -e "$f" ] && l=$f; done; echo "$d/directives (latest: $l)"' _ "${CLAUDE_PLUGIN_ROOT}"`
- Profile: !`bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/lib.sh" hq_diff_profile "$(bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/lib.sh" hq_resolve_base 2>/dev/null)" 2>&1 || echo "unavailable"`

## What you were asked

**No arguments — route `fresh`.** The builder designs against the plan's
`## Requirements`, writes its work items into the plan's `## Plan`, and then
works them. **A plan with no `## Plan` section is the ordinary state of a
branch the plan module has just left** — it is not a reason to stop, and it is
not yours to write. On a relaunch the section is already there and the design
is already settled.

**Arguments (`$ARGUMENTS`) — route `micro`.** They are fix directives: apply
those and nothing else. **The argument is one of two things, and what decides
which is whether a file is there:**

- **a path with a file at it.** `/hq:triage` wrote that file — one per triage
  pass, in the directory § Context names. Read it whole. Every directive in it
  goes into **one** launch, in the file's order; the file states its own shape,
  and `commands/triage.md` is where that shape is defined.
- **anything else.** The text is itself one directive, from a person who read a
  review and decided what `/hq:triage` would have.

**A single token with a `/` in it and no file at the end of it is neither.**
Stop and say the path is not there — a directives file that was written and
then removed, a stale path from an earlier branch, a typo. Handing it to the
builder as though it were prose launches a pass whose whole instruction is a
file name.

**No plan for this branch** — the § Context line says `none`. Stop and say so;
run `/hq:plan` first. Do not compose one here and do not let the builder infer
one.

## Procedure

**1. Get the repository context.**

```bash
bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/inject.sh"
```

Its entire output — first line through the `sha256:` line — goes into the launch
prompt **verbatim**. Do not summarise it, quote parts of it, or reformat it. A
gate compares what you pasted against what those files say at launch time and
refuses the launch when they disagree. If the launch comes
back denied, run this again and replace the whole block; editing the old one to
match is the failure the gate exists to catch.

**2. Launch the builder.**

One `implementer` agent, through the Agent tool. Its prompt carries, in this
order:

- the base branch and the current branch
- the plan's path, from § Context
- the route — `fresh`, or `micro` with the directives spelled out one per line.
  Read from a file, that is every directive the file holds, in its order — the
  builder is never handed the path instead of them, and never a subset
- the injected block from step 1, verbatim

Nothing else. The builder's instructions are its own definition; do not restate
them.

**Run it in the foreground and wait.** The builder writes this working tree.
Anything you do here while it runs lands in the same diff it is committing.

**3. Record the pass.**

Take the profile again first. **The one in § Context is the profile of the diff
before the builder ran**, which for a branch whose first commit the pass just
made is `none`.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/lib.sh" hq_diff_profile "$(bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/lib.sh" hq_resolve_base)"
```

Route `fresh`:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/record.sh" module name=implement \
  duration_s=$(( <MS> / 1000 )) route=fresh profile=<PROFILE>
```

Route `micro`, which carries one value more:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/record.sh" module name=implement \
  duration_s=$(( <MS> / 1000 )) route=micro profile=<PROFILE> directives=<N>
```

Replace `<MS>` with the builder's own run time exactly as the Agent tool reports
it — the `duration_ms` figure that comes back with the agent, pasted unchanged.
`<PROFILE>` is what the command above just printed. `<N>` is **how many
directives this launch carried** — the count you spelled into the prompt, not
how many the builder came back having applied; the pass cost what it cost
whether or not every one of them landed. They are placeholders rather than
shell variables, and the command does not run until they are gone.

**That count is what makes the micro row divisible.** One pass applies every
directive of a triage round and runs the floor once, so its
`duration_s` is the cost of the round rather than of one fix, and the measure
that reads these rows has nothing to divide by without it. The recorder requires
the key on `route=micro` and refuses it on every other row — a micro row with no
count is refused rather than written, because a written one could not be told
from a row recorded before this count existed.

A relaunch is a second pass and records a second row. Do not add the two up
yourself.

**4. Ask the fence the question the builder could not.**

```bash
bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/plan-gate.sh" surface <plan> <base>
```

Both are the values § Context printed: the plan's full path, and the base.

**Both directions.** Undeclared paths are already reported by a gate after
every commit; the half that matters now is entries declared and never touched —
either the work is not finished, or the plan promised something the work did
not do. Both are the user's to decide. Report what it says; do not quietly edit
the plan to match the diff.

Under route `micro`, expect untouched entries: a fix pass touches part of a
branch's declared surface by construction. Say which they are and leave them.

**5. Report.**

- what the builder returned, verbatim in its own shape
- the surface result — clean, or the paths on each side
- what is left: items still unchecked, floor items that failed, directives
  not applied

Then stop. **You do not review the work** — `/hq:review` launches the verifier.
If items remain and the builder stopped
for reasons that a second pass would clear, relaunch from step 1; if it stopped
because the plan cannot be worked as written, that is the user's call.
