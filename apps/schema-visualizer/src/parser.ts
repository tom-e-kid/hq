import { parse } from 'yaml'

// ── Raw YAML types ─────────────────────────────────────────
interface RawFK {
  table: string
  column: string
  on_delete: string
}

interface RawColumn {
  name: string
  type: string
  pk?: boolean
  unique?: boolean
  nullable?: boolean
  default?: string
  fk?: RawFK
}

interface RawCompositeFK {
  columns: string[]
  references: { table: string; columns: string[] }
  on_delete: string
}

interface RawIndex {
  columns: string[]
}

interface RawTable {
  id: string
  name: string
  category: string
  columns: RawColumn[]
  pk?: string[]
  unique?: string[][]
  indexes?: RawIndex[]
  foreign_keys?: RawCompositeFK[]
}

interface RawRelation {
  from: string
  to: string
  type: string
  composite?: boolean
  column?: string
}

interface RawCategory {
  id: string
  label: string
  description: string
}

interface RawSchema {
  format: string
  database: string
  categories: RawCategory[]
  tables: RawTable[]
  relations: RawRelation[]
}

// ── Parsed types (exported for layout / App) ───────────────
export interface Column {
  name: string
  type: string
  pk: boolean
  fk: boolean
  unique: boolean
  nullable: boolean
  jsonb: boolean
  default?: string
  fkTarget?: { table: string; column: string; onDelete: string }
}

export interface Table {
  id: string
  name: string
  category: string
  columns: Column[]
  compositePK?: string[]
  compositeUniques: string[][]
  indexes: string[][]
  compositeFKs: {
    columns: string[]
    refTable: string
    refColumns: string[]
    onDelete: string
  }[]
}

export interface Relation {
  from: string
  to: string
  type: string
  composite: boolean
  column?: string
}

export interface Category {
  id: string
  label: string
  description: string
}

export interface Schema {
  format: string
  database: string
  categories: Category[]
  tables: Table[]
  relations: Relation[]
}

// ── Parser ─────────────────────────────────────────────────
export function parseSchema(yamlText: string): Schema {
  const raw = parse(yamlText) as RawSchema

  const tables: Table[] = raw.tables.map((t) => {
    const columns: Column[] = t.columns.map((c) => ({
      name: c.name,
      type: c.type,
      pk: c.pk ?? false,
      fk: !!c.fk,
      unique: c.unique ?? false,
      nullable: c.nullable ?? false,
      jsonb: c.type === 'jsonb',
      default: c.default,
      fkTarget: c.fk
        ? {
            table: c.fk.table,
            column: c.fk.column,
            onDelete: c.fk.on_delete,
          }
        : undefined,
    }))

    return {
      id: t.id,
      name: t.name,
      category: t.category,
      columns,
      compositePK: t.pk,
      compositeUniques: t.unique ?? [],
      indexes: (t.indexes ?? []).map((i) => i.columns),
      compositeFKs: (t.foreign_keys ?? []).map((fk) => ({
        columns: fk.columns,
        refTable: fk.references.table,
        refColumns: fk.references.columns,
        onDelete: fk.on_delete,
      })),
    }
  })

  const relations: Relation[] = raw.relations.map((r) => ({
    from: r.from,
    to: r.to,
    type: r.type,
    composite: r.composite ?? false,
    column: r.column,
  }))

  return {
    format: raw.format,
    database: raw.database,
    categories: raw.categories,
    tables,
    relations,
  }
}
