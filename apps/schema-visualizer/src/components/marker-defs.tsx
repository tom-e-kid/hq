import { categoryColor } from '../constants.ts'
import type { Schema } from '../parser.ts'

interface Props {
  categories: Schema['categories']
}

export function MarkerDefs({ categories }: Props) {
  return (
    <defs>
      <pattern id="dots" x="0" y="0" width="22" height="22" patternUnits="userSpaceOnUse">
        <circle cx="11" cy="11" r="0.65" fill="#111827" />
      </pattern>
      {categories.map((cat) => (
        <marker
          key={cat.id}
          id={`arr-${cat.id}`}
          markerWidth="7"
          markerHeight="7"
          refX="5.5"
          refY="3"
          orient="auto"
          markerUnits="strokeWidth"
        >
          <path d="M0,0 L0,6 L7,3 z" fill={categoryColor(cat.id)} opacity={0.85} />
        </marker>
      ))}
      <marker
        id="arr-null"
        markerWidth="7"
        markerHeight="7"
        refX="5.5"
        refY="3"
        orient="auto"
        markerUnits="strokeWidth"
      >
        <path d="M0,0 L0,6 L7,3 z" fill="#475569" opacity={0.7} />
      </marker>
    </defs>
  )
}
