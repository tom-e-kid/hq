import { categoryColor } from '../constants.ts'
import type { LayoutTable } from '../layout.ts'

interface Props {
  tables: LayoutTable[]
  catFilter: Set<string>
}

export function CategoryZones({ tables, catFilter }: Props) {
  const zones = new Map<string, { minX: number; minY: number; maxX: number; maxY: number }>()
  for (const lt of tables) {
    const cat = lt.table.category
    const existing = zones.get(cat)
    if (existing) {
      existing.minX = Math.min(existing.minX, lt.x)
      existing.minY = Math.min(existing.minY, lt.y)
      existing.maxX = Math.max(existing.maxX, lt.x + lt.width)
      existing.maxY = Math.max(existing.maxY, lt.y + lt.height)
    } else {
      zones.set(cat, {
        minX: lt.x,
        minY: lt.y,
        maxX: lt.x + lt.width,
        maxY: lt.y + lt.height,
      })
    }
  }

  return (
    <>
      {Array.from(zones.entries()).map(([cat, z]) => {
        const color = categoryColor(cat)
        const dimmed = catFilter.size > 0 && !catFilter.has(cat)
        return (
          <rect
            key={cat}
            x={z.minX - 12}
            y={z.minY - 16}
            width={z.maxX - z.minX + 24}
            height={z.maxY - z.minY + 32}
            rx={10}
            fill={color + '06'}
            stroke={color + '15'}
            strokeWidth={1}
            opacity={dimmed ? 0.3 : 1}
            style={{ transition: 'opacity 0.15s' }}
          />
        )
      })}
    </>
  )
}
