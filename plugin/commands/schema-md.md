# schema-md: Drizzle schema.ts → docs/schema.md

Generate a structured DB schema document from Drizzle ORM schema definitions.

## Input / Output

- **Input**: Drizzle schema definition files only (`.ts` files containing `pgTable`, etc.)
- **Output**: `docs/schema-YYYYMMDD-HHMMSS.md` (timestamped with local datetime at execution)

**Important**: Never reference existing `docs/schema*.md` files. Always generate from scratch using only the schema definition files as input.

Locate the Drizzle schema definition files. Typical paths:
- `src/db/schema.ts` (single file)
- `src/db/schema/*.ts` (split layout)
- `apps/*/src/db/schema.ts` (monorepo)

If not found, ask the user.

## Step 1: Schema Analysis

Extract the following from the schema definition files:

- Table names (first argument of `pgTable('table_name', ...)`)
- Column definitions (name, type, constraint chain)
- PK (`.primaryKey()` / `primaryKey({ columns: [...] })`)
- FK (`.references(() => table.column, { onDelete: '...' })` / `foreignKey({ ... })`)
- UNIQUE (`.unique()` / `unique().on(...)`)
- INDEX (`index().on(...)`)
- DEFAULT (`.default(value)` / `.defaultNow()` / `.$defaultFn(...)`)

## Step 2: Category Classification

Group all tables into domain-meaningful categories.

**Classification approach:**
- Use comment separators in schema.ts (`// --- xxx ---`, etc.) as hints
- Cluster tightly-coupled tables based on FK dependency graphs
- Group tables sharing common patterns (same parent FK, similar column structure)
- Target 1–10 tables per category. Split if too many, merge if too few

**Attributes for each category:**
- **ID**: 2-letter uppercase abbreviation (e.g., `AU`, `TN`, `MD`). Choose a concise domain abbreviation
- **Label**: Short English name (e.g., `Auth`, `Tenant`, `Master`)
- **Description**: One-line description in Japanese

## Step 3: Table ID Assignment

Assign each table an ID in the format `CategoryID-SequenceNumber` (e.g., `AU-01`, `TN-02`).

Sequencing rules:
- Parent tables come before child tables within a category (FK dependency order)
- Junction tables are placed after both endpoint tables
- Zero-padded 2-digit numbers (01–99)

## Step 4: Generate docs/schema-YYYYMMDD-HHMMSS.md

Output in the following fixed format.

---

### Output Format

````markdown
# DB Schema

## Overview

(1–2 sentence summary of the entire schema. Include total table count, category count, ORM, and DB.)

### Table ID System

Each table is assigned a category prefix + sequence number ID for use as a shared reference in discussions.

| Prefix | Category | Table Count | Description |
| --- | --- | --- | --- |
| XX | Label | N | Japanese description |
(rows for all categories)

## Tables by Category

| ID | Table Name | Summary |
| --- | --- | --- |
| **XX - Label** | | |
| XX-01 | table_name | Concise Japanese summary |
(all tables; bold header row separates each category)

## Key Design Patterns

(Explain important design patterns for understanding the schema. Consider:)
(- Domain-specific structures and unique constraint purposes)
(- Common patterns such as tables with shared column structures)
(- Multi-tenant or scoping structures)
(- FK on_delete strategy differences — intent behind CASCADE vs SET NULL)
(Reference table IDs in parentheses, e.g., `chunk_type (MD-06)`)

## Category Details

---

### XX - Label

(1–2 line supplementary description of the category if needed)

#### XX-01: table_name

| Column | Type | Constraints |
| --- | --- | --- |
| column_name | type | constraint info |

- **PK**: `(col1, col2)` (for composite PK)
- **UNIQUE**: `(col1, col2)` (for composite UNIQUE)
- **INDEX**: `col1` (if indexed)
- Additional notes (if design intent needs explanation)

(separate categories with `---`)

---

## Relation Diagram

```
parent_table (XX-01)
 ├─< child_table (XX-02)        fk_column → parent.id          CASCADE
 ├──○ nullable_child (XX-03)    fk_column → parent.id          SET NULL
 └─< another_child (XX-04)      fk_column → parent.id          CASCADE
```

(Build trees rooted at major parent tables. Cover all FK relationships.)

**Rule: Always write from the parent table's perspective.** List child table FKs under the referenced parent using `─<` or `──○`. Do not use child-perspective N:1 notation (`──`). This unifies notation to two symbols and eliminates directional ambiguity.

Legend: `─<` 1:N (CASCADE)  `──○` 1:N (SET NULL)
````

---

### Constraint Column Conventions

| schema.ts expression | Constraint column |
|---|---|
| `.primaryKey()` | `PK` |
| `.$defaultFn(() => crypto.randomUUID())` | `PK, UUID auto` |
| `.notNull()` | `NOT NULL` |
| (no `.notNull()`, not PK) | (blank = nullable) |
| `.unique()` | `UNIQUE` |
| `.default(value)` | `DEFAULT value` |
| `.defaultNow()` | `DEFAULT now()` |
| `.$onUpdate(() => new Date())` | `auto update` (alongside DEFAULT) |
| `.references(() => t.id, { onDelete: 'cascade' })` | `FK → t(id) CASCADE` |
| `.references(() => t.id, { onDelete: 'set null' })` | `FK → t(id) SET NULL` |

Use comma-separated notation when multiple constraints overlap (e.g., NOT NULL + DEFAULT + FK).

### Language Rules

- Table summaries, category descriptions, key design patterns: use the user's language (match the language they are using in the conversation)
- Column constraints: English abbreviations (PK, FK, NOT NULL, UNIQUE, CASCADE, SET NULL, DEFAULT)
- For tables originating from external libraries, include links to official documentation
