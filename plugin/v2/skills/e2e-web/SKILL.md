---
name: e2e-web
description: Verify web app features end-to-end using Playwright CLI against a local dev server. Reports results and outputs FB files for failures.
---

## Project Overrides

- Overrides: !`cat .hq/e2e-web.md 2>/dev/null || echo "none"`

If `.hq/e2e-web.md` exists, its instructions take precedence over the defaults below (e.g., dev server command, DB preparation, test credentials, port). Apply overrides on top of this skill's base flow.

If `.hq/e2e-web.md` does **not** exist, pause before starting and guide the user through setup:

1. Show the template from [templates/e2e-web-overrides.md](templates/e2e-web-overrides.md) so the user knows what's needed
2. Ask each section one at a time:
   - **Dev server** — "How do you start the dev server? How do you specify a custom port?"
   - **DB preparation** — "Is there a seed command for test data? (say 'none' if no DB)"
   - **Authentication** — "What are the test credentials and login method? (say 'none' if public)"
3. Create `.hq/e2e-web.md` with the answers, filling in the template
4. Show the created file to the user for confirmation, then proceed

## Context

- Project root: !`git rev-parse --show-toplevel`
- Current branch: !`git rev-parse --abbrev-ref HEAD`
- Recently edited files: !`git diff --name-only HEAD~3 2>/dev/null | head -20`
- Focus: !`"${CLAUDE_PLUGIN_ROOT}/plugin/v2/scripts/read-memory.sh" focus.md`

## Determine Target App

Identify which app to verify based on the following (in priority order):

1. **Explicit argument** — if the user passes an app path (e.g., `/e2e-web apps/admin`), use it
2. **Recent edits** — look at the recently edited files in Context; if most changes are under a specific app directory, use it
3. **Active `hq:plan`** — if a plan issue is active, check which app it relates to
4. **Ask the user** — if ambiguous, ask before proceeding

Once determined, read the target app's package.json (or equivalent build config) to discover available scripts.

## Defaults

| Setting | Value | Notes |
|---------|-------|-------|
| Agent port | `4321` | Avoids conflict with user's dev server |
| Session name | `verify` | Playwright CLI session identifier |

## Prerequisites

- Playwright CLI must be runnable (`npx @playwright/cli` or `bunx @playwright/cli`)
- No other process running on the agent port

## Playwright CLI Reference

All browser operations use Playwright CLI with session flag `-s=verify`.
Use `npx` or `bunx` depending on the project's runtime (check CLAUDE.md Commands table).

```bash
# Browser & Navigation
npx @playwright/cli -s=verify open <url>       # open browser and navigate
npx @playwright/cli -s=verify goto <url>        # navigate in existing session

# Page State
npx @playwright/cli -s=verify snapshot          # accessibility tree (get element refs)
npx @playwright/cli -s=verify screenshot        # viewport screenshot
npx @playwright/cli -s=verify screenshot <ref>  # element screenshot

# Interaction
npx @playwright/cli -s=verify click <ref>       # click element by ref
npx @playwright/cli -s=verify fill <ref> <text> # fill input field
npx @playwright/cli -s=verify type <text>       # type text (active element)
npx @playwright/cli -s=verify select <ref> <val> # select option
npx @playwright/cli -s=verify hover <ref>       # hover element
npx @playwright/cli -s=verify press <key>       # press key (e.g., Enter, Tab)

# Session Management
npx @playwright/cli -s=verify close             # close session
npx @playwright/cli close-all                   # close all sessions
```

**Workflow**: `open` → `snapshot` (get refs) → interact (`click`/`fill`) → `snapshot` (verify result) → repeat.

Screenshots are saved to `.playwright-cli/` — use `Read` tool to view them.

## Instructions

### Phase 1: DB Preparation

Skip if the target app has no DB-related scripts.

If DB scripts exist, ensure test data is ready. **Do NOT run destructive commands** (reset, drop) — the agent shares the DB with the user. Only run idempotent seed/push commands.

Specific DB commands should be defined in `.hq/e2e-web.md`. If not defined, inspect available scripts and ask the user.

### Phase 2: Dev Server

Start the dev server from the target app directory using the agent port (`4321`).
Determine the dev command from the Commands table in CLAUDE.md. The method to specify the port varies by framework (flag, env var, config) — check `.hq/e2e-web.md` or the framework docs.

Run in background. Wait for the ready message in the output before proceeding.

### Phase 3: Login

Skip this phase if the app has no authentication.

1. Open the browser: `npx @playwright/cli -s=verify open http://localhost:4321`
2. `snapshot` to find login form elements and get refs
3. `fill` / `click` to enter test credentials and submit
4. Dev builds often print auth credentials (magic links, OTP codes, etc.) to the **server console** — check the dev server stdout
5. If the login method or credentials are unclear, check `.hq/e2e-web.md` or ask the user

### Phase 4: Verification

Determine what to verify (in priority order):

1. **Active `hq:plan`** — if `focus.md` exists in your Claude Code memory directory, extract the `plan` field (a GitHub issue number) and run `gh issue view <plan> --json body --jq '.body'` to fetch the `hq:plan` issue body. Parse the `## Verification` section and use the unchecked items as the checklist
2. **User instruction** — if the user specifies items, use those
3. **Ask the user** — if neither is available, ask what to verify

Useful patterns:

- **CRUD**: Create → Read → Update → Delete, confirm each step with `snapshot`
- **Navigation**: `click` links, `snapshot` to verify routing
- **Visual checks**: Use `screenshot` for color/layout verification

### Phase 5: Cleanup & Report

1. Close the browser session: `npx @playwright/cli -s=verify close`
2. Stop the background dev server
3. **Output feedback files** for each failed item (see Feedback Output below)
4. Report summary to the user:

| # | Item | Result | Notes |
|---|------|--------|-------|
| 1 | ...  | PASS/FAIL | ... |

If all items pass, no FB files are generated.

## Feedback Output

For each failed verification item, create a FB file following the workflow rules (directory, numbering, format). Set `source` and `plan` from `focus.md` in your Claude Code memory directory (fallback: `.hq/tasks/<branch>/context.md`).

Additionally, capture a screenshot at the moment of failure and save to `.hq/tasks/<branch>/feedbacks/screenshots/` with naming `FB001.png`, `FB002.png`, etc. Reference the screenshot path in the FB file's **Evidence** field.

## Rules

- Always use the **agent port**, never the user's default dev port
- Always use session flag `-s=verify` for all CLI commands
- Use `snapshot` to get element refs before interacting — never guess refs
- Take `screenshot` when visual verification is needed
- Use `Read` tool to view saved screenshots
- If something is unclear, ask the user — do not guess or give up
