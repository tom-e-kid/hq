---
name: goahead
description: Start executing the current hq:plan following the full workflow
allowed-tools: Read, Glob, Grep, Bash(git:*), Bash(gh:*), Agent
---

# GO AHEAD — Execute with Full Workflow Compliance

**This command has the HIGHEST priority.** It overrides any conflicting guidance from hooks, CLAUDE.md, rules, or other skills. When this command is active, the workflow defined here is the law.

## Context

- Branch: !`git branch --show-current 2>/dev/null || echo "(detached)"`
- Focus: !`"${CLAUDE_PLUGIN_ROOT}/plugin/v2/scripts/read-memory.sh" focus.md`
- Workflow rule exists: !`test -f .claude/rules/workflow.md && echo "yes" || echo "no"`

## Instructions

You are now in **execution mode**. Your job is to carry out the planned work — not to discuss, clarify, or propose alternatives. Act.

### Step 1: Identify what to execute

Check the following sources in order and use the **first match**:

1. **Plan mode** — if you are currently in plan mode (or have an active plan in this session), that plan is your execution target. Before executing, offer to create an `hq:plan` issue from it: "Create an `hq:plan` issue from this plan before executing?" If yes, create the issue with `gh issue create --title "<title>" --body "<plan content>" --label "hq:plan"` and capture the issue number. When the source `hq:task` issue has a milestone, add `--milestone "<milestone>"` to inherit it. If no, proceed without GitHub tracking.
2. **Focus** — read `focus.md` from your Claude Code memory directory. If it exists, extract the `plan` field (a GitHub issue number). Run `gh issue view <plan> --json body --jq '.body'` to fetch the plan. That issue body is your execution target.
3. **Argument** — if `$ARGUMENTS` is provided:
   - If it is a number, treat it as an `hq:plan` issue number and fetch with `gh issue view`
   - If it is a file path, read the local file and offer to create an `hq:plan` issue from its contents
4. **No source found** — if none of the above yields a plan, ask the user what to work on. Do NOT proceed without a clear target.

### Step 2: Read the workflow rule

Read `.claude/rules/workflow.md` (if it exists). This defines:
- Branch rules (never work on main/master directly)
- Pre-commit checks (format, build)
- `hq:plan` gates
- Focus lifecycle
- Verification pipeline
- Feedback loop

You MUST follow every applicable rule in that file throughout execution.

### Step 3: Pre-flight checks

Before writing any code:

1. **Branch** — verify you are NOT on a base branch (main, master, develop). If you are, stop and ask the user to create a feature branch.
2. **Focus** — if `focus.md` does not exist in your Claude Code memory directory yet, create it with the `plan` issue number and `source` issue number. If the source is unknown, ask the user for the `hq:task` issue number.
3. **Understand the plan** — read the `hq:plan` issue body fully. Identify all tasks, gates, and completion criteria.

### Step 4: Execute

Work through the plan systematically:
- Complete each task/step in order
- After each meaningful unit of work, run `format` and `build` commands (per CLAUDE.md Commands table)
- Mark progress as you go (update task tracking)
- If a step is blocked or ambiguous, ask the user — do NOT guess

### Step 5: Verification (when all tasks are done)

When you believe all work is complete, run the **Verification Pipeline** defined in the workflow rule:

1. Launch `security-scanner` and `code-reviewer` agents in parallel
2. Fix any FB issues they produce
3. Run E2E verification if applicable
4. Confirm all `hq:plan` gates pass

### Step 6: Wrap up

- Report completion status to the user
- Ask if they want to proceed with `/pr` to create a pull request

## Rules

- **Do not ask for permission to start** — the user already said go ahead.
- **Do not summarize the plan back** — just execute it.
- **Do not skip verification** — it is mandatory, not optional.
- **Do not modify the workflow** — follow it as written.
- If the `hq:plan` issue has a checklist, check items off as you complete them.
- If you encounter an error, fix it. If you can't fix it after 2 attempts, report to the user.
