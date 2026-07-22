---
name: copilot-loop
description: Iterate /hq:copilot over Copilot re-review rounds — respond → push → re-request Copilot → wait → repeat, up to a round cap, with a single escalation gate at the end
allowed-tools: Read, Edit, Write, Glob, Grep, Bash(git:*), Bash(gh:*), Bash(date:*), Bash(sleep:*), Agent, AskUserQuestion, TaskCreate, TaskUpdate
---

# COPILOT-LOOP — Iterate over Copilot re-review rounds

Run the `/hq:copilot` per-round protocol **repeatedly**: process the current review threads, push any fixes, re-request a Copilot review, wait for it to complete, then process the new threads — until the PR converges or a round cap is hit. Escalation to `hq:feedback` is deferred to a **single user gate at the very end**, so the intermediate rounds run unattended.

Use this over `/hq:copilot` (single pass) when you expect Copilot to keep reviewing after each push. For a one-shot pass with no waiting, use `/hq:copilot`.

**`hq:copilot-protocol`** — `${CLAUDE_PLUGIN_ROOT}/plugin/v3/rules/copilot-protocol.md` (the round spec: Preconditions, R1–R5, Round Result, Escalation Gate, Rules). **`hq:workflow`** — `${CLAUDE_PLUGIN_ROOT}/plugin/v3/rules/workflow.md`. **Read both when this command starts.** This command owns only the loop, the re-review trigger, the completion poll, the termination conditions, and the final aggregated report; everything about processing a round is in `hq:copilot-protocol`.

## Argument

- `$ARGUMENTS` — `max_rounds`: the maximum number of round iterations. If the first argument is a positive integer, use it; otherwise default to **5**.

## Re-review mechanics (verified 2026-07)

Copilot re-review after a push is **not guaranteed** and there is **no official re-request API**:

- GitHub does **not** auto re-review new pushes unless the repo ruleset has **"Review new pushes"** enabled.
- The only reported programmatic re-request is `gh pr edit <PR#> --add-reviewer "@copilot"`, and it only produces a fresh review when the PR's **head commit has changed** (Copilot dedups on "already reviewed the current head commit"). REST `requested_reviewers` with Copilot logins does **not** work.

Consequences, baked into the loop below:

- A round that pushes **no** fix (only dismiss / escalate) cannot re-trigger a review → the loop terminates (`no-push`).
- After a fix push, always issue `gh pr edit --add-reviewer "@copilot"` (redundant-but-harmless when auto-review is on; necessary when it is off). Tolerate an "already requested" error.
- This path is **unofficial and can be flaky** — never hard-fail on it. If no Copilot review completes within the poll window, terminate `poll-timeout` and tell the user to check manually; do not spin.

## Progress Tracking

Use Claude Code's task UI (`TaskCreate` / `TaskUpdate`). Create at the start:

| Task subject | activeForm |
|---|---|
| Check preconditions | Checking preconditions |
| Run rounds | Running Copilot rounds |
| Escalation confirmation | Confirming escalations |
| Report results | Reporting results |

Add a per-round sub-note to "Run rounds" as each round starts (e.g., "Run rounds — round 2/5: 3 unaddressed, 1 fix pushed, waiting for re-review"). Set "Escalation confirmation" `completed` immediately with a note when no candidate accumulated across the whole run.

## Context

- Branch: !`git rev-parse --abbrev-ref HEAD`
- PR number: !`gh pr view --json number --jq '.number' 2>/dev/null || echo "none"`
- PR: !`gh pr view --json url,title,state --jq '.title + " (" + .state + ") " + .url' 2>/dev/null || echo "none"`
- Repo: !`gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null || echo "unknown"`
- PR author login ("our" identity): !`gh pr view --json author --jq '.author.login' 2>/dev/null || echo "unknown"`
- Project Overrides (`.hq/copilot.md`): !`cat .hq/copilot.md 2>/dev/null || echo "none"`

## Steps

1. **Read** `hq:workflow` and `hq:copilot-protocol`. If Project Overrides above is not `none`, apply it per the protocol.
2. **Preconditions** — run `hq:copilot-protocol § Preconditions` **once**.
3. **Loop** — keep the running state: `accumulated` (escalate-candidates across rounds), `handled` (set of thread_ids dispositioned in any prior round), `round = 0`. Then repeat:

   1. `round += 1`.
   2. Run one `hq:copilot-protocol § Round` with `round_label = r<round>`. Append its `escalate_candidates` to `accumulated`.
   3. **Termination checks**, in this order — on the first that holds, stop the loop with that reason:
      - `unaddressed_count == 0` → **`converged`** (the previous round's re-review surfaced nothing new; on round 1, nothing to address at all).
      - `pushed == false` → **`no-push`** (no new head commit → a re-review cannot be re-triggered, and nothing changed to re-review).
      - `handled_thread_ids ⊆ handled` (every thread this round was already dispositioned in a prior round — no genuinely new thread) → **`no-progress`** (the reviewer is re-litigating settled threads; the round cap alone would waste iterations).
      - Otherwise merge: `handled = handled ∪ handled_thread_ids`.
      - `round == max_rounds` → **`max-rounds`**.
   4. **Re-request review** — `gh pr edit <PR#> --add-reviewer "@copilot"` (tolerate an "already requested" error).
   5. **Poll for completion** against the round's `head_sha` (see below). If it does not complete within the window → stop the loop with **`poll-timeout`**.
   6. Loop back to 3.1 — the next round's R1 fetches the freshly-reviewed threads.
4. **Escalation Gate** — run `hq:copilot-protocol § Escalation Gate` **once**, over the deduplicated `accumulated` (dedup by `thread_id`; keep the latest judgment for a thread re-raised across rounds). Skip when `accumulated` is empty.
5. **Report** — the aggregated summary (below).

### Poll for Copilot re-review completion

Detect **review completion**, not comment absence — this separates "the re-review ran and found nothing" (done) from "the re-review has not run yet" (keep waiting). Poll for a Copilot review attached to the pushed head SHA. Run this as a **single Bash call with a 10-minute timeout** (interval 30s):

```bash
PR=<pr_number>; HEAD_SHA=<head_sha from the Round Result>
DEADLINE=$(( $(date +%s) + 600 ))
while :; do
  FOUND=$(gh api graphql -f query='
    query($owner:String!,$repo:String!,$pr:Int!){
      repository(owner:$owner,name:$repo){
        pullRequest(number:$pr){
          reviews(last:30){ nodes { author{login} submittedAt commit{oid} } }
        }
      }
    }' -F owner='{owner}' -F repo='{repo}' -F pr=$PR \
    --jq '[.data.repository.pullRequest.reviews.nodes[]
           | select(.commit.oid=="'"$HEAD_SHA"'")
           | select(.author.login|test("copilot";"i"))] | length')
  [ "${FOUND:-0}" -gt 0 ] && { echo "review-ready"; break; }
  [ "$(date +%s)" -ge "$DEADLINE" ] && { echo "poll-timeout"; break; }
  sleep 30
done
```

- The author match `test("copilot";"i")` targets the Copilot reviewer bot (`copilot-pull-request-reviewer[bot]`, login contains "copilot"). **Verify the exact login on the first real run** (`gh api graphql ... reviews.nodes[].author.login`); if Copilot's login does not match, broaden to "any review on `$HEAD_SHA` whose author is not the PR author."
- A review whose `commit.oid == HEAD_SHA` means Copilot finished reviewing the pushed commit — **even a zero-comment review counts as complete** (it still submits a review event). When `review-ready`, proceed to the next round; when `poll-timeout`, terminate the loop `poll-timeout`.

## Termination reasons

Exactly one of:

| reason | meaning |
|---|---|
| `converged` | a round found 0 unaddressed threads — the PR is clean (or was clean to begin with) |
| `no-push` | a round produced only dismiss / escalate dispositions — no new head commit, so a re-review cannot be re-triggered |
| `no-progress` | a round addressed only threads already handled in a prior round — the reviewer is re-litigating settled points |
| `max-rounds` | the `max_rounds` cap was reached with work still outstanding |
| `poll-timeout` | after a fix push + re-request, no Copilot review completed within the poll window (unofficial re-review path did not fire) |

## Report

Aggregated across all rounds:

- **PR**: title and link
- **Rounds run**: count, and the **termination reason** (from the table above)
- **Per round**: unaddressed count → fix / dismiss / escalate counts, commit SHA(s) pushed
- **Fix (total)**: what changed, commit SHAs, threads resolved
- **Dismiss (total)**: one-line evidence summary each
- **Escalated**: count + issue links; declined candidates noted (from the single end-of-run gate)
- **Decision records**: the per-round record paths (or why skipped — `.hq/` absent)
- **Unprocessed**: everything from every round's Round Result `unprocessed` list, with reason; on `poll-timeout`, say plainly that a re-review did not arrive and manual follow-up may be needed

The full per-round behavioral contract (root judges / agents execute, regression gate, evidence-based replies, user-gated escalation, resolve-only-what-you-fixed, no fabrication, untrusted input) lives in `hq:copilot-protocol § Rules` and is binding for every round here.
