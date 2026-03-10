# schema-yaml: docs/schema-*.md → docs/schema-*.yaml

Generate a `chunk-schema/v1` compliant YAML file from a schema document (`.md`).

## Input / Output

- **Input**: File path can be specified as an argument. If omitted, automatically selects the most recent `docs/schema-YYYYMMDD-HHMMSS.md` by timestamp
- **Output**: Same filename as input with `.yaml` extension (e.g., `docs/schema-20260309-164352.md` → `docs/schema-20260309-164352.yaml`)

## Procedure

1. Identify the input file (argument or latest `docs/schema-*.md`)
2. Read the input file and extract table structures and relation information
3. Refer to `${CLAUDE_PLUGIN_ROOT}/apps/schema-visualizer/README.md` "Input Spec — chunk-schema/v1" (L29-124) as the format specification
4. Cross-check column nullable/default details against the Drizzle schema definition files in the project
5. Generate a `chunk-schema/v1` compliant YAML and write to the output file

## Format Specification Reference

**Strictly follow the `chunk-schema/v1` spec defined in `${CLAUDE_PLUGIN_ROOT}/apps/schema-visualizer/README.md` L29-124.**

Key structure (see README.md for full details):
- Top level: `format`, `database`, `categories`, `tables`, `relations`
- categories: `id`, `label`, `description`
- tables: `id`, `name`, `category`, `columns`, `pk` (composite), `unique` (composite), `indexes`, `foreign_keys` (composite)
- columns: `name`, `type`, `pk`, `unique`, `nullable`, `default`, `fk`
- relations: `from`, `to`, `type`, `composite`, `column`

## YAML Generation Rules

### nullable

- Column without `.notNull()` AND not a PK → `nullable: true`
- Default is NOT NULL (`false`), so do not write `nullable` for NOT NULL columns

### default

- `.$defaultFn(() => crypto.randomUUID())` → `default: uuid_auto`
- `.defaultNow()` → `default: now`
- `.default(value)` → `default: "value"` (string, number, or boolean as-is)

### FK

- Single-column FK: `.references(() => table.column, { onDelete: 'xxx' })` → column-level `fk:`
- Composite FK: `foreignKey({ columns: [...], foreignColumns: [...] })` → table-level `foreign_keys:`
- `on_delete` values: `cascade` → `CASCADE`, `set null` → `SET_NULL`

### PK

- Single PK: `.primaryKey()` → column-level `pk: true`
- Composite PK: `primaryKey({ columns: [...] })` → table-level `pk: [col1, col2]`

### relations Section

- Cross-reference the input `.md` relation diagram with schema.ts FK definitions
- Each relation: `from` = table holding the FK, `to` = referenced table
- `type`: `CASCADE` or `SET_NULL`
- When multiple FKs exist between the same tables, use `column:` to disambiguate
- For composite FKs, add `composite: true`

## YAML Style Guide

- Insert comment separators per category: `# ── AU - Auth ──────...`
- Use flow style for fk: `fk: { table: user, column: id, on_delete: CASCADE }`
- Group relations with comments: `# AU → user`, `# TN → organization`, etc.
- Use 2-space indentation

## Language

- Descriptions (category `description`, etc.) should use the user's language (match the language they are using in the conversation)

## Important Notes

- If input `.md` conflicts with schema.ts, schema.ts is the source of truth
- If tables/columns exist in schema.ts but not in the input `.md`, add them
- Derive indexes from `index().on(column)` in schema.ts (check schema.ts even if not in schema.md)
