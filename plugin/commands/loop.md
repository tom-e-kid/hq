---
name: loop
description: Run this branch's cycle end to end — plan, build, verify, triage, fix, open the pull request — calling one module at a time
argument-hint: "[what the work is — omit when this branch already has a plan]"
allowed-tools: Bash(bash:*), Bash(git:*), Bash(gh:*), Bash(date:*), Read, Grep, Glob, Write, Edit, Agent, Skill, TaskCreate, TaskUpdate
---

# LOOP — call the modules in turn, and stop only where a person decides

Every module this page names runs on its own, and this page adds nothing to
what any of them does. What it holds is three things: which module is next,
whether to go round again, and where a person is still in the run.

**You call modules through the Skill tool and you do not do their work.** Do
not review a diff here, do not judge a finding here, do not compose a pull
request body here. Whatever a module reports, it reported — you carry it, you
do not restate it as your own conclusion or argue with it.

The tool list above is wider than this page's own steps, because every module
called from here runs its tool calls in this session.

**The cycle ends when the pull request is open.** What comes after a merge —
taking in an outside reviewer's comments, recording what they found, removing
the run's working directory — is not this page's, and the one module of it that
exists, `hq:archive`, is not called from here. The outside reviewer has to be
one this cycle cannot start, or what that reviewer finds stops being a
measurement of it.

## Context

- Entry state: !`bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/loop-state.sh"`

**That is one command and its whole answer.** The observations a run is entered
on, and the module they derive, are `loop-state.sh`'s; the mapping from the one
to the other is stated in that script's header and nowhere else. Do not restate
it here, and do not work any of these values out by hand. The one place they
are taken again is step 2, and only because the module there can have moved
you onto a different branch.

**Everything above is read off this machine.** No line asks a forge whether a
pull request exists: the module that opens one checks that for itself, and a
network answer would make the entry of a run depend on something that can be
down.

**`entry=unknown`** — the derivation itself failed, and the `why=` line of that
same output says what could not be read. Say what that line said and stop. There is nothing
to enter at, and entering somewhere anyway is worse than not starting. Do not
work the cause out from the `unknown`s themselves: they are what the run could
not read, not why, and there are stops where every one of them is `unknown`.

## What you were asked

**Arguments (`$ARGUMENTS`)** — that text is what the work is, and it is handed
to `hq:plan` in step 2 unchanged. Nothing here reads it for any other purpose:
which module runs next is decided by the state below, never by what the request
says.

**No arguments** — this branch is expected to have a plan already, or the
request is in the conversation this command was invoked from. Either way
`hq:plan` is the module that settles it, and it stops on its own when neither
holds.

## Where this run enters

**`entry=` in § Context names the module, and this page enters there.** The
derivation behind it — which observations decide it, and why each one is the
one that decides — belongs to `loop-state.sh` and is written in its header. It
is a pure function of what that script read off this machine, and it is not
this page's to reproduce, second-guess or adjust for what the request says.

**A module called too early costs a pass that finds its work already done; one
called too late skips work nobody will come back for.** That is what the
derivation is buying, and it is the reason to follow it rather than to start
wherever the conversation seems to be.

**This same derivation is how a stopped run is resumed: invoke this command
again.** Nothing is carried from one invocation to the next except what the
modules left on this machine — the plan, the findings file, the reports, the
telemetry rows. There is no resume token to lose and none to clean up.

**The branch can change under a run that entered at `hq:plan`.** That module
creates the branch when the one you are on is the base, and every line in
§ Context was derived from the branch as it was at invocation. So after step 2
returns, take the branch and the plan's path again before going on; a run that
carries the base's task directory into step 3 hands the builder the wrong plan,
or none.

## Where a person is in this run

Three kinds of stop, and no others. Everything else this page decides, it
decides without asking.

- **the plan gate** — `hq:plan` holds it and it is not skippable.
- **the consultation** — below.
- **the final report** — step 8.

**A consultation is any point where what to do next is not this page's to
pick.** That test is the whole of it. Each place one arises is stated at the
step it arises at, and this page keeps no second list of those places and no
count of them: a copy goes stale the day a step gains a condition, and nothing
compares the two.

**One of them belongs to no single step, so it is stated here — a module
reported something its own definition calls the user's to decide.** Each module
says, in its own definition, which of its outcomes it does not settle. Those
definitions are where that list lives; do not carry a copy of it here, and do
not answer one of them yourself because it looks small. An outcome the
definition tells that module to report and carry on from is not a consultation,
however large it reads.

**This is what happens to a report about the plan itself.** When the builder
comes back saying the plan is wrong — a claim in it is false, a number in it
does not match the tree — it goes to the user with what the builder said,
verbatim.

**Take a consultation to the user with three things**: what the module
reported, where the run is, and what the options are. Then wait.

**An answer resolves into one of two things.** The run continues from the step
the consultation interrupted, carrying what the user decided into the next
module's call — or it ends there and you go to step 8 with the run unfinished
and said to be unfinished. An answer is not licence to skip a module.

## Procedure

**1. Read the entry state.**

It is already above, in § Context: `entry=` names the module this run starts
at, and the steps below are that module and the ones after it. Go to the step
that module is, and run nothing here to confirm it — the observations were read
once, at invocation, and reading them a second time would only mean acting on
whichever of the two answers came back second.

`entry=unknown` stops the run here, as § Context says. Report what the other
lines said and go to step 8.

**2. `hq:plan`.**

Call it with what § What you were asked settled: the `$ARGUMENTS` text when
there was one, and nothing when there was not.

The gate inside it is a conversation with the user, and its answers are its
own: `go` continues to step 3, `stop` ends the run here with the plan written.
Report which one came back.

On `go`, take the branch and the run's directory again before step 3 — this is
the module that can have moved you onto a new branch:

```bash
git branch --show-current
bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/lib.sh" hq_task_dir
```

The plan is `plan.md` inside what the second command printed. Everything from
here on uses these two values, not the ones § Context printed.

**3. `hq:implement`.**

No arguments — route `fresh`. **The builder designs first** — the plan says
what must be true, not how to build it — writes its work items into the plan,
and then works them. A plan with no items yet is the state `hq:plan` leaves
behind, not a failure.

**This is the step where the design gets decided, and no person is in it.**
The plan gate held the user's approval of the outcomes and of the boundary;
it did not approve a shape, because there was none to approve. The shape
reaches the user afterwards — in what the builder returns, and through the
pull request body. Pillar A verifies it in between. Do not read step 7's "the
approval is already held" as covering the design.

Read what it returns before deciding anything: it ends with what is left over,
and a leftover that its own definition calls the user's is a consultation.

**4. `hq:review`.**

No arguments. It launches the verifier and reports what came back.

**An empty diff is an answer, not a round.** When it comes back saying this
branch has no changes against its base, there is nothing to verify and nothing
to offer — that is a consultation, not a walk on to step 7.

**5. `hq:triage`.**

No arguments. It judges every finding that has no disposition yet and writes
out fix directives for the `fix_now` ones.

**Its verdicts are not yours to revisit.** A finding you would have judged
differently is a thing to say in step 8, not to act on.

**6. The fix round.**

Call `hq:implement` once, passing the path of the directives file triage
reported — route `micro`. One call for the whole file, because that is the
handover the triage module's own definition writes: every directive of the
round in one file, applied by one pass of the builder over this tree.

**Triage said nothing came out `fix_now`** — there is no file and no call to
make. Go on to the round question below.

**Then decide whether another verification round is earned.** That rule belongs
to the review module and is stated at the end of `plugin/commands/review.md`;
read it there and apply it. Do not decide it from a summary of it, and do not
restate it on this page.

- **Another round is earned** — go back to step 4, after the count below.
- **It is not** — go to step 7.

**Three verification rounds have finished and triage still produces `fix_now`
— that is a consultation, and it comes before the return to step 4.** Count the
rounds this session ran plus the `reports=` count § Context printed. What this
catches is a cycle
that is generating work as fast as it closes it, which is a thing to decide
about rather than to keep paying for.

**Three is a placeholder.** It was picked with no measurement behind it.
Replace it once enough runs are on record to pick a number with a reason.

**7. `hq:pr`.**

**Reached from step 6, when no further verification round is earned.**

**Then check what is outstanding, because that is a separate condition.** A
`high` or `medium` finding whose fix would fall outside the fence is disposed
of as `defer`, so a round can end with no directive left to run and something
on record that still stops the change shipping. That state is neither step 6
nor this one — it is the consultation, and widening the fence is among the
answers the user has.

**Call it without asking.** The user's approval of *this work* is already held
by the plan gate — the outcomes it has to reach and the boundary it may touch
— and the conditions for offering the branch are held by the gate inside this
module. A question here would put a person back at the end of the run, which
is the wait this whole page exists to remove. **What that approval does not
cover is the design**, which was settled at step 3; the body this module
composes is where it reaches the user, so do not let it go out without one.

**A refusal from that gate is not the end of the run by itself.** It names
conditions, and two of them are answered by another `hq:implement` round from
step 3 rather than by the consultation:

- **unchecked plan items** — the work is not finished.
- **no `## Plan` section at all** — the builder never reached the point of
  writing its items, so nothing was built. This looks like a plan-shaped
  problem and is not one; sending it to the consultation asks a person to
  answer a question only another build round can.

Anything else it names goes to the consultation.

**8. Report.**

- the modules that ran, in order, and how many verification rounds there were
- **each module's `duration_s` as that module recorded it** — the value it
  passed to its own `record.sh module` call in this session. Do not take a
  clock of your own and do not add the values up into a run total that claims
  to be the run's elapsed time; see below for what is missing from that sum
- the pull request's URL, or the step the run stopped at and why
- everything the modules reported as the user's to decide, including anything
  they said they could not check
- the material `hq:pr` said did not fit the body's format

## What this step does not measure, and does not guarantee

**It writes no telemetry row.** Every module records its own pass, and the
boundary of a measurement is the boundary of a module. Adding a row for this
page would measure the plan gate's conversation and the consultations — waits
with a person on the other end, unbounded above.

**So the seam is unmeasured**: this page's own derivation, reading and
reporting are in no row and are estimated nowhere.

**Nothing checks that the modules ran, that they ran in this order, or that
stopping was the right call.** Each module's own gates hold whatever that
module guarantees, and they hold it the same whether it was called from here or
by hand. What is not held anywhere is this page being followed.

**Layer 2 does not reach this module** — it launches no subagent of its own, so
nothing injects the repository's own notes. Read `.hq/knowledge.md` if this
repository has one.
