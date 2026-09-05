---
name: review
description: Pillar A — launch the verifier over this branch's changes and collect what it could falsify
allowed-tools: Bash(bash:*), Bash(git:*), Agent, TaskCreate, TaskUpdate
---

# REVIEW — verify what this branch claims

Pillar A: the party that verifies is not
the party that wrote. You are the caller. You do not review the diff yourself —
you launch the verifier, and you never edit its findings.

## Context

- Branch: !`git branch --show-current 2>/dev/null || echo "(detached)"`
- Base: !`bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/lib.sh" hq_resolve_base 2>/dev/null || echo "(unresolved)"`
- Targets: !`bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/lib.sh" hq_review_targets "$(bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/lib.sh" hq_resolve_base 2>/dev/null)" 2>&1 || echo "(TARGETS UNAVAILABLE — see step 1)"`
- Profile: !`bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/lib.sh" hq_diff_profile "$(bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/lib.sh" hq_resolve_base 2>/dev/null)" 2>&1 || echo "unavailable"`
- Output directory: !`bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/lib.sh" hq_task_dir 2>/dev/null || echo "(unresolved)"`
- Earlier pass: !`bash -c 'd=$(bash "$1/plugin/scripts/lib.sh" hq_task_dir 2>/dev/null) || { echo unknown; exit 0; }; if [ -f "$d/findings.jsonl" ]; then echo "$d/findings.jsonl"; else p=none; for f in "$d/reports"/*; do [ -e "$f" ] && p="clean ($d/reports/)"; done; echo "$p"; fi' _ "${CLAUDE_PLUGIN_ROOT}"`

Each target line is `<verifier><TAB><path>`. The mapping lives in `lib.sh`
(`hq_verifier_for`) and nowhere else, so do not re-derive it from the paths.

**The earlier-pass line decides which pass this is.** `none` means neither a
findings file nor a report is there: no verifier has run, and step 3 launches a
first pass. A findings path, or `clean` with the reports directory, means one
has, and the launch has more to carry — see step 3's second half. `unknown`
means the derivation failed; that is the same stop as an unresolved output
directory.

## Procedure

**1. Tell an empty diff apart from a diff you could not take.**

Both leave the target list blank, and they lead to opposite actions.

*Targets unavailable* — the line above says `TARGETS UNAVAILABLE`, or carries a
`fatal:` from git. The base did not resolve: it may name a branch that exists
only as `origin/<name>`, or be misspelled in `.hq/settings.json`, or not be
fetched. **Report the error and stop. Write no record.**

*Targets empty, no error* — the branch has no changes against its base. Say so,
record it, and stop; do not launch a verifier to look at nothing.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/record.sh" module name=review duration_s=0 profile=none
```

**2. Get the repository context.**

```bash
bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/inject.sh"
```

Its entire output — first line through the `sha256:` line — goes into the
launch prompt **verbatim**. Do not summarise it, do not quote parts of it, do
not reformat it. A gate compares what you pasted against what those files say
at launch time and refuses the launch when they disagree. If the launch comes
back denied, run this command again and replace the entire block; editing the
old one to match is the failure the gate exists to catch.

**3. Launch the verifier.**

One `reviewer` agent, through the Agent tool. Its prompt carries, in this
order:

- the base branch and the current branch
- the target list from § Context, verbatim
- the output directory from § Context, verbatim
- the injected block from step 2, verbatim

Nothing else on a first pass. The verifier's instructions are its own
definition; do not restate them.

**On a later pass, four more things.** The § Context line named a findings file
or read `clean`, so a pass has already run. Carry:

- **the previous findings**, by path — the file the line named. On a `clean`
  line there is no findings file and there were no verdicts either; say both in
  the prompt and carry the remaining two items
- **what triage decided about each of them**, as the triage step reported it:
  the id, the verdict, and the sentence it rested on. This is the one item with
  no file to point at; paste what you have. **Where the run does not have them,
  say that in the prompt** rather than leaving the item out
- **the previous prose report**, by path — `reports/` under the output
  directory holds one per pass, and the claims the last pass could not falsify
  are in the most recent
- **the commits since that pass**, as a range the verifier can run `git log` and
  `git diff` over. That diff is the part it reads at full strength

If the output-directory line reads `(unresolved)` — a detached HEAD, or no
repository — stop and say so; there is nowhere for the findings to go.

**Background or not, decided by what you would do while waiting.** The Agent
tool backgrounds by default, and one question decides it: **does the work you
would do meanwhile change this working tree?** The verifier reads files and
runs tests against the tree as it stands; editing anything here while it runs
means it reads a mixture of before and after. So:

- **Nothing else to do, or the next thing is an edit here** — run it in the
  foreground and wait.
- **The parallel work leaves this tree alone** — composing a pull request body,
  reading, talking it over — background it and pick the result up on return.

**4. Record the run.**

```bash
bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/record.sh" module name=review \
  duration_s=$(( <MS> / 1000 )) profile=<PROFILE>
```

Replace `<MS>` with the verifier's own run time exactly as the Agent tool
reports it — the `duration_ms` figure that comes back with the agent, pasted
unchanged. Replace `<PROFILE>` with the value from § Context. Both are
placeholders rather than shell variables, and the command does not run until
they are gone. The shell does the division; you paste the number you were
given, not a wall-clock difference.

**5. Report what came back.**

The verifier appends to `findings.jsonl` and writes a prose report under
`reports/`, both inside the output directory from § Context — outside the
repository, so nothing it wrote shows up in this branch's diff. Report to the
user:

- the finding count, by class, and how many carry no class
- the count by weight, and **which of `high` and `medium` are outstanding** —
  those are what stop the change shipping, and they are the number the user is
  deciding on
- on a later pass, which ids this pass added
- the number of claims the verifier tried to falsify and could not
- both file paths

Then stop. **Triage decides what happens to a finding, and it is a separate
step.** Do not fix, dismiss, or rank the findings here; re-weighting one is the
same act. If the user asks you to act on a finding, that is their call to make
and theirs to make explicitly.

**6. When this runs again.**

Not after every fix pass. What earns another round is a fix that **changed what
something does** — code, or an instruction that is read and acted on at run
time.

A pass that only touched records — a changelog entry, a decision log, a comment
restating what the code already says — does not earn one.

A `low` finding does not start a round by itself either. It rides along with
whatever else is being fixed.
