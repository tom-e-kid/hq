import { categoryColor } from '../constants.ts'
import { COL_WIDTH, type LayoutTable } from '../layout.ts'
import type { Schema } from '../parser.ts'

interface Props {
  schema: Schema
  tables: LayoutTable[]
}

export function CategoryHeaders({ schema, tables }: Props) {
  const catPositions = new Map<string, number>()
  for (const lt of tables) {
    if (!catPositions.has(lt.table.category)) {
      catPositions.set(lt.table.category, lt.x)
    }
  }

  return (
    <>
      {schema.categories.map((cat) => {
        const x = catPositions.get(cat.id)
        if (x === undefined) return null
        return (
          <g key={cat.id}>
            <text
              x={x + COL_WIDTH / 2}
              y={40}
              textAnchor="middle"
              fill={categoryColor(cat.id)}
              fontSize={16}
              fontWeight={700}
              fontFamily="system-ui, sans-serif"
            >
              {cat.id} - {cat.label}
            </text>
            <text
              x={x + COL_WIDTH / 2}
              y={58}
              textAnchor="middle"
              fill="#64748b"
              fontSize={11}
              fontFamily="system-ui, sans-serif"
            >
              {cat.description}
            </text>
          </g>
        )
      })}
    </>
  )
}
