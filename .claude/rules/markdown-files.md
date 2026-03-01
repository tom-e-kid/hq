# Markdown File Handling Rules

## Frontmatter

`.md` files in this repository use YAML frontmatter. Use metadata like `purpose`, `summary`, `tags` for efficient information retrieval.

## Progressive Reading Strategy

When you need to understand file contents, read incrementally:

1. **Read frontmatter first** — check `summary`, `tags`, etc. before opening the full body
2. **Stop if frontmatter suffices** — e.g., "What did I do in October?" can be answered from `summary` alone
3. **Read the body only when needed** — e.g., "What did I do on October 15?" requires scanning daily entries

## Handling Multiple Files

When searching across multiple `.md` files, do not read all bodies at once:

1. Collect frontmatter from candidate files
2. Narrow down targets based on frontmatter content
3. Read the body of narrowed-down files only
