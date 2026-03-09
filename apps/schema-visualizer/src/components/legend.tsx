import { LEGEND_DOT_COLORS } from '../constants.ts'

export function Legend() {
  return (
    <div
      style={{
        marginTop: 10,
        display: 'flex',
        gap: 22,
        fontSize: 9.5,
        color: '#334155',
        letterSpacing: '0.03em',
        alignItems: 'center',
      }}
    >
      <LegendDot color={LEGEND_DOT_COLORS.pk} label="PK" />
      <LegendDot color={LEGEND_DOT_COLORS.fk} label="FK" />
      <LegendDot color={LEGEND_DOT_COLORS.unique} label="UNIQUE" />
      <LegendLine dashed={false} label="CASCADE" />
      <LegendLine dashed={true} label="SET NULL" />
      <span style={{ marginLeft: 'auto', color: '#1e3050' }}>
        テーブルをクリックで関連を強調 · カテゴリボタンでフィルタ
      </span>
    </div>
  )
}

function LegendDot({ color, label }: { color: string; label: string }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 5 }}>
      <div style={{ width: 8, height: 8, borderRadius: 2, background: color }} />
      <span style={{ color: '#64748b' }}>{label}</span>
    </div>
  )
}

function LegendLine({ dashed, label }: { dashed: boolean; label: string }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 5 }}>
      <svg width={28} height={8}>
        <line
          x1={0}
          y1={4}
          x2={28}
          y2={4}
          stroke="#64748b"
          strokeWidth={1.5}
          strokeDasharray={dashed ? '4,3' : undefined}
        />
      </svg>
      <span style={{ color: '#64748b' }}>{label}</span>
    </div>
  )
}
