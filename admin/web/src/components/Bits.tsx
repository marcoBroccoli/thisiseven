import type { ReactNode } from 'react'
import type { CalendarSyncState, PageMeta } from '../api'
import { colorHex } from '../lib/format'

export function Card({
  title,
  actions,
  note,
  children,
  bodyless,
}: {
  title?: string
  actions?: ReactNode
  note?: ReactNode
  children: ReactNode
  /** Tables sit flush against the card edge; forms and prose get padding. */
  bodyless?: boolean
}) {
  return (
    <section className="card">
      {(title || actions) && (
        <header className="card-head">
          {title && <h2>{title}</h2>}
          {actions && <div className="spacer" />}
          {actions}
        </header>
      )}
      {note && <div className="card-note">{note}</div>}
      {bodyless ? children : <div className="card-body">{children}</div>}
    </section>
  )
}

export function Pill({
  tone = 'neutral',
  children,
}: {
  tone?: 'neutral' | 'ok' | 'warn' | 'danger' | 'info' | 'accent'
  children: ReactNode
}) {
  return <span className={`pill ${tone === 'neutral' ? '' : tone}`}>{children}</span>
}

/** Calendar sync state is the one enum an operator reads constantly, and its
 *  severity is not obvious from the name — 'external_changed' is information,
 *  'retry_required' is a fire. Encode that once. */
export function SyncPill({ state }: { state: CalendarSyncState }) {
  const map: Record<CalendarSyncState, { tone: 'ok' | 'warn' | 'danger' | 'info' | 'neutral'; label: string }> = {
    synced: { tone: 'ok', label: 'Synced' },
    not_scheduled: { tone: 'neutral', label: 'Not scheduled' },
    external_changed: { tone: 'info', label: 'Changed in Google' },
    external_deleted: { tone: 'warn', label: 'Deleted in Google' },
    retry_required: { tone: 'danger', label: 'Retry required' },
  }
  const m = map[state] ?? { tone: 'neutral' as const, label: state }
  return <Pill tone={m.tone}>{m.label}</Pill>
}

export function StatusPill({ status }: { status: string }) {
  const tone =
    status === 'pending' || status === 'queued'
      ? 'warn'
      : status === 'approved' || status === 'accepted' || status === 'sent'
        ? 'ok'
        : status === 'failed'
          ? 'danger'
          : 'neutral'
  return <Pill tone={tone as never}>{status}</Pill>
}

export function ColorDot({ color }: { color: string }) {
  return <span className="swatch" style={{ background: colorHex(color) }} title={color} />
}

export function Pager({
  meta,
  onPage,
  loading,
}: {
  meta: PageMeta
  onPage: (page: number) => void
  loading?: boolean
}) {
  const from = meta.total === 0 ? 0 : (meta.page - 1) * meta.per_page + 1
  const to = Math.min(meta.page * meta.per_page, meta.total)
  return (
    <div className="pager">
      <span>
        {from}–{to} of {meta.total}
      </span>
      {loading && <span className="muted">updating…</span>}
      <span className="spacer" />
      <button
        className="btn-sm"
        onClick={() => onPage(meta.page - 1)}
        disabled={meta.page <= 1}
        aria-label="Previous page"
      >
        ← Prev
      </button>
      <span className="muted">
        {meta.page} / {meta.total_pages}
      </span>
      <button
        className="btn-sm"
        onClick={() => onPage(meta.page + 1)}
        disabled={meta.page >= meta.total_pages}
        aria-label="Next page"
      >
        Next →
      </button>
    </div>
  )
}

export function SearchBox({
  value,
  onChange,
  placeholder,
  autoFocus,
}: {
  value: string
  onChange: (v: string) => void
  placeholder: string
  autoFocus?: boolean
}) {
  return (
    <div className="search">
      <input
        type="search"
        value={value}
        placeholder={placeholder}
        aria-label={placeholder}
        autoFocus={autoFocus}
        onChange={(e) => onChange(e.target.value)}
      />
    </div>
  )
}

export function KV({ items }: { items: [string, ReactNode][] }) {
  return (
    <dl className="kv">
      {items.map(([k, v]) => (
        <div key={k} style={{ display: 'contents' }}>
          <dt>{k}</dt>
          <dd>{v}</dd>
        </div>
      ))}
    </dl>
  )
}

export function Modal({
  title,
  subtitle,
  onClose,
  footer,
  children,
  wide,
}: {
  title: string
  subtitle?: ReactNode
  onClose: () => void
  footer?: ReactNode
  children: ReactNode
  wide?: boolean
}) {
  return (
    <div
      className="scrim"
      role="dialog"
      aria-modal="true"
      aria-label={title}
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) onClose()
      }}
    >
      <div className="modal" style={wide ? { maxWidth: 760 } : undefined}>
        <div className="modal-head">
          <h2>{title}</h2>
          {subtitle && <div className="dim">{subtitle}</div>}
        </div>
        <div className="modal-body">{children}</div>
        {footer && <div className="modal-foot">{footer}</div>}
      </div>
    </div>
  )
}
