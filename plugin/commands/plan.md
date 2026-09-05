---
name: plan
description: Settle what the change must satisfy, survey what it reaches, and write the plan the branch will be built and judged against
argument-hint: "[what to plan — omit to take it from this conversation]"
allowed-tools: Bash(bash:*), Bash(git:*), Bash(gh:*), Bash(date:*), Bash(mkdir:*), Read, Grep, Glob, Write, Edit, AskUserQuestion, TaskCreate, TaskUpdate
---

# PLAN — decide what must be true, not how to build it

The plan settles three things and stops: **what must be satisfied**, **what the
survey found that the work has to reckon with**, and **how anyone will know it
was satisfied**. How to build it — the design, the work items, the tests — is
the builder's, and this module does not decide it.

## Context

- Branch: !`git branch --show-current 2>/dev/null || echo "(detached)"`
- Base: !`bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/lib.sh" hq_resolve_base 2>/dev/null || echo "(unresolved)"`
- Existing plan for this branch: !`bash -c 'd=$(bash "$1/plugin/scripts/lib.sh" hq_task_dir 2>/dev/null) || { echo unknown; exit 0; }; [ -f "$d/plan.md" ] && echo "$d/plan.md" || echo none' _ "${CLAUDE_PLUGIN_ROOT}"`
- Xcode build configuration: !`bash -c 'r=$(git rev-parse --show-toplevel 2>/dev/null) || { echo none; exit 0; }; [ -f "$r/.hq/xcodebuild-config.md" ] && cat "$r/.hq/xcodebuild-config.md" || echo none'`

An existing plan means this branch already has one: read it and continue that
work rather than starting a second.

**The Xcode line printed a file** — this repository builds with `xcodebuild`,
and its Build Command is settled. `## Floor` lifts that command verbatim,
destination and all; a destination you chose is a second statement of the one
the user settled. **It says `none` and the survey turns up an `.xcworkspace` or
`.xcodeproj`** — the configuration was never made. Raise that at step 4 —
`/hq:xcodebuild-config` settles it with the user — rather than composing a
build command of your own.

## What you were asked

The § Context above says where the work would go. What the work *is* comes from
one of three places, and which one applies is settled before anything else
happens.

**Arguments were given** (`$ARGUMENTS`) — that text is the request. A reference
in it counts as part of the request: an issue number, a branch name, a path.
Read what it points at before going on.

**Arguments were given but could mean two different pieces of work** — a bare
noun, a file name with no verb, a sentence that reads as either of two changes.
**Ask, and wait.** Do not resolve it by picking the more likely one.

**No arguments** — the request is in the conversation this command was invoked
from. Read back over it, and open step 3 by stating in one sentence what you
take the work to be. If nothing in the session names a piece of work, say so
and stop.

## Procedure

**1. Take the start time.**

```bash
date +%s
```

Keep the number. Step 8 subtracts it; the shell does the arithmetic, not you.

**2. Read the repository context.**

```bash
bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/inject.sh"
```

Its output is this repository's own notes to whoever works here; read it whole
before going on. No machine checks that you did — layer 2 guarantees injection
only at a subagent launch, and this module launches none because its gate in
step 6 is a conversation with the user.

**3. Settle what must be true when this is done — with the user, before
surveying.**

Turn the request into a short list of outcomes, and agree it. Each one is a
statement about the world after the change, in this repository's own words.

**A requirement survives a change of design.** That is the test, and it is the
only one that matters here:

- "the token is renewed before it expires, with no manual step" — survives any
  design. A requirement.
- "put the renewal decision in the token store" — is rewritten the moment the
  design puts it somewhere else. Not a requirement; not yours to decide.

**The tell is a step.** A requirement says what is true of the world; the
moment a sentence names something the code *does* — measures, compares, reads,
writes, in what order — it is a design, however outcome-shaped the rest of the
line looks. "the boundary is measured against the usual range and stops when it
falls outside" is a mechanism wearing an outcome's clothes; "a discontinuous
boundary never completes without a person deciding" is the outcome under it.

Use `AskUserQuestion` where two readings of the request would lead to different
outcomes. **Surveying before this is settled surveys for the wrong thing** —
what the change reaches depends on what it has to achieve.

Three failures to press on:

- **A requirement nobody can confirm.** If you cannot say how anyone would know
  it holds, it is a wish. Settle the confirmation here, beside it — the two are
  written on one row for that reason.
- **A work item wearing a requirement's clothes.** Apply the two tests above to
  every line.
- **An assumption stated as a given.** The request usually carries some — "this
  one will be like the last one", "nothing else uses it", "the format has not
  changed". **Sort them by whether a command could settle them**, and put the
  ones that could into the survey as things to measure. An assumption the
  survey later falsifies sends the whole agreement back here, which is the
  expensive way to find out.

**4. Survey what the change reaches.**

Read outward from the agreed outcomes until the signal runs out — what follows
is where signal usually is, not a checklist to fill.

- **The constraints.** What in this repository, or outside it, stops the
  straightforward shape from working? These change the design more than
  anything else on this list, and the builder cannot find them by reading the
  files it edits.
- **The single sources.** Which document, schema, or neighbouring definition
  already states a fact this change would state again? Those are where `drift`
  lands.
- **The callers and the consumers.** Grep the central symbol across the whole
  repository, not the directory. Something reached only from a test is still
  reached.
- **The mines.** Where the tree and its documents disagree, where a name means
  something other than it says, where the local idiom has a trap in it.
- **What was already decided here.** `git log` over the area and merged pull
  requests on the task's keywords: the decisions the new work must not
  contradict silently, and the approaches already abandoned.

Zero hits are an outcome. Say so explicitly rather than omitting the line —
"nothing else references it" is what justifies a small fence.

**5. Compose the plan body** per § The plan file below.

Then read it back for **what it does not say**. Three questions surface that
class:

- **Could a builder satisfy every row and still not have done the work?** That
  is a missing requirement.
- **Does any row tell the builder how?** Cut it back to what must be true.
- **What is the reader assumed to already know?** They have this file and the
  repository, and no memory of this conversation.

**6. Present the plan and hold the gate.**

Present the composed body **verbatim** — not a summary of it. Then ask for
exactly one of:

- **go** — write the artifacts and finish.
- **stop** — the plan is worth keeping but the work is not starting now. Write
  the artifacts, record, and end.
- **pushback** — anything else. Take it back to step 3 or 4 and re-present.

The gate is not skippable, and neither branch of it is your call.

**7. Put the plan where this branch's plan goes.**

**The question is which branch the work belongs on — not whether a plan file
exists.** A branch with no plan yet is the ordinary state of a branch someone
made a minute ago. Compare the two § Context lines at the top.

*Branch is the base* — the work has no branch yet, so make one:

```bash
git checkout -b <type>/<kebab-slug>
```

`<type>` is one of `feat` / `fix` / `docs` / `refactor` / `chore` / `test`, and
the slug is short.

*Branch is anything else* — you are on a topic branch already. **Create no
branch.** If that branch is not where this work belongs, say so and stop; which
branch to be on is the user's call, not a thing to fix by making another.

Either way the branch is settled **before** the write: every consumer of the
plan derives its path from the current branch.

Then write the body to `plan.md` in the directory this branch's run owns. Ask
for the directory; do not compose it. It is **outside the repository being
worked on**.

```bash
mkdir -p "$(bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/lib.sh" hq_task_dir)"
bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/lib.sh" hq_task_dir
```

A gate checks the shape as you write it and blocks with what is wrong. Fix the
named items and write the file again; never work around it.

**8. Record the run.**

```bash
bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/record.sh" module name=plan \
  duration_s=$(( $(date +%s) - <START> ))
```

Replace `<START>` with the number from step 1 — it is a placeholder, not a
shell variable, and the command does not run until you have.

## The plan file

| section | required | what it holds |
|---|---|---|
| `## Summary` | yes | what this change does and why now, in three to five lines of this repository's own words. No vocabulary from this plugin. |
| `## Requirements` | yes | the table: one row per outcome, with how anyone confirms it. |
| `## Notes` | yes | what the survey found that the work has to reckon with, and what you decided **not** to touch, with why. |
| `## Editable surface` | yes | the existing paths the survey says the work reaches. The builder adds what it creates. |
| `## Floor` | yes | the machine checks any implementation of this must pass. Every item `[auto]`. |

The heading line above the sections is `# <type>(<scope>): <title>`.

`## Plan` is **not** written here. The builder writes it after it has designed,
as the work items it intends to commit; the ship gate counts them at the end.

Body prose is written in the conversation language; the headings and the tags
below are fixed English, because a machine reads them.

### The summary

Three to five lines. What is wrong now, and what will be true after. Someone
who has never seen this plugin, and does not work on this repository daily,
reads this section alone and knows what is being attempted.

**No vocabulary from this plugin.** No fence, no floor, no tags, no module
names. If a sentence needs one to make sense, it belongs in another section.

### The requirements table

One table. Every row is an outcome and the way anyone confirms it.

```
| # | what must be true | how anyone confirms it |
|---|---|---|
| R1 | <outcome, in this repository's words> | [manual] <one observable a person checks> |
| R2 | <outcome> | [review] <what the verifier must be able to trace in the built code> |
```

**Both columns on one row, deliberately.** A list of outcomes and a separate
list of confirmations must correspond, and two lists that must correspond are
the shape that goes quietly out of step. One row, one pair.

Row ids are `R<digits>`, unique, and are how everything downstream refers to a
row.

### The confirmation tags

Every `## Requirements` row carries exactly one, in its
`how anyone confirms it` column — the last one, beside the outcome it confirms.

| tag | who confirms, and how |
|---|---|
| `[manual]` | a person runs or looks at one observable thing. |
| `[review]` | pillar A's verifier traces, in the code that was built, where this outcome is satisfied. An outcome it cannot trace is a finding. |

**Never the builder's own word.** Neither tag is satisfied by the party that
wrote the code saying it did the work. That separation is what pillar A is.

**`[manual]` is for what no machine here can check.** If a test could assert
the outcome, the row is `[review]`, and what the verifier traces is that test:
that it exists, and that it asserts this row rather than something adjacent.
The builder writes it as part of building, and it joins the suite `## Floor`
already runs.

Getting this backwards has a specific cost. A `[manual]` row goes into the pull
request body as something a person still has to do, so a row that a test
actually covers reads as outstanding forever — and one that no test covers,
written as `[manual]` because it *sounded* like a person's job, reads as
covered by a person who is never going to build the fixture. **The question is
not who would naturally look at it. It is whether a machine here could.**

### The notes

List items. Four kinds carry almost all of the value, and the survey usually
turns up some of each:

| kind | what it is | why the plan has to carry it |
|---|---|---|
| constraint | something that stops the straightforward shape from working | the builder cannot find it by reading the files it edits, and will design around a wall that is not there — or into one that is |
| reach | what else moves when this moves | so the builder does not re-survey the tree |
| mine | the tree and its documents disagree; a name means something other than it says | only a reader who has been here knows |
| left alone | what the survey found and you decided is out of scope, **with the reason** | without the reason the builder picks it up again |

**A note states a fact, not a decision about the new code.** Same test as a
requirement: change the design, and the note is still true.

### The fence tags

An `## Editable surface` entry is `` - `<path>` — [tag] <note, one line> ``.
The first backticked span is the path and nothing else is; an entry ending in
`/` covers what is under it.

| tag | the entry is |
|---|---|
| `[new]` | a file that does not exist yet |
| `[edit]` | an existing file the work changes |
| `[delete]` | a file the work removes |

**This section declares what the survey found — the existing files the change
reaches.** Which new files come into being is a design decision, so the plan
usually names none; the builder adds them, with the reason, before touching
them.

**Expanding the fence is allowed and is never silent.** A gate compares the
branch's diff against this section after every commit and names any path
nobody declared. What is forbidden is the diff arriving with paths nobody
declared — not the declaring.

### The floor

The machine checks that any implementation of this change must pass, whatever
shape the builder gives it: the test suite, the type checker, the linter, the
build. Every item is `[auto]` and its **first backticked span** is the command,
runnable verbatim here; no later span in the item may be a command — two
assertions fold into one shell string (`a && b`) rather than into two spans
joined by prose.

```
- [ ] [auto] `<command>`
```

**The floor is not the judgment.** It says nothing about whether the change did
what it was for; that is `## Requirements`, and the parties named there answer
it. Do not put a check here that only one design would pass — the builder has
not designed yet, and a floor it cannot meet without guessing your design is a
design decision in disguise.

Where the § Context line printed an Xcode configuration, the command under that
file's `## Build Command` is a floor item, lifted verbatim. That file's
`## Run Command` boots a simulator and launches the app; nothing it prints is
an assertion, so it belongs beside a `[manual]` row in `## Requirements` if it
belongs anywhere.

### Numbers in the body

Write the number, and put the command that produces it in parentheses after
it: 6 files (`git grep -l parse_manifest | wc -l`).

**The reader gets the number; the command is how the next reader checks it.**
Writing only the command hides the answer from every human and from any model
that will not stop to run it.

**The command has to compute what the sentence claims.** `git grep -l` prints
one line per file, so that form counts files; occurrences need
`git grep -c … | awk -F: '{s+=$NF} END {print s+0}'`.

**`s+0`, not `s`.** With no match, `git grep` prints nothing and awk's `s` is
never set, so `print s` emits a blank line where the answer is zero.

Where a value genuinely has no command behind it — a judgment, a count of
things only a reader can pick out — write the number and say where it came
from.

**`## Floor` items are excluded.** An item's first backticked span is its
command and no later span may be one, so a count command written in an item's
note is read as a second assertion and the gate blocks the write.
