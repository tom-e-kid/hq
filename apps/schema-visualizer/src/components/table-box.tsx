import { categoryColor, columnDotColor, columnTextColor, DIM_OPACITY } from '../constants.ts'
import { ROW_H, TABLE_HEADER_H, type LayoutTable } from '../layout.ts'

interface Props {
  lt: LayoutTable
  dimmed: boolean
  isSelected: boolean
  onClick: () => void
}

export function TableBox({ lt, dimmed, isSelected, onClick }: Props) {
  const t = lt.table
  const color = categoryColor(t.category)

  return (
    <g
      data-table={t.name}
      opacity={dimmed ? DIM_OPACITY : 1}
      style={{ cursor: 'pointer', transition: 'opacity 0.15s' }}
      onClick={onClick}
    >
      {isSelected && (
        <rect
          x={lt.x - 3}
          y={lt.y - 3}
          width={lt.width + 6}
          height={lt.height + 6}
          rx={9}
          fill={color}
          opacity={0.1}
        />
      )}

      {/* Card body */}
      <rect
        x={lt.x}
        y={lt.y}
        width={lt.width}
        height={lt.height}
        rx={6}
        fill="#0c1220"
        stroke={color}
        strokeWidth={isSelected ? 1.5 : 0.75}
        strokeOpacity={isSelected ? 0.9 : 0.3}
      />

      {/* Header fill */}
      <rect x={lt.x} y={lt.y} width={lt.width} height={TABLE_HEADER_H} rx={6} fill={color + '18'} />
      <rect
        x={lt.x}
        y={lt.y + TABLE_HEADER_H - 5}
        width={lt.width}
        height={5}
        fill={color + '18'}
      />
      <line
        x1={lt.x}
        y1={lt.y + TABLE_HEADER_H}
        x2={lt.x + lt.width}
        y2={lt.y + TABLE_HEADER_H}
        stroke={color}
        strokeWidth={0.5}
        strokeOpacity={0.25}
      />

      {/* Category badge */}
      <rect x={lt.x + 6} y={lt.y + 8} width={22} height={14} rx={3} fill={color + '28'} />
      <text
        x={lt.x + 17}
        y={lt.y + 18.5}
        textAnchor="middle"
        fill={color}
        fontSize={7.5}
        fontWeight={800}
        fontFamily="monospace"
        letterSpacing="0.02em"
      >
        {t.category}
      </text>

      {/* Table name */}
      <text
        x={lt.x + 34}
        y={lt.y + 21}
        fill="#e2e8f0"
        fontSize={10.5}
        fontWeight={600}
        fontFamily="monospace"
        letterSpacing="-0.01em"
      >
        {t.name}
      </text>

      {/* Columns */}
      {t.columns.map((col, i) => {
        const cy = lt.y + TABLE_HEADER_H + i * ROW_H
        return (
          <g key={col.name}>
            {i > 0 && (
              <line
                x1={lt.x + 6}
                y1={cy}
                x2={lt.x + lt.width - 6}
                y2={cy}
                stroke="#111827"
                strokeWidth={0.6}
              />
            )}
            <rect
              x={lt.x + 7}
              y={cy + 5}
              width={4}
              height={10}
              rx={1.5}
              fill={columnDotColor(col)}
              opacity={0.9}
            />
            <text
              x={lt.x + 15}
              y={cy + 14.5}
              fill={columnTextColor(col)}
              fontSize={8.5}
              fontFamily="monospace"
            >
              {col.name}
            </text>
          </g>
        )
      })}
    </g>
  )
}
