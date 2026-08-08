import { useState } from 'react'
import type { TrendSeries } from '../api'
import { fmtDate, fmtNumber } from '../lib/format'

/** A 14-bar column chart, hand-drawn in SVG.
 *
 *  A charting library would be the single largest dependency in this bundle for
 *  one chart on one page — and the console has a strict 'self' CSP, so nothing
 *  can be pulled in at runtime anyway. Fourteen rects is fourteen rects.
 *
 *  The y-axis always starts at zero: a truncated axis on an ops dashboard turns
 *  a two-signup day into a cliff. */
export function TrendChart({ days, series }: { days: string[]; series: TrendSeries[] }) {
  const [activeKey, setActiveKey] = useState(series[0]?.key ?? '')
  const active = series.find((s) => s.key === activeKey) ?? series[0]
  if (!active || days.length === 0) return null

  const points = active.points
  const max = Math.max(1, ...points)
  const total = points.reduce((a, b) => a + b, 0)
  const w = 100
  const h = 100
  const gap = 1.4
  const barW = (w - gap * (points.length - 1)) / points.length

  return (
    <div>
      <div className="chart-legend">
        {series.map((s) => (
          <button
            key={s.key}
            aria-pressed={s.key === active.key}
            onClick={() => setActiveKey(s.key)}
          >
            {s.label}
          </button>
        ))}
      </div>
      <svg
        className="chart"
        viewBox={`0 0 ${w} ${h}`}
        preserveAspectRatio="none"
        role="img"
        aria-label={`${active.label}: ${points.join(', ')} over the last ${points.length} days`}
      >
        {points.map((v, i) => {
          const barH = (v / max) * (h - 6)
          return (
            <rect
              key={i}
              className="bar"
              x={i * (barW + gap)}
              y={h - barH}
              width={barW}
              height={Math.max(barH, v > 0 ? 1.5 : 0.4)}
              rx={0.8}
            >
              <title>{`${fmtDate(days[i])} — ${fmtNumber(v)}`}</title>
            </rect>
          )
        })}
        <line className="axis" x1={0} y1={h} x2={w} y2={h} vectorEffect="non-scaling-stroke" />
      </svg>
      <div className="chart-caption">
        <span>{fmtDate(days[0])}</span>
        <span>
          peak {fmtNumber(max)} · total {fmtNumber(total)}
        </span>
        <span>{fmtDate(days[days.length - 1])}</span>
      </div>
    </div>
  )
}

/** Horizontal funnel: mail → verdict → draft → todo. Widths are relative to the
 *  first step, so the drop-off is the shape and not a number to subtract. */
export function Funnel({ rows }: { rows: { label: string; count: number }[] }) {
  const top = Math.max(1, rows[0]?.count ?? 1)
  return (
    <div className="stack" style={{ gap: 9 }}>
      {rows.map((r, i) => {
        const pct = (r.count / top) * 100
        const prev = i > 0 ? rows[i - 1].count : null
        const drop = prev && prev > 0 ? Math.round(((prev - r.count) / prev) * 100) : null
        return (
          <div key={r.label}>
            <div className="row" style={{ justifyContent: 'space-between', marginBottom: 3 }}>
              <span>{r.label}</span>
              <span className="mono dim">
                {fmtNumber(r.count)}
                {drop !== null && drop > 0 && <span className="muted"> · −{drop}%</span>}
              </span>
            </div>
            <div className="funnel-bar">
              <div className="funnel-fill" style={{ width: `${Math.max(pct, 1)}%` }} />
            </div>
          </div>
        )
      })}
    </div>
  )
}
