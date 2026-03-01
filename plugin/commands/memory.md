---
description: "Record a lesson from user feedback to memory"
---

Record a lesson learned from the user's recent correction or feedback. Follow these steps strictly.

## Steps

### 1. Resolve git root

Run `git rev-parse --show-toplevel` and store the result as `GIT_ROOT`.

### 2. Determine save target

Check the user's intent from the conversation context or arguments:

- If the user said "global", "cross-project", or similar → target is `~/.hq/memory.md`
- Otherwise → target is `$GIT_ROOT/.hq/memory.md`

### 3. Identify the lesson

Look at the recent conversation for the user's correction or feedback. Extract:

- **What went wrong** — the mistake or suboptimal approach
- **The rule** — the principle to prevent recurrence

If unclear what the user wants to record, use AskUserQuestion to clarify.

### 4. Format the entry

Format as:

```markdown
## YYYY-MM-DD: <short title>

**問題**: <what went wrong>
**ルール**: <the rule to prevent recurrence>
```

Use the same language as the user's correction.

### 5. Append to memory file

1. If the target file does not exist, create it with frontmatter:
   ```markdown
   ---
   purpose: Memory log — lessons learned and rules to follow
   ---
   ```
2. Append the formatted entry to the end of the file

### 6. Confirm

Report what was saved and where (e.g., "Saved to `.hq/memory.md`" or "Saved to `~/.hq/memory.md` (global)").
