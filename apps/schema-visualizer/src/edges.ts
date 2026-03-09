import type { LayoutTable } from './layout.ts'
import type { Relation } from './parser.ts'

// ── Types ───────────────────────────────────────────────────
export interface EdgeDef {
  relation: Relation
  x1: number
  y1: number
  x2: number
  y2: number
  fromTable: string
  toTable: string
  fromCategory: string
}

// ── Edge computation ────────────────────────────────────────
export function computeEdges(relations: Relation[], tableMap: Map<string, LayoutTable>): EdgeDef[] {
  return relations
    .map((r) => {
      const from = tableMap.get(r.from)
      const to = tableMap.get(r.to)
      if (!from || !to) return null

      const fromCX = from.x + from.width / 2
      const fromCY = from.y + from.height / 2
      const toCX = to.x + to.width / 2
      const toCY = to.y + to.height / 2

      let x1: number, y1: number, x2: number, y2: number

      const dx = Math.abs(toCX - fromCX)
      const dy = Math.abs(toCY - fromCY)

      if (dx >= dy) {
        if (toCX > fromCX) {
          x1 = from.x + from.width
          x2 = to.x
        } else {
          x1 = from.x
          x2 = to.x + to.width
        }
        y1 = fromCY
        y2 = toCY
      } else {
        if (toCY > fromCY) {
          y1 = from.y + from.height
          y2 = to.y
        } else {
          y1 = from.y
          y2 = to.y + to.height
        }
        x1 = fromCX
        x2 = toCX
      }

      return {
        relation: r,
        x1,
        y1,
        x2,
        y2,
        fromTable: r.from,
        toTable: r.to,
        fromCategory: from.table.category,
      }
    })
    .filter((e): e is EdgeDef => e !== null)
}

// ── Edge path (cubic bezier) ────────────────────────────────
export function edgePath(e: EdgeDef): string {
  const dx = Math.abs(e.x2 - e.x1)
  const dy = Math.abs(e.y2 - e.y1)

  if (dx >= dy) {
    const cp = Math.max(dx * 0.45, 50)
    const sx = e.x2 > e.x1 ? 1 : -1
    return `M${e.x1},${e.y1} C${e.x1 + sx * cp},${e.y1} ${e.x2 - sx * cp},${e.y2} ${e.x2},${e.y2}`
  }

  const cp = Math.max(dy * 0.45, 30)
  const sy = e.y2 > e.y1 ? 1 : -1
  return `M${e.x1},${e.y1} C${e.x1},${e.y1 + sy * cp} ${e.x2},${e.y2 - sy * cp} ${e.x2},${e.y2}`
}
