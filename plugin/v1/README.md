# Plugin v1 (legacy — frozen)

Command-driven workflow with orchestration layer. Do not modify.

The `/hq:dev` command acts as an orchestration layer, composing independent skills:

```
/hq:dev [platform]              ← command (orchestration)
    ├── dev-core/SKILL.md       ← always loaded (branch management, planning, commit conventions)
    └── dev-<platform>/SKILL.md ← loaded by platform detection or argument
```

- **Command** (`dev.md`): Explicitly reads both skills via the Read tool and delegates to the dev-core workflow
- **dev-core**: Platform-agnostic workflow. Does not assume any platform skill exists (works standalone)
- **dev-\<platform\>**: Platform-specific setup and build rules. Does not reference dev-core

No direct references exist between skills — adding or removing a platform skill only requires updating the detection table in the command.

**Skills:**

| Skill      | Description                                                                           |
| ---------- | ------------------------------------------------------------------------------------- |
| `dev-core` | Platform-agnostic development workflow — branch management, task tracking, conventions |
| `dev-ios`  | iOS/Xcode build, run, and environment configuration                                   |
| `reviewer` | Code review standards — review criteria, security alerts, reporting format            |
| `ops`      | HQ operations — TODO and notes CRUD via `hq` CLI                                      |

**Commands:**

| Command             | Description                                                                       |
| ------------------- | --------------------------------------------------------------------------------- |
| `/hq:dev`           | Start development (loads dev-core + platform skill)                               |
| `/hq:pr`            | Create or update a GitHub Pull Request                                            |
| `/hq:code-review`   | Review code changes on the current branch (includes security alert scan)          |
| `/hq:accept-review` | Evaluate code review results, commit accepted fixes, and extract follow-up issues |
| `/hq:estimate`      | Collect requirements and organize work item estimates with risks and blockers     |
| `/hq:close`         | Archive task files to `.hq/tasks/done/` and clean up branches                    |
