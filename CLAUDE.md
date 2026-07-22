# HQ

A development hub for AI-assisted workflows across multiple projects.

## Repository Overview

- **.claude-plugin/** — Plugin manifest (`plugin.json`): defines commands, agents, and skills paths
- **plugin/v3/** — Active plugin version (commands, agents, skills)
- **plugin/v2/** — Legacy — frozen, do not modify
- **plugin/v1/** — Legacy — do not modify

CLI tools formerly under `tools/` were split out to [github.com/tom-e-kid/hqdb](https://github.com/tom-e-kid/hqdb) (commit `7ab6454`). This repository has no build step — it is plugin (markdown) only.

## Plugin Development

- For plugin structure (plugin.json, commands, agents, skills, hooks), always refer to the official Claude Code documentation: https://docs.anthropic.com/en/docs/claude-code/plugins

## Dogfooding

This repository develops its own plugin and uses that same plugin (the `hq:*` commands, agents, and skills under `plugin/v3/`) to drive its own development workflow. Changes to the workflow are exercised here first.

The workflow rules live under **`plugin/v3/rules/`**: `workflow.md` (cross-cutting source of truth, read on every invocation) plus the stage protocols `draft-protocol.md` / `execute-protocol.md` (full phase specifications, Read-and-followed by the loop and its agents), and `copilot-protocol.md` (the post-PR review-thread round spec, shared by `/hq:copilot` and `/hq:copilot-loop`). The pipeline has a single entry command — `commands/loop.md` (`/hq:loop`, Stages 0–7 + root judgments J1–J8) — with `/hq:copilot` / `/hq:copilot-loop` and `/hq:archive` as post-PR tools. There is no copy, no distribution step, and no consumer-side build artifact: editing these files is the change.

## Loop Value — standing evaluation point

Whether `hq:loop` earns its wall-clock cost over bare LLM instruction (direct implement → PR, no structured review) is a **permanently open question**, answered with telemetry (`~/.hq/events.jsonl`), never with impressions. When discussing loop design changes, bring this lens.

- Established (as of 2026-07): review-stage findings are ~63% fixed pre-PR, including High/Critical ones; executors self-report ~0 defects on fresh builds (the builder does not detect its own mistakes — review is the only detection surface); review + triage consume ~50% of run wall-clock; value is a function of the diff profile, not of the loop — mature repos with mostly-mechanical diffs yield near-zero findings, greenfield / engine-heavy repos yield the most.
- Open: whether newer model generations shrink the review yield. The `run_start` `model` payload field (added 2026-07) makes this measurable — re-evaluate as data accumulates.
- Method: compare High/Critical detection rate and slot 6/7 timings by model and by repo. Residual-based comparisons (e.g. external reviewer comments on the shipped PR) measure survivorship only — findings fixed pre-PR are invisible there — and must not be used as evidence that review adds nothing.

## Language Policy

- Agent instructions (CLAUDE.md, rules, skills, commands): English
- User-facing documents: follow the user's language
- Session conversation: follow the user's language
