interface Props {
  zoomLevel: number
  onReset: () => void
}

const buttonStyle: React.CSSProperties = {
  background: '#0c1220',
  border: '1px solid #1e293b',
  borderRadius: 4,
  color: '#64748b',
  padding: '2px 8px',
  fontSize: 9.5,
  cursor: 'pointer',
  fontFamily: 'inherit',
}

export function ZoomControls({ zoomLevel, onReset }: Props) {
  return (
    <div
      style={{
        position: 'absolute',
        bottom: 12,
        left: 12,
        display: 'flex',
        gap: 4,
        alignItems: 'center',
      }}
    >
      <span
        style={{
          color: '#475569',
          fontSize: 9.5,
          fontFamily: 'inherit',
          marginRight: 4,
        }}
      >
        {Math.round(zoomLevel * 100)}%
      </span>
      <button onClick={onReset} style={buttonStyle}>
        Reset
      </button>
    </div>
  )
}
