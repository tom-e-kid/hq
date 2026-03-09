import { categoryColor } from '../constants.ts'
import type { Schema } from '../parser.ts'

interface Props {
  tableName: string
  schema: Schema
  svgWidth: number
}

export function InfoBadge({ tableName, schema, svgWidth }: Props) {
  const t = schema.tables.find((tb) => tb.name === tableName)
  if (!t) return null

  const cat = schema.categories.find((c) => c.id === t.category)
  const color = categoryColor(t.category)

  return (
    <g transform={`translate(${svgWidth - 240}, 20)`}>
      <rect
        width={220}
        height={30}
        rx={5}
        fill="#0c1220"
        stroke={color}
        strokeWidth={1}
        strokeOpacity={0.5}
      />
      <text x={10} y={14} fill={color} fontSize={8.5} fontWeight={700} fontFamily="monospace">
        {t.category} · {cat?.label}
      </text>
      <text x={10} y={24} fill="#94a3b8" fontSize={10} fontFamily="monospace">
        {t.id}: {t.name}
      </text>
    </g>
  )
}
