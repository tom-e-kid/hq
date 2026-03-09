import { categoryColor } from '../constants.ts'
import type { Category } from '../parser.ts'

interface Props {
  categories: Category[]
  activeCategories: Set<string>
  onToggleCategory: (catId: string) => void
}

export function Header({ categories, activeCategories, onToggleCategory }: Props) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 20, marginBottom: 14 }}>
      <div>
        <div
          style={{
            color: '#475569',
            fontSize: 9.5,
            letterSpacing: '0.15em',
            textTransform: 'uppercase',
          }}
        >
          chunk · PostgreSQL
        </div>
        <div
          style={{
            color: '#e2e8f0',
            fontSize: 17,
            fontWeight: 700,
            marginTop: 1,
            letterSpacing: '-0.02em',
          }}
        >
          DB Schema · ER Diagram
        </div>
      </div>
      <div
        style={{
          flex: 1,
          height: 1,
          background: 'linear-gradient(90deg,#1e293b 60%,transparent)',
        }}
      />
      <div style={{ display: 'flex', gap: 5 }}>
        {categories.map((cat) => {
          const isActive = activeCategories.has(cat.id)
          const color = categoryColor(cat.id)
          return (
            <button
              key={cat.id}
              onClick={() => onToggleCategory(cat.id)}
              style={{
                background: isActive ? color + '20' : 'transparent',
                border: `1px solid ${isActive || activeCategories.size === 0 ? color : color + '40'}`,
                borderRadius: 4,
                color: isActive || activeCategories.size === 0 ? color : color + '70',
                padding: '3px 9px',
                fontSize: 9.5,
                cursor: 'pointer',
                letterSpacing: '0.05em',
                transition: 'all 0.15s',
                fontFamily: 'inherit',
              }}
            >
              {cat.id} <span style={{ opacity: 0.7 }}>{cat.label}</span>
            </button>
          )
        })}
      </div>
    </div>
  )
}
