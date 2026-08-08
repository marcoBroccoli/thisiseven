import { useEffect, useMemo, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { api } from '../api'

type Item = { id: string; label: string; sub: string; to: string }

const PAGES: Item[] = [
  { id: 'p-dash', label: 'Dashboard', sub: 'g d', to: '/' },
  { id: 'p-users', label: 'Users', sub: 'g u', to: '/users' },
  { id: 'p-house', label: 'Households', sub: 'g h', to: '/households' },
  { id: 'p-ops', label: 'Gmail & Calendar ops', sub: 'g o', to: '/ops' },
  { id: 'p-notif', label: 'Notifications', sub: 'g n', to: '/notifications' },
  { id: 'p-set', label: 'Settings', sub: 'g s', to: '/settings' },
  { id: 'p-audit', label: 'Audit log', sub: 'g a', to: '/audit' },
  { id: 'p-health', label: 'Health', sub: 'g e', to: '/health' },
]

/** ⌘K / Ctrl-K. Pages match locally and instantly; households and users are
 *  fetched once the operator has typed enough to mean something, so the palette
 *  never fires a request per keystroke on an empty box. */
export function Palette({ onClose }: { onClose: () => void }) {
  const [q, setQ] = useState('')
  const [cursor, setCursor] = useState(0)
  const [remote, setRemote] = useState<Item[]>([])
  const navigate = useNavigate()
  const listRef = useRef<HTMLDivElement>(null)

  const pages = useMemo(() => {
    const needle = q.trim().toLowerCase()
    if (!needle) return PAGES
    return PAGES.filter((p) => p.label.toLowerCase().includes(needle))
  }, [q])

  useEffect(() => {
    const needle = q.trim()
    if (needle.length < 2) {
      setRemote([])
      return
    }
    let live = true
    const t = setTimeout(async () => {
      try {
        const [hs, us] = await Promise.all([
          api.households({ q: needle, per_page: 5 }),
          api.users({ q: needle, per_page: 5 }),
        ])
        if (!live) return
        setRemote([
          ...hs.rows.map((h) => ({
            id: `h-${h.id}`,
            label: h.name,
            sub: 'household',
            to: `/households/${h.id}`,
          })),
          ...us.rows.map((u) => ({
            id: `u-${u.id}`,
            label: u.email ?? u.id,
            sub: 'user',
            to: `/users/${u.id}`,
          })),
        ])
      } catch {
        if (live) setRemote([])
      }
    }, 220)
    return () => {
      live = false
      clearTimeout(t)
    }
  }, [q])

  const items = useMemo(() => [...pages, ...remote], [pages, remote])

  useEffect(() => setCursor(0), [q])

  const go = (item: Item | undefined) => {
    if (!item) return
    navigate(item.to)
    onClose()
  }

  return (
    <div
      className="scrim"
      role="dialog"
      aria-modal="true"
      aria-label="Command palette"
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) onClose()
      }}
    >
      <div className="modal palette">
        <input
          autoFocus
          type="text"
          value={q}
          placeholder="Jump to a page, household or user…"
          aria-label="Search"
          onChange={(e) => setQ(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'ArrowDown') {
              e.preventDefault()
              setCursor((c) => Math.min(c + 1, items.length - 1))
            } else if (e.key === 'ArrowUp') {
              e.preventDefault()
              setCursor((c) => Math.max(c - 1, 0))
            } else if (e.key === 'Enter') {
              e.preventDefault()
              go(items[cursor])
            } else if (e.key === 'Escape') {
              onClose()
            }
          }}
        />
        <div className="palette-list" ref={listRef} role="listbox">
          {items.length === 0 && <div className="state">No match.</div>}
          {items.map((it, i) => (
            <div
              key={it.id}
              role="option"
              aria-selected={i === cursor}
              className="palette-item"
              onMouseEnter={() => setCursor(i)}
              onMouseDown={(e) => {
                e.preventDefault()
                go(it)
              }}
            >
              <span>{it.label}</span>
              <span className="sub">{it.sub}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}
