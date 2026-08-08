// Formatting the console does over and over. Kept in one file so a date reads
// the same on every page — inconsistent timestamps are how an operator ends up
// comparing two numbers that are not comparable.

export function fmtDateTime(iso: string | null | undefined): string {
  if (!iso) return '—'
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return '—'
  return d.toLocaleString(undefined, {
    year: 'numeric',
    month: 'short',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  })
}

export function fmtDate(iso: string | null | undefined): string {
  if (!iso) return '—'
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return '—'
  return d.toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: '2-digit' })
}

/** "3 days ago" / "in 2 hours". Relative time is what an operator actually
 *  reads on an ops page; the absolute value goes in the title attribute. */
export function fmtRelative(iso: string | null | undefined): string {
  if (!iso) return 'never'
  const then = new Date(iso).getTime()
  if (Number.isNaN(then)) return 'never'
  const diff = then - Date.now()
  const abs = Math.abs(diff)
  const rtf = new Intl.RelativeTimeFormat(undefined, { numeric: 'auto' })
  const units: [Intl.RelativeTimeFormatUnit, number][] = [
    ['year', 31536000000],
    ['month', 2592000000],
    ['day', 86400000],
    ['hour', 3600000],
    ['minute', 60000],
  ]
  for (const [unit, ms] of units) {
    if (abs >= ms) return rtf.format(Math.round(diff / ms), unit)
  }
  return 'just now'
}

export function fmtMoney(cents: number): string {
  return new Intl.NumberFormat(undefined, { style: 'currency', currency: 'EUR' }).format(
    cents / 100,
  )
}

export function fmtNumber(n: number): string {
  return new Intl.NumberFormat().format(n)
}

export function shortId(id: string | null | undefined): string {
  if (!id) return '—'
  return id.slice(0, 8)
}

/** A member colour is #RRGGBB after migration 010, but a legacy row may still
 *  say "clay" or "teal" — render those rather than an empty swatch. */
export function colorHex(color: string): string {
  if (color === 'clay') return '#A6552F'
  if (color === 'teal') return '#37756D'
  return /^#[0-9a-f]{6}$/i.test(color) ? color : '#888888'
}

export function titleCase(s: string): string {
  return s.replace(/[_.]/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase())
}
