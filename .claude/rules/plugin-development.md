# Plugin Development Rules

## Directory Structure

The Claude Code plugin for this repo uses the following layout:

```
.claude-plugin/
  plugin.json          # Plugin manifest (component registration)
plugin/
  skills/              # Skills (SKILL.md)
  commands/            # Commands (*.md)
```

## Registering Components

Plugin.json uses directory-based auto-discovery (`"skills": "./plugin/skills"`).
New skills/commands placed in the correct directory are discovered automatically.
Ensure the directory paths in plugin.json are correct when adding new component types.

## Verification

After adding or renaming a command/skill, verify it appears in the session's skill list.
