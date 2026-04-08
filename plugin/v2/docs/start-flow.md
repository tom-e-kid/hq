# Start Flow

`/start` runs the complete hq workflow — from planning through PR creation — for a given `hq:task` issue.

```
Phase 1: Check Current State
│  Active work? (focus exists / feature branch with changes)
│  → Continue existing task → skip to Phase 5
│  → Interrupt → commit/stash, optionally /archive, switch to base
│  → No active work → proceed
│
Phase 2: Input Source
│  $ARGUMENTS → parse issue number + supplementary context
│  (no argument → ask user)
│
Phase 3: Planning (mandatory — no code before approval)
│  ┌─ 3a: Brainstorming ────────────────────────┐
│  │  Review hq:task, discuss with user,          │
│  │  investigate codebase, align on scope        │
│  └─────────────────────────────────────────────┘
│  ┌─ 3b: Plan Generation ──────────────────────┐
│  │  Launch Plan subagent → structured plan      │
│  │  (steps, gates, verification items)          │
│  └─────────────────────────────────────────────┘
│  ┌─ 3c: Review & Approval ────────────────────┐
│  │  Present plan → user feedback → wait for     │
│  │  explicit approval before proceeding         │
│  └─────────────────────────────────────────────┘
│
Phase 4: Execution Prep
│  Create hq:plan issue (sub-issue of hq:task)
│  Create work branch
│  Set focus (focus.md + .hq/tasks/<branch>/context.md)
│  Read workflow rules
│
Phase 5: Execute
│  Work through plan step by step
│  Format & build after each unit
│  Check off hq:plan checklist items
│
Phase 6: Simplify
│  /simplify → review full changeset
│  Format & build
│
Phase 7: Verification (parallel)
│  ┌────────────────────────────────────────────┐
│  │  code-reviewer    ║    security-scanner     │
│  │  (background)     ║    (background)         │
│  └──────────┬────────╨────────┬───────────────┘
│             ▼                 ▼
│  Fix FB issues (max 2 rounds)
│  E2E verification (if applicable)
│
Phase 8: PR Creation
│  Check unresolved FBs → escalate to hq:feedback?
│  /pr → create pull request
│
Phase 9: Report
   Task, plan, branch, changes, verification, PR link
```

## Key Design Decisions

- **Planning is mandatory** — no production code before user-approved plan. Brainstorming is interactive and takes as many turns as needed.
- **GitHub Issue traceability** — `hq:plan` is a sub-issue of `hq:task`. PR uses `Closes #plan` + `Refs #task`.
- **Parallel verification** — `code-reviewer` and `security-scanner` agents run simultaneously in the background.
- **Simplify before verify** — Phase 6 catches cross-cutting improvements (deduplication, unnecessary abstractions) that per-step reviews miss.
- **Resumable** — if active work is detected, the user can continue from Phase 5 without re-planning.
