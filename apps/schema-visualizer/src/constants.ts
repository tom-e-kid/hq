import type { Column } from './parser.ts'

// ── Category colors ─────────────────────────────────────────
const CATEGORY_COLORS: Record<string, string> = {
  AU: '#818cf8',
  TN: '#38bdf8',
  MD: '#34d399',
  IS: '#fbbf24',
  IT: '#f472b6',
  US: '#c084fc',
}

export function categoryColor(catId: string): string {
  return CATEGORY_COLORS[catId] ?? '#6b7280'
}

// ── Column indicator colors ─────────────────────────────────
const DOT_COLORS = {
  pk: '#fbbf24',
  fk: '#38bdf8',
  unique: '#a78bfa',
  jsonb: '#4ade80',
  normal: '#1e3050',
}

const TEXT_COLORS = {
  pk: '#fcd34d',
  fk: '#7dd3fc',
  unique: '#c4b5fd',
  jsonb: '#86efac',
  normal: '#4b6280',
}

export function columnDotColor(col: Column): string {
  if (col.pk) return DOT_COLORS.pk
  if (col.fk) return DOT_COLORS.fk
  if (col.unique) return DOT_COLORS.unique
  if (col.jsonb) return DOT_COLORS.jsonb
  return DOT_COLORS.normal
}

export function columnTextColor(col: Column): string {
  if (col.pk) return TEXT_COLORS.pk
  if (col.fk) return TEXT_COLORS.fk
  if (col.unique) return TEXT_COLORS.unique
  if (col.jsonb) return TEXT_COLORS.jsonb
  return TEXT_COLORS.normal
}

// ── Legend dot colors (re-exported for Legend component) ─────
export const LEGEND_DOT_COLORS = DOT_COLORS

// ── Rendering constants ─────────────────────────────────────
export const DIM_OPACITY = 0.12
