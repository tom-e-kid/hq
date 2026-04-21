---
source: <hq:task issue number, e.g. 42>
plan: <hq:plan issue number, e.g. 123>
skill: <skill or agent that generated this FB, e.g. /code-review, /e2e-web, copilot>
run_at: <ISO 8601 timestamp>
covers_acceptance: <optional — unique substring of the `## Acceptance` item this FB covers, e.g. "`pnpm test` passes">
---

<!--
`covers_acceptance` is a soft convention (no hook / script enforces it):

- Populate it in FBs originating from `/hq:start` Phase 4 (Execute) or Phase 5 (Acceptance),
  where each FB maps 1:1 to a specific Acceptance item. The value is a short unique
  substring of that item's text, enough to disambiguate it within the plan body.
- Leave it unset in FBs originating from `/hq:start` Phase 6 (Quality Review) — code-reviewer
  and integrity-checker findings generally do not map 1:1 to Acceptance items.
- Leave it unset in FBs from external sources (`/hq:respond`, ad-hoc drops).

See `.claude/rules/workflow.local.md` § Feedback Loop for the rationale (linear audit trail
for the Phase 5 1-by-1 toggle rule).
-->


# <concise description of the issue>

- **File**: <target file and line number, if applicable>
- **Severity**: Critical / High / Medium / Low
- **Description**: <what is wrong or what failed>
- **Impact**: <why it matters>
- **Expected**: <what should have happened>
- **Actual**: <what actually happened>
- **Evidence**: <path to screenshot or log, if available — omit if none>
- **Hint**: <suspected code location or fix direction — omit if unknown>
