# Review-Triage Flow

`/review-triage` checks the current PR for unaddressed review comments (Copilot, human reviewers, etc.), analyzes each one, and autonomously takes the appropriate action.

```
Phase 1: Preconditions
│  PR exists? open?
│
Phase 2: Fetch
│  gh api → line-level review comments
│  Filter: top-level & no reply from PR author
│  (no unaddressed comments → done)
│
Phase 3: Deep Analysis (parallel)
│  ┌─────────────────────────────────────────────┐
│  │  review-comment-analyzer (per comment)       │
│  │  Read code → assess validity → classify      │
│  │  → self-validate → return structured result  │
│  └──┬──────────────┬──────────────┬─────────────┘
│     │              │              │
│   Fix          Feedback       Dismiss
│
Phase 4: Execute
│  ┌─ Fix (sequential) ──────────────────────────┐
│  │  Edit code → format → build → test           │
│  │  (no tests? → code-level verification)       │
│  │  Commit → push → reply with SHA              │
│  └──────────────────────────────────────────────┘
│  ┌─ Feedback + Dismiss (parallel) ─────────────┐
│  │  Feedback: create hq:feedback issue → reply  │
│  │  Dismiss: reply with evidence-based reason   │
│  └──────────────────────────────────────────────┘
│
Phase 5: Report
   Summary: Fix count + SHAs, Feedback issues, Dismiss count
```

## Key Design Decisions

- **Fully autonomous** — no user approval gates. All decisions are self-validated with evidence. The user reviews the results in the PR itself.
- **Conservative on Fix** — when uncertain about safety, escalates to `hq:feedback` rather than risking a regression.
- **Regression gate** — Fix changes must pass format, build, and test before commit. When no tests exist, code-level verification is documented in the commit message.
- **Evidence-based replies** — every reply (Fix, Feedback, Dismiss) cites specific code references, commits, or documentation.
