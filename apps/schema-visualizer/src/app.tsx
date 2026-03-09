import { useCallback, useEffect, useMemo, useState } from 'react'
import { CategoryHeaders } from './components/category-headers.tsx'
import { CategoryZones } from './components/category-zones.tsx'
import { Header } from './components/header.tsx'
import { InfoBadge } from './components/info-badge.tsx'
import { Legend } from './components/legend.tsx'
import { MarkerDefs } from './components/marker-defs.tsx'
import { TableBox } from './components/table-box.tsx'
import { ZoomControls } from './components/zoom-controls.tsx'
import { categoryColor } from './constants.ts'
import { computeEdges, edgePath } from './edges.ts'
import { useZoomPan } from './hooks/use-zoom-pan.ts'
import { computeLayout, type LayoutTable } from './layout.ts'
import { parseSchema, type Schema } from './parser.ts'

export default function App() {
  const [schema, setSchema] = useState<Schema | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [selectedTable, setSelectedTable] = useState<string | null>(null)
  const [activeCategories, setActiveCategories] = useState<Set<string>>(new Set())

  const schemaFile = new URLSearchParams(window.location.search).get('schema') ?? 'schema.yaml'
  useEffect(() => {
    fetch(`/${schemaFile}`)
      .then((r) => r.text())
      .then((text) => setSchema(parseSchema(text)))
      .catch((e: unknown) => setError(e instanceof Error ? e.message : String(e)))
  }, [schemaFile])

  const layout = useMemo(() => {
    if (!schema) return null
    return computeLayout(schema)
  }, [schema])

  const visibleTables = useMemo(() => {
    if (!layout) return []
    if (activeCategories.size === 0) return layout.tables
    return layout.tables.filter((lt) => activeCategories.has(lt.table.category))
  }, [layout, activeCategories])

  const visibleTableMap = useMemo(() => {
    const m = new Map<string, LayoutTable>()
    for (const lt of visibleTables) m.set(lt.table.name, lt)
    return m
  }, [visibleTables])

  const edges = useMemo(() => {
    if (!schema) return []
    return computeEdges(schema.relations, visibleTableMap)
  }, [schema, visibleTableMap])

  const relatedTables = useMemo(() => {
    if (!selectedTable || !schema) return new Set<string>()
    const set = new Set<string>()
    set.add(selectedTable)
    for (const r of schema.relations) {
      if (r.from === selectedTable) set.add(r.to)
      if (r.to === selectedTable) set.add(r.from)
    }
    return set
  }, [selectedTable, schema])

  const {
    svgRef,
    viewBox,
    zoom: zoomLevel,
    reset: resetZoom,
    didDrag,
    handlers: zoomHandlers,
  } = useZoomPan(layout?.width ?? 0, layout?.height ?? 0)

  const handleSvgClick = useCallback(
    (e: React.MouseEvent<SVGSVGElement>) => {
      if (didDrag.current) return
      const target = e.target as SVGElement
      if (!target.closest('[data-table]')) {
        setSelectedTable(null)
      }
    },
    [didDrag]
  )

  const toggleCategory = useCallback((catId: string) => {
    setActiveCategories((prev) => {
      const next = new Set(prev)
      if (next.has(catId)) {
        next.delete(catId)
      } else {
        next.add(catId)
      }
      return next
    })
  }, [])

  if (error) {
    return (
      <div style={{ color: '#ef4444', padding: 40, fontFamily: 'monospace' }}>
        Error loading schema: {error}
      </div>
    )
  }

  if (!schema || !layout) {
    return (
      <div style={{ color: '#94a3b8', padding: 40, fontFamily: 'system-ui' }}>
        Loading schema...
      </div>
    )
  }

  return (
    <div
      style={{
        background: '#06090f',
        minHeight: '100vh',
        padding: '16px 20px',
        fontFamily: "'JetBrains Mono', 'Fira Code', monospace",
      }}
    >
      <Header
        categories={schema.categories}
        activeCategories={activeCategories}
        onToggleCategory={toggleCategory}
      />

      <div
        style={{
          overflow: 'hidden',
          borderRadius: 8,
          border: '1px solid #0f1e2e',
          position: 'relative',
        }}
      >
        <svg
          ref={svgRef}
          width="100%"
          height="100%"
          viewBox={viewBox}
          style={{ display: 'block', width: '100%', height: 'calc(100vh - 90px)', cursor: 'grab' }}
          {...zoomHandlers}
          onClick={handleSvgClick}
        >
          <MarkerDefs categories={schema.categories} />

          <rect x={-5000} y={-5000} width={15000} height={15000} fill="#07090e" />
          <rect x={-5000} y={-5000} width={15000} height={15000} fill="url(#dots)" />

          <CategoryZones tables={visibleTables} catFilter={activeCategories} />
          <CategoryHeaders schema={schema} tables={visibleTables} />

          {edges.map((e, i) => {
            const isFocused =
              selectedTable !== null &&
              (e.fromTable === selectedTable || e.toTable === selectedTable)
            const isVisible = selectedTable === null || isFocused
            const color = e.relation.type === 'SET_NULL' ? '#475569' : categoryColor(e.fromCategory)
            const markerId =
              e.relation.type === 'SET_NULL' ? 'url(#arr-null)' : `url(#arr-${e.fromCategory})`
            return (
              <path
                key={i}
                d={edgePath(e)}
                fill="none"
                stroke={color}
                strokeWidth={isFocused ? 1.8 : 0.9}
                strokeOpacity={isVisible ? (isFocused ? 0.85 : 0.22) : 0.04}
                strokeDasharray={e.relation.type === 'SET_NULL' ? '5,4' : undefined}
                markerEnd={markerId}
                style={{ transition: 'stroke-opacity 0.15s, stroke-width 0.15s' }}
              />
            )
          })}

          {visibleTables.map((lt) => {
            const isDim =
              (selectedTable !== null && !relatedTables.has(lt.table.name)) ||
              (activeCategories.size > 0 && !activeCategories.has(lt.table.category))
            return (
              <TableBox
                key={lt.table.name}
                lt={lt}
                dimmed={isDim}
                isSelected={selectedTable === lt.table.name}
                onClick={() => {
                  if (didDrag.current) return
                  setSelectedTable((prev) => (prev === lt.table.name ? null : lt.table.name))
                }}
              />
            )
          })}

          {selectedTable && (
            <InfoBadge tableName={selectedTable} schema={schema} svgWidth={layout.width} />
          )}
        </svg>

        <ZoomControls zoomLevel={zoomLevel} onReset={resetZoom} />
      </div>

      <Legend />
    </div>
  )
}
