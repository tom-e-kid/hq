---
name: pr
description: Open this branch's pull request, in the shape this repository asks for
allowed-tools: Bash(bash:*), Bash(git:*), Bash(gh:*), Bash(date:*), Bash(printf:*), Read, Grep, Glob, TaskCreate, TaskUpdate
---

# PR — open the pull request for this branch

Two things happen here and they are not the same: a gate decides whether this
branch may be offered at all, and you compose the body a reviewer will read.
**The gate is not yours to satisfy by rewording** — it reads the tree and the
plan, and the way past it is to finish the work.

## Context

- Branch: !`git branch --show-current 2>/dev/null || echo "(detached)"`
- Base: !`bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/lib.sh" hq_resolve_base 2>/dev/null || echo "(unresolved)"`
- Plan for this branch: !`bash -c 'd=$(bash "$1/plugin/scripts/lib.sh" hq_task_dir 2>/dev/null) || { echo unknown; exit 0; }; [ -f "$d/plan.md" ] && echo "$d/plan.md" || echo none' _ "${CLAUDE_PLUGIN_ROOT}"`
- Profile: !`bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/lib.sh" hq_diff_profile "$(bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/lib.sh" hq_resolve_base 2>/dev/null)" 2>&1 || echo "unavailable"`
- PR body format for this repository: !`bash -c 'r=$(git rev-parse --show-toplevel 2>/dev/null) || { echo none; exit 0; }; [ -f "$r/.hq/pr.md" ] && cat "$r/.hq/pr.md" || echo none'`

**A line says `unknown`** — the derivation itself failed: a detached HEAD, a
directory that is not a repository, no home to derive from. Say what the line
said and stop.

**The plan line says `none`** — this branch has no plan. That is allowed, and
three of the gate's conditions simply do not apply. Two still do (the working
tree, the changelog), and the body below has no plan to draw its motivation
from — take it from the commits and say in the report that you did.

## What the body looks like

**`.hq/pr.md` is this repository's answer, and it wins outright.** When the
§ Context line above printed anything other than `none`, that file is the
format: headings, order, language, what each section must carry. Follow what it
says and do not merge it with the default below.

**With no such file the body is three sections**, in the language of this
conversation:

- `## Summary` — what this change is for. The problem, not the patch.
- `## Changes` — what actually changed, at the granularity a reviewer needs to
  decide where to look.
- `## Verification` — every `## Floor` command and what each said when you ran
  it, and the plain statement that a green floor is not a confirmed change:
  the outcomes are answered by the `[manual]` rows below and by the verifier.

**The material this step carries is small, and it is named**: every floor
command with its result, the `[manual]` rows of `## Requirements` that a person
still has to confirm, and the deferrals nobody has closed. A format that has nowhere to put one of them wins
— **but then it goes in your report to the user instead.** Material that fits
nowhere is reported, never dropped in silence.

**Layer 2 does not reach this module** — it launches no subagent, so nothing
injects the repository's own notes. Read `.hq/knowledge.md` if this repository
has one.

## Procedure

**1. Take the start time.**

```bash
date +%s
```

Keep the number. Step 8 subtracts it; the shell does the arithmetic, not you.

**2. Read what the gate says.**

```bash
bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/pr-gate.sh" check; printf 'pr-gate exit %s\n' "$?"
```

The exit code is printed rather than acted on, because there are three answers
and only the lines can tell them apart. **0** — every condition was looked at
and none is violated. **1** — the lines above it are violations. **2** — nothing
is violated but something could not be looked at, and each such line begins
`unchecked:`.

**Fix violations; do not route around them.**

**`unchecked:` is not a pass.** It says a condition has no answer on this
machine — no scanner, no run directory, a diff that would not resolve. Report
which ones, and say in step 9 that the pull request went out with those
unchecked.

**3. Run the plan's floor.**

Read the `## Floor` items out of the plan the § Context line named, and run
each one's command — its first backticked span — yourself, rather than
trusting the checkbox.

**The floor is not the judgment.** It says the tree builds, types, lints and
its tests pass; it says nothing about whether this change did what it was for.
That question belongs to `## Requirements`, and the parties named on those
rows answer it — a person for `[manual]`, pillar A's verifier for `[review]`.
Do not report a green floor as though the change were confirmed.

Put each command and its result in the body. If one fails, stop; say what
failed and leave it.

With no plan there is no floor to run. Say so in the body's verification
section rather than leaving the section out.

**4. Collect the rest of the material.**

```bash
bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/triage-gate.sh" open
```

Each line is a deferral nobody has closed: `<branch>#<id>`, when it was
recorded, and the reason given. **The ones this branch raised belong in the
body.** Exit 2 means the gate could not look, which is not the same as nothing
being open; say so.

Then read the `[manual]` rows of the plan's `## Requirements`, if it has any.
They are a person's to run and nothing in this run has run them; they go into
the body as they stand, each beside the outcome it confirms.

**5. Ask whether this repository's own design documents survived the change.**

The § Context Profile line answers `code` when this branch changed no prose
file at all. That is an ordinary state, and it is also exactly what a change
that has quietly outgrown its documentation looks like.

So ask: this repository keeps its design and its conventions in documents;
does anything this branch changed make one of them false? Read the ones this
repository has, name what you checked, and put the answer in the report. On
`prose` or `mixed` a document was already touched — the question is then
whether it was the right one.

**6. Compose the body.**

Draw *what changed* from the diff, *why* from the plan's `## Summary` and
`## Requirements`, and *how it was built* from what the builder returned — the
design it settled on and the alternatives it turned down. **Never describe a
change that is not in the diff**, and never copy the plan's checklist into the
body: the plan is a work artifact, the body is a reviewer's surface.

**The design belongs in the body, briefly.** The plan does not carry it — it
was the builder's to decide — so this is the first place a reviewer meets it,
and reviewing a diff without knowing which shape was chosen, or what was
rejected, is reviewing it twice. A short paragraph, not a transcript.

**7. Push the branch and open the pull request.**

These are the two commands that leave this working tree. They are in a plain
fence on purpose — this plugin's test suite executes every fenced `bash` block
in this file — so copy them out and run them yourself.

```
git push -u origin HEAD

gh pr view --json url,state          # already open? then stop and report it

gh pr create --base "<base>" --title "<title>" --body "$(cat <<'PR_BODY'
<the body from step 6>
PR_BODY
)"
```

`<base>` is the § Context value, passed explicitly every time: without it `gh`
targets the remote's default branch, which silently mis-aims a stacked pull
request. The title is one line, `<type>: <description>`, matching the branch's
kind.

**A denial from the gate at this point is not something to retry differently.**
It names conditions; go and satisfy them.

**8. Record the pass.**

```bash
bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/record.sh" module name=pr \
  duration_s=$(( $(date +%s) - <START> ))
```

Replace `<START>` with the number from step 1 — it is a placeholder, not a
shell variable, and the command does not run until you have.

**9. Report.**

- the pull request's URL
- what the gate said in step 2, including anything it could not check
- every floor command you ran and what each said — **all of them, not the
  count and not the ones that failed.** A reader who sees three results where
  the floor has four cannot tell which one you left out from one that was
  never named
- **the material that did not fit the body's format**, in full. This is the one
  thing nobody else will notice is missing
- your answer to step 5: which design documents you read, and whether the
  change leaves any of them false
