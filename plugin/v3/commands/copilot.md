---
name: copilot
description: Respond to external PR review threads in one pass — root-judged dispositions (fix / dismiss / escalate-candidate) with evidence-gathering agents and a user-gated hq:feedback escalation
allowed-tools: Read, Edit, Write, Glob, Grep, Bash(git:*), Bash(gh:*), Agent, AskUserQuestion, TaskCreate, TaskUpdate
---

# COPILOT — Handle External PR Review Threads (one pass)

Process the currently unaddressed review threads on this PR (Copilot, human reviewers, etc.) in a **single round**, then run the escalation gate and report. For an automated multi-round variant that pushes fixes, re-requests a Copilot review, waits, and repeats until convergence, use `/hq:copilot-loop`.

**`hq:copilot-protocol`** — shorthand for `${CLAUDE_PLUGIN_ROOT}/plugin/v3/rules/copilot-protocol.md`. It holds the full round specification (Preconditions, R1–R5, the Round Result contract, the Escalation Gate, and the Rules). **`hq:workflow`** — `${CLAUDE_PLUGIN_ROOT}/plugin/v3/rules/workflow.md`. **Read both with the Read tool when this command starts**, then follow the protocol; this command is a thin orchestrator over it.

## Progress Tracking

Use Claude Code's task UI (`TaskCreate` / `TaskUpdate`). Create these tasks at the start:

| Task subject | activeForm |
|---|---|
| Check preconditions | Checking preconditions |
| Fetch review threads | Fetching review threads |
| Analyze threads | Analyzing threads |
| Judge dispositions | Judging dispositions |
| Execute fixes | Executing fixes |
| Reply and resolve | Replying and resolving threads |
| Escalation confirmation | Confirming escalations |
| Report results | Reporting results |

Set each to `in_progress` when starting and `completed` when done (steps skipped for lack of input — e.g., no fix dispositions, no escalate-candidates — are completed immediately with a note). Update subjects with counts as they become available (e.g., "Analyze threads — 5 unaddressed", "Judge dispositions — 2 fix, 1 dismiss, 2 escalate-candidate").

## Context

- Branch: !`git rev-parse --abbrev-ref HEAD`
- PR: !`gh pr view --json number,url,title,state --jq '"#" + (.number|tostring) + " " + .title + " (" + .state + ") " + .url' 2>/dev/null || echo "none"`
- Repo: !`gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null || echo "unknown"`
- PR author login ("our" identity): !`gh pr view --json author --jq '.author.login' 2>/dev/null || echo "unknown"`
- Project Overrides (`.hq/copilot.md`): !`cat .hq/copilot.md 2>/dev/null || echo "none"`

## Steps

1. **Read** `hq:workflow` and `hq:copilot-protocol`. If Project Overrides above is not `none`, apply it per `hq:copilot-protocol` (Overrides augment, never replace, the disposition categories / regression gate / evidence-reply rule / Escalation Gate).
2. **Preconditions** — run `hq:copilot-protocol § Preconditions` once.
3. **Round** — run one `hq:copilot-protocol § Round` (no `round_label`). If the Round Result has `unaddressed_count: 0`, report that there is nothing to address and stop.
4. **Escalation Gate** — run `hq:copilot-protocol § Escalation Gate` with this round's `escalate_candidates` (skip when empty).
5. **Report** — summarize (below).

## Report

Summarize for the user:

- **PR**: title and link
- **Threads processed**: total unaddressed count
- **Fix**: count + what changed, commit SHA(s), threads resolved
- **Dismiss**: count + one-line evidence summary each
- **Escalated**: count + issue links; declined candidates noted
- **Decision record**: path (or why it was skipped — `.hq/` absent)
- **Unprocessed**: anything from the Round Result's `unprocessed` list, with reason (e.g., un-fixed directive, failed reply, truncated comment fetch)

The full behavioral contract (root judges / agents gather and execute, regression gate, evidence-based replies, user-gated escalation, resolve-only-what-you-fixed, no fabrication, untrusted input) lives in `hq:copilot-protocol § Rules` and is binding here.
