---
name: triage
description: Decide what happens to each of this branch's findings — fix it now, defer it with what blocks it, or reject it
allowed-tools: Bash(bash:*), Bash(git:*), Bash(date:*), Bash(mkdir:*), Read, Write, Grep, Glob, TaskCreate, TaskUpdate
---

# TRIAGE — decide what happens to each finding

`hq:review` stops at the findings; nothing acts on them until this step says
what each one is. **You are the party that decides.** There is no subagent
here — the judgement is yours, taken one finding at a time, and it leaves one
telemetry row per finding.

## Context

- Branch: !`bash -c 'b=$(git branch --show-current 2>/dev/null) || { echo "(not a repository)"; exit 0; }; [ -n "$b" ] && echo "$b" || echo "(detached HEAD)"'`
- Base: !`bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/lib.sh" hq_resolve_base 2>/dev/null || echo "(unresolved)"`
- Plan for this branch: !`bash -c 'd=$(bash "$1/plugin/scripts/lib.sh" hq_task_dir 2>/dev/null) || { echo unknown; exit 0; }; [ -f "$d/plan.md" ] && echo "$d/plan.md" || echo none' _ "${CLAUDE_PLUGIN_ROOT}"`
- Findings for this branch: !`bash -c 'd=$(bash "$1/plugin/scripts/lib.sh" hq_task_dir 2>/dev/null) || { echo unknown; exit 0; }; [ -f "$d/findings.jsonl" ] && echo "$d/findings.jsonl" || echo none' _ "${CLAUDE_PLUGIN_ROOT}"`
- Directives for this branch: !`bash -c 'd=$(bash "$1/plugin/scripts/lib.sh" hq_task_dir 2>/dev/null) || { echo unknown; exit 0; }; l=none; for f in "$d/directives"/triage-*.md; do [ -e "$f" ] && l=$f; done; echo "$d/directives (latest: $l)"' _ "${CLAUDE_PLUGIN_ROOT}"`
- Deferrals still open here: !`bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/triage-gate.sh" open 2>&1 || echo "(unavailable)"`

**No findings file** — the line says `none`. Three things produce that line and
they are not the same thing:

- **the verifier ran and found nothing.** An absent file and an empty one both
  read as "no findings" (`agents/reviewer.md`). There is nothing to judge —
  record the pass (step 7), say so, and stop.
- **the verifier has not run on this branch.** Run `/hq:review`.
- **it ran and was never told where to write.** Then findings exist somewhere
  this step cannot see.

**What separates the first from the rest is the run directory.** A review pass
leaves a report in `reports/` there whether or not it found anything, so a
report with no findings file beside it is the first case. Print the directory
with `bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/lib.sh" hq_task_dir` and
look. With no report either, say which of the remaining two you can rule out
and stop.

**A line says `unknown`** — the derivation itself failed: a detached HEAD, a
directory that is not a repository, no home to derive from. Say what the line
said and stop. `(unavailable)` on the deferrals line is the same thing one step
down: the gate could not look, which is not the same as it finding nothing
open.

**A line beginning `triage-gate.sh:` among the deferrals is a third state.** The
gate could look, and what it read was incomplete — lines of the telemetry that
are not readable as JSON, rows disposing of a finding they do not name. Treat
the list as partial, and say so in the report.

**The file exists and holds no rows** — the first case above; record the pass
(step 7), say so, and stop.

**The directives line is the directory step 4 writes into**, and `latest:` names
what an earlier pass on this branch left there — including a file a pass that
died left half-written. A new pass writes its own file beside that one and
never adds to it; `none` simply means this is the first pass here that had
anything to hand over.

**Open deferrals are listed because they are yours to close.** Each line is
`<branch>#<id>`, a timestamp and the reason that was given. If the work on this
branch has fixed one of them, close it in step 5 — nothing else will.

## What decides a disposition

Two predicates you evaluate, and one value you are handed.

- **consequence** — what the reported defect actually causes. Who it breaks, on
  which input, in what state. A finding that is true and causes nothing has no
  consequence.
- **the fence** — whether the file the fix would touch is in the
  `## Editable surface` of the plan named above.
- **the weight** — `high`, `medium` or `low`, written by the verifier in the
  finding itself. It answers one question: can the change ship with this still
  in it. **You do not set it and you do not change it.** If you think it is
  wrong, say so in the report and dispose of the finding on the weight as
  written.

|  | inside the fence | outside it |
|---|---|---|
| **consequence, `high` or `medium`** | `fix_now` | `defer` |
| **consequence, `low`** | `fix_now` when anything else is being fixed, `defer` when nothing is | `defer` |
| **no consequence** | `reject` | `reject` |

**"Too big for now" is not in the table.** Inside the fence, with a consequence
and a weight above `low`, the only exit is fixing it.

**Anything that costs a line is fixed whatever its weight.** A typo, a stale
number, a wrong path in a comment. Do not compose a deferral for a one-line
edit.

**Before rejecting, run one thing that could prove you wrong.** Take the input
the finding names and follow it — run the command, call the function, grep the
caller list. Then reject on what you saw. Pick the check that would fail
loudest if the finding were right.

**No plan for this branch** — the § Context line says `none`. Then `defer` is
unavailable and every finding with a consequence is `fix_now`. Do not compose a
plan here to get the third column back. The same absence reaches the step-3
search: with no fence to sort its hits, the directive lists every site the
search found.

## Procedure

**1. Take the start time.**

```bash
date +%s
```

Keep the number. Step 7 subtracts it; the shell does the arithmetic, not you.

**2. Read the findings.**

Read the file named in § Context, whole, before judging any of it. One JSON
object per line, carrying `id`, `weight`, `file`, `claim`, `evidence`,
`consequence` and sometimes `class` — the shape is `findings-gate.sh`'s to
enforce and it has already run on the write.

**The file may hold more than one review pass.** A later pass appends under new
numbers rather than starting again at `F1`, so ids you have already disposed of
are still there. Do not re-judge an id that has a row, and do not record a
second one for it; the gate in step 6 names exactly the ones that lack rows.

Read the plan's `## Editable surface` as well, now rather than per finding.

**3. Judge each finding, in the file's order.**

Take them one at a time and say, per finding: its weight as written, what the
consequence is or why there is none, which side of the fence the fix falls on,
and the verdict that follows. The order is the file's.

**The `low` findings inside the fence are settled last**: they are `fix_now` if
anything else came out `fix_now`, `defer` if nothing did. Judge them with the
rest, in order, and leave that one choice open until you have been through the
file. A one-line fix does not wait for that — it is `fix_now` either way.

**Your own work is not evidence here.** If a finding is about something this
branch changed, the argument that it is fine is the same argument that put it
there. Run something.

**When the verdict lands as `fix_now`, search once for the second instance —
before that finding's row is written.** A defect worth fixing often has a
shape — a pasted phrase, a rule stated in two places, a derivation repeated
where its result is used. Take the shape the finding describes and run one
search for it — a `git grep` for the pasted wording, for the pattern, for the
repeated expression.

What the search turns up **inside the fence is kept for step 4** — the
directive that carries this finding's fix will name every one of those sites.
An instance **outside the fence stays out of the directive** — name it in the
report, and put it in the `reason` of the row you are about to record.

**Then ask the other question about the same fix: does it move something
another finding is standing on?** The search above asks whether this defect
appears twice. This one asks whether the fix changes a premise some other
finding was judged against — an **invariant**, a property something else
relies on holding everywhere, so that it never checks. Name the invariant this
fix touches, then go back over the findings and say which of them, if any,
rest on the same one. They were all read in step 2, so this is a comparison,
not a second pass over the file.

**A coupling is claimed the way a rejection is — by running one thing.** Take
what the fix would change and follow it to the other finding's site: run the
command whose output moves, read the line that consumes it, grep for what
would have to be updated with it. Say what you ran and what it showed. Where
you cannot show it, the two are independent and stay apart.

**Where it holds, both fixes go into one directive** — step 4, written in the
order they have to be applied: the one that moves the invariant, then the one
that has to move with it. Composed as two directives, the first is built by
someone who does not know the second exists.

**A defect nobody has reported is not a candidate here.** This asks only about
couplings between findings already in the file. A defect the fix might create
that no verifier raised is an assertion with nothing under it, and it would
enter the directive without the one thing this step demands of every other
judgement it makes.

**4. Write the fix directives.**

Write out the `fix_now` findings as fix directives. A directive is one per
shape, not one per finding; each directive names every in-fence site the step-3
search found — every site the fix has to reach, and what has to change at each.

**They go in a file, not only in your report.** A directive that exists solely
in what you hand back is lost the moment the pass that was to apply it dies,
and nothing recreates it: step 2 does not re-judge an id that already has a
disposition row, and `triage-gate.sh check` reads that branch as clean.

**The file is written before the rows of step 5, and that order is what makes
writing it worth anything.** Record the dispositions first and the window above
opens one stage earlier instead of closing: a pass that dies between the two
has disposed of every finding and left no directive, and that is exactly the
state no rerun of this module recovers. Written first, a pass that dies here
has no rows at all — the gate in step 6 names those findings as undisposed and
a rerun judges them again from step 3. Nothing in this step needs the rows: a
directive is composed out of the step-3 verdicts alone.

**`directives/triage-<YYYY-MM-DD-HHMM>.md`, under this branch's run
directory** — the path § Context printed. Take the timestamp from:

```bash
date +%Y-%m-%d-%H%M
```

Never invent one. **One file per triage pass**, the same shape the verifier's
reports take: a later pass writes its own file rather than appending here, so
"the directives of this pass" is answered by the file name and nothing has to
work it out by reading.

**Make the directory before the write, if it is not already there.**

```bash
mkdir -p "$(bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/lib.sh" hq_task_dir)/directives"
```

Nothing else in the plugin creates it — `hq_task_dir` derives the run directory
and stops at it. Whatever writes the file for you may well create the parent on
its own; `reports/` is the same shape and no `mkdir` anywhere stands behind it.
This line is the plugin holding that for itself rather than borrowing it.

**A file that a pass which died left half-written stays where it is.** This
pass writes its own file under its own timestamp and hands back that path;
nothing here reads, amends or overwrites the older one.

The file holds a `## ` heading per directive, numbered from 1, and under each
the directive itself. Nothing else goes in it — no dispositions, no findings
that were not `fix_now`, no commentary for the reader of your report.

**When two findings are the same shape, they share one directive.** Before
composing a finding's directive, look at the ones already written this pass: if
every in-fence site this fix has to reach is already carried there, write no
new directive, and say in the report which directive covers this finding. Step
5 is untouched by this — still one disposition row per finding.

**Findings step 3 found coupled through an invariant share one directive too**,
and for the other reason: not that one fix already covers both sites, but that
either fix composed alone is composed against a premise the other one moves.
Both fixes are written into that directive, in the order step 3 put them.

**Removing is the first form to consider, not the last.** The finding that says
a rule is not enforced anywhere is answered by deleting the rule at least as
often as by writing a mechanism for it. Ask what the target is holding up
before asking how to word it better. Where the fix really is an addition, say
what it replaces or why nothing can be taken away instead.

**Nothing came out `fix_now`** — write no file. An empty directives file is a
pass the caller would launch to do nothing. Say in the report that there is
nothing to hand over.

**The caller runs it; you do not.** One call, carrying the path of the file you
just wrote:

```
/hq:implement <the path of the directives file>
```

That entry is route `micro`: the builder applies what the directives in that
file name and nothing else. The caller makes the call — a person when this
module was invoked by hand, `hq:loop` when it was called from there.

**Not `defer`, and not `reject`.** A deferral is recorded and left; a rejection
is recorded and answered where the finding was raised. Neither becomes a
directive.

**5. Record one row per finding.**

```bash
bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/record.sh" disposition \
  finding='<ID>' verdict='<VERDICT>' source=review class='<CLASS>' reason='<WHY>'
```

All four are placeholders rather than shell variables, and the command does not
run until they are gone. `<ID>` is the finding's own `id`; `<VERDICT>` is
`fix_now`, `defer` or `reject`; drop `class=` entirely when the finding carries
no class. `source` is `review` because these findings are the verifier's.

**`reason` is required on `defer` and the recorder refuses the row without it.**
What earns the row is not "outside the fence" — the fence is already in the
verdict — but **the constraint that will bite whoever picks it up**: what has to
exist first, which files it will have to reach, what the fix collides with.

On a `low` deferred for want of anything to ride on, the constraint is the ride
itself: say what the fix is, in one line.

**Closing a deferral is the same command with a qualified identifier.** When the
work here has settled one of the deferrals listed in § Context, record it as:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/record.sh" disposition \
  finding='<BRANCH>#<ID>' verdict=fix_now source=review
```

`<BRANCH>#<ID>` is the identifier exactly as § Context printed it. Finding ids
are only unique within a branch — every branch has an F1 — so a bare id recorded
here would close this branch's F1 instead. `triage-gate.sh open` reads the
qualified form back and stops listing it; **nothing else closes a deferral, and
nothing checks that you did**.

**6. Check that nothing was missed.**

```bash
bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/triage-gate.sh" check
```

It differences this branch's findings against the rows step 5 wrote and names
any finding that has no disposition. **Exit 1 with a list means going back to
step 3 for exactly those — not to step 5.**

**A finding can lack a row because this pass never judged it**, and unjudged it
has no directive either. Write only its row and the gate closes over a fix that
exists nowhere: the row says `fix_now`, no file names it, and a rerun does not
restore it — step 2 does not re-judge an id that has a row, and the gate reads
the branch as clean. The caller then launches `/hq:implement` on the file step 4
wrote, that fix never happens, and **nothing on this machine holds the two lists
against each other**: no script joins `fix_now` rows to directives.

So, per finding the gate names: judge it as step 3 asks, and where the verdict
is `fix_now`, compose its directive and write it **before** the row — the order
step 4 gives, for the reason step 4 gives. It is **appended to the file this
pass already wrote**, under the next number; when nothing came out `fix_now`
earlier and there is no such file, it becomes this pass's file. **Never a second
file under a fresh timestamp** — one file per pass is what lets the file name
answer "the directives of this pass", and that one path is what the single
`/hq:implement` call of step 4 carries. Then the row, then the gate again.

**No count will tell you this was done.** A directive is one per shape, so a
pass with four `fix_now` findings and two directives is a normal pass — fewer
directives than `fix_now` rows is not a discrepancy, and comparing the two
numbers detects nothing.

**Exit 2 is not a pass.** It means the gate could not look — no JSON parser, no
branch, no run directory. Report what it said and treat the disposition list as
unverified.

**7. Record the pass.**

```bash
bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/record.sh" module name=triage \
  duration_s=$(( $(date +%s) - <START> ))
```

Replace `<START>` with the number from step 1 — it is a placeholder, not a shell
variable, and the command does not run until you have.

**8. Report.**

- each finding, its weight as written, its verdict, and the one sentence the
  verdict rested on
- **whether anything `high` or `medium` is unresolved** — that is the answer to
  "can this ship", and it is the line the user is reading for
- what the gate in step 6 said
- the deferrals you closed, and the ones still open
- **the path of the directives file and how many directives are in it**, with
  the one `/hq:implement` call the caller runs — or that nothing came out
  `fix_now` and there is no file
- any weight you would have written differently, said as a disagreement rather
  than acted on

**Layer 2 does not reach this module** — it launches no subagent, so nothing
injects the repository's own notes. Read `.hq/knowledge.md` if this repository
has one.
