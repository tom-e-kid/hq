import { useCallback, useEffect, useRef, useState } from 'react'

const MIN_ZOOM = 0.3
const MAX_ZOOM = 3

interface ViewState {
  x: number
  y: number
  w: number
  h: number
}

export function useZoomPan(contentW: number, contentH: number) {
  const svgRef = useRef<SVGSVGElement>(null)
  const [view, setView] = useState<ViewState>({ x: 0, y: 0, w: contentW, h: contentH })
  const isPanning = useRef(false)
  const didDrag = useRef(false)
  const panStart = useRef({ x: 0, y: 0, vx: 0, vy: 0 })

  useEffect(() => {
    setView({ x: 0, y: 0, w: contentW, h: contentH })
  }, [contentW, contentH])

  const zoom = view.w > 0 ? contentW / view.w : 1

  const handleWheel = useCallback(
    (e: React.WheelEvent<SVGSVGElement>) => {
      e.preventDefault()
      const svg = svgRef.current
      if (!svg) return

      const rect = svg.getBoundingClientRect()
      const mx = (e.clientX - rect.left) / rect.width
      const my = (e.clientY - rect.top) / rect.height
      const factor = e.deltaY > 0 ? 1.08 : 1 / 1.08

      setView((prev) => {
        const newW = Math.min(contentW / MIN_ZOOM, Math.max(contentW / MAX_ZOOM, prev.w * factor))
        const newH = Math.min(contentH / MIN_ZOOM, Math.max(contentH / MAX_ZOOM, prev.h * factor))
        const newX = prev.x + (prev.w - newW) * mx
        const newY = prev.y + (prev.h - newH) * my
        return { x: newX, y: newY, w: newW, h: newH }
      })
    },
    [contentW, contentH]
  )

  const handleMouseDown = useCallback(
    (e: React.MouseEvent<SVGSVGElement>) => {
      if (e.button !== 0) return
      isPanning.current = true
      didDrag.current = false
      panStart.current = { x: e.clientX, y: e.clientY, vx: view.x, vy: view.y }
    },
    [view.x, view.y]
  )

  const handleMouseMove = useCallback(
    (e: React.MouseEvent<SVGSVGElement>) => {
      if (!isPanning.current) return
      const svg = svgRef.current
      if (!svg) return

      const movedX = Math.abs(e.clientX - panStart.current.x)
      const movedY = Math.abs(e.clientY - panStart.current.y)
      if (movedX > 4 || movedY > 4) didDrag.current = true

      const rect = svg.getBoundingClientRect()
      const dx = ((e.clientX - panStart.current.x) / rect.width) * view.w
      const dy = ((e.clientY - panStart.current.y) / rect.height) * view.h
      setView((prev) => ({
        ...prev,
        x: panStart.current.vx - dx,
        y: panStart.current.vy - dy,
      }))
    },
    [view.w, view.h]
  )

  const handleMouseUp = useCallback(() => {
    isPanning.current = false
  }, [])

  const reset = useCallback(() => {
    setView({ x: 0, y: 0, w: contentW, h: contentH })
  }, [contentW, contentH])

  return {
    svgRef,
    viewBox: `${view.x} ${view.y} ${view.w} ${view.h}`,
    zoom,
    reset,
    didDrag,
    handlers: {
      onWheel: handleWheel,
      onMouseDown: handleMouseDown,
      onMouseMove: handleMouseMove,
      onMouseUp: handleMouseUp,
      onMouseLeave: handleMouseUp,
    },
  }
}
