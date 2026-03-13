# HQ

Centralized management of monthly logs, project info, and knowledge base — designed for AI agent collaboration.

All data is stored as plain Markdown with YAML frontmatter. Both humans and AI agents can read and write it directly.

## Components

### plugin/ — Claude Code Plugin

A Claude Code plugin that provides skills and commands for HQ operations.

**Skills:**

| Skill | Description |
|-------|-------------|
| `dev` | Development workflow — branch management, task tracking, plan-then-implement cycle |
| `ops` | HQ operations — TODO and notes CRUD via `hq` CLI |
| `dev-ios` | iOS/Xcode build configuration and verification |
| `reviewer` | Code review standards — review criteria, security alerts, reporting format |

**Commands:**

| Command | Description |
|---------|-------------|
| `/hq:pr` | Create or update a GitHub Pull Request |
| `/hq:code-review` | Review code changes on the current branch (includes security alert scan) |
| `/hq:accept-review` | Evaluate code review results, commit accepted fixes, and extract follow-up issues |
| `/hq:estimate` | Collect requirements and organize work item estimates with risks and blockers |
| `/hq:schema-md` | Generate Markdown documentation from Drizzle ORM schema definitions |
| `/hq:schema-yaml` | Convert schema Markdown to `chunk-schema/v1` YAML (for schema-visualizer) |
| `/hq:memory` | Record a lesson learned to memory |
| `/hq:close` | Clean up completed task files and remove WIP entries |

### apps/ — Standalone Web Applications

#### schema-visualizer

An interactive ER diagram viewer for `chunk-schema/v1` YAML files, built with React and Vite.

- Load schema from `docs/schema.yaml` or via `?schema=` query parameter
- Click tables to highlight relations, scroll to zoom, drag to pan
- Filter tables by category

```bash
cd apps/schema-visualizer
bun install
bun run dev
```

### tools/ — HQ CLI

A Go-based CLI and TUI dashboard built with [Bubble Tea](https://github.com/charmbracelet/bubbletea).

The TUI dashboard displays a live, interactive overview in the terminal:

- **Milestones** — upcoming deadlines with remaining days
- **WIP** — tasks currently being worked on
- **Open Tasks** — unchecked items grouped by project
- **Monthly Summary** — hours breakdown by client
- **Activity Calendar** — heatmap of daily work hours

**CLI Subcommands:**

```
hq                          Launch TUI dashboard (default)
hq tasks                    List, add, or complete tasks
hq notes                    List, view, add, or copy notes
hq milestones               List, add, or complete milestones
hq monthly [YYYY.MM]        Show monthly time summary
```

Common flags: `--inbox`, `--project <org/project>`, `--role <role>`, `--json`, `--all`

**Build & Install:**

```bash
mise run build              # Build to tools/bin/hq
mise run install            # Build and install to ~/.local/bin/hq
```

### AGENTS.md — Codex Reviewer Demo

`AGENTS.md` is a demo configuration for using [OpenAI Codex](https://openai.com/index/openai-codex/) as an automated code reviewer. It inlines review criteria and policies so that it works standalone in any project. The canonical source for review standards is `plugin/skills/reviewer/SKILL.md`; AGENTS.md is kept in sync manually.

## Data Directory (`db/`)

HQ reads data from a `db/` directory. The path is resolved in this order:

1. `--path` flag
2. `~/.hq/settings.json` → `data_dir`
3. Walk up from cwd looking for a directory containing `db/`

### Expected Structure

```
db/
├── projects/
│   ├── _milestones.md             # Shared milestones (checkbox list with dates/recurring rules)
│   ├── _words.md                  # Word ticker entries (bullet list displayed in TUI header)
│   ├── <org>/
│   │   └── <project>/
│   │       ├── README.md          # Project metadata (frontmatter: title, repo, tags)
│   │       ├── tasks.md           # Project tasks (checkbox list)
│   │       └── notes/             # Project notes (one .md per note)
│   └── ...
├── inbox/
│   ├── tasks.md                   # Inbox tasks (no project association)
│   └── notes/                     # Inbox notes
└── logs/
    └── YYYY/
        └── MM.md                  # Monthly log (time entries + daily journal)
```

### Settings

**`~/.hq/settings.json`** — Global configuration:

```json
{
  "data_dir": "/path/to/hq/db",
  "sections": {
    "monthly": false
  }
}
```

`sections` controls dashboard section visibility. Set a section to `false` to hide it. Available sections: `milestones`, `wip`, `todo`, `monthly`. Omitted sections default to visible.

**`<project>/.hq/settings.json`** — Per-project configuration:

```json
{
  "base_branch": "main",
  "resources": [
    { "name": "tasks.md", "type": "tasks", "role": "tasks" },
    { "name": "backlog.md", "type": "tasks", "role": "backlog" },
    { "name": "notes", "type": "notes", "role": "notes" }
  ]
}
```

`resources` lets you define multiple task files or notes directories per project, each with a `role` that can be targeted via `--role`.

## Task & Milestone Syntax

Tasks and milestones are written as Markdown checkbox lines in `tasks.md` or `_milestones.md`.

### Basic

```markdown
- [ ] Undated task
- [x] Completed task
```

### With Deadline

Prefix with `YYYY-MM-DD`:

```markdown
- [ ] 2026-03-15 Submit report
- [ ] 2026-04-01 Release v2.0
```

### Recurring

Use `@` prefixed rules. The next occurrence is calculated automatically.

```markdown
# Every month on the 10th
- [ ] @monthly 10 Pay invoice

# Last day of every month
- [ ] @month-end Billing

# Every year on March 15
- [ ] @yearly 03-15 Tax filing

# Every week on Monday
- [ ] @weekly mon Team standup
```

**Supported rules:**

| Rule | Format | Example |
|------|--------|---------|
| `@monthly` | `@monthly <day>` | `@monthly 10` → 10th of each month |
| `@month-end` | `@month-end` | Last day of each month (handles 28/29/30/31) |
| `@yearly` | `@yearly <MM-DD>` | `@yearly 03-15` → March 15 each year |
| `@weekly` | `@weekly <dow>` | `@weekly mon` → every Monday |

Day-of-week values: `sun`, `mon`, `tue`, `wed`, `thu`, `fri`, `sat`

### WIP Tracking

`~/.hq/wip.md` tracks work-in-progress tasks across all projects. The `dev` skill automatically adds entries when starting a new work branch.

```markdown
---
purpose: Track in-progress tasks
---

- org/project: Task description (branch: feat/some-feature)
- org/another: Another task (branch: fix/bug-123)
- org/solo: Task without branch
```

Each line follows the format: `- <org/project>: <description> (branch: <branch>)`

The `(branch: ...)` suffix is optional. Entries are displayed in the TUI dashboard's WIP section and should be removed manually when the work is complete.

### Monthly Log Format

`db/logs/YYYY/MM.md` contains YAML frontmatter and daily sections:

```markdown
---
title: "2026-03 Monthly Log"
month: "2026-03"
---

## 20260301

### Results

T:

- ClientA:Development: 3.0
- ClientA:Meeting: 1.0
- ClientB:Research: 2.5
```

Time entries follow the format `- Client:Category: hours`.
