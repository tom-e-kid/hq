import type { Schema, Table } from './parser.ts'

// ── Layout constants ───────────────────────────────────────
const COL_WIDTH = 280
const COL_GAP = 80
const TABLE_HEADER_H = 36
const ROW_H = 22
const TABLE_GAP = 24
const PADDING_TOP = 80
const PADDING_LEFT = 40

// ── Types ──────────────────────────────────────────────────
export interface LayoutTable {
  table: Table
  x: number
  y: number
  width: number
  height: number
}

export interface LayoutResult {
  tables: LayoutTable[]
  width: number
  height: number
}

// ── Compute table box height ───────────────────────────────
function tableHeight(t: Table): number {
  return TABLE_HEADER_H + t.columns.length * ROW_H + 8
}

// ── Auto-layout ────────────────────────────────────────────
export function computeLayout(schema: Schema): LayoutResult {
  const categoryOrder = schema.categories.map((c) => c.id)
  const byCategory = new Map<string, Table[]>()

  for (const cat of categoryOrder) {
    byCategory.set(cat, [])
  }
  for (const t of schema.tables) {
    const list = byCategory.get(t.category)
    if (list) list.push(t)
  }

  const layoutTables: LayoutTable[] = []
  let maxBottom = 0

  for (let colIdx = 0; colIdx < categoryOrder.length; colIdx++) {
    const catId = categoryOrder[colIdx]!
    const tables = byCategory.get(catId) ?? []
    const x = PADDING_LEFT + colIdx * (COL_WIDTH + COL_GAP)
    let y = PADDING_TOP

    for (const t of tables) {
      const h = tableHeight(t)
      layoutTables.push({ table: t, x, y, width: COL_WIDTH, height: h })
      y += h + TABLE_GAP
    }
    if (y > maxBottom) maxBottom = y
  }

  const totalWidth =
    PADDING_LEFT +
    categoryOrder.length * COL_WIDTH +
    (categoryOrder.length - 1) * COL_GAP +
    PADDING_LEFT
  const totalHeight = maxBottom + 40

  return { tables: layoutTables, width: totalWidth, height: totalHeight }
}

// ── Re-export constants for rendering ──────────────────────
export { TABLE_HEADER_H, ROW_H, COL_WIDTH }
