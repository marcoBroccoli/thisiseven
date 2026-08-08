import { useEffect, useRef, useState, type ReactNode } from 'react'
import { NavLink, useNavigate } from 'react-router-dom'
import type { Admin } from '../api'
import { Palette } from './Palette'

const NAV: { group: string; items: { to: string; label: string; key: string }[] }[] = [
  {
    group: 'Overview',
    items: [
      { to: '/', label: 'Dashboard', key: 'd' },
      { to: '/health', label: 'Health', key: 'e' },
    ],
  },
  {
    group: 'Data',
    items: [
      { to: '/users', label: 'Users', key: 'u' },
      { to: '/households', label: 'Households', key: 'h' },
      { to: '/ops', label: 'Gmail & Calendar', key: 'o' },
    ],
  },
  {
    group: 'Operate',
    items: [
      { to: '/notifications', label: 'Notifications', key: 'n' },
      { to: '/settings', label: 'Settings', key: 's' },
      { to: '/audit', label: 'Audit log', key: 'a' },
    ],
  },
]

type Theme = 'system' | 'light' | 'dark'

function applyTheme(t: Theme) {
  const root = document.documentElement
  if (t === 'system') root.removeAttribute('data-theme')
  else root.setAttribute('data-theme', t)
}

export function Layout({
  admin,
  onSignedOut,
  children,
}: {
  admin: Admin
  onSignedOut: () => void
  children: ReactNode
}) {
  const [paletteOpen, setPaletteOpen] = useState(false)
  const [theme, setTheme] = useState<Theme>(
    () => (localStorage.getItem('even-admin-theme') as Theme) || 'system',
  )
  const navigate = useNavigate()
  const pendingG = useRef(false)

  useEffect(() => {
    applyTheme(theme)
    localStorage.setItem('even-admin-theme', theme)
  }, [theme])

  // Keyboard: ⌘K opens the palette; `g` then a letter jumps. The `g` prefix is
  // ignored while a field has focus, or typing "gu" in a search box would
  // navigate away mid-word.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const el = document.activeElement
      const typing =
        el instanceof HTMLInputElement ||
        el instanceof HTMLTextAreaElement ||
        el instanceof HTMLSelectElement ||
        (el as HTMLElement | null)?.isContentEditable === true

      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault()
        setPaletteOpen(true)
        return
      }
      if (typing || e.metaKey || e.ctrlKey || e.altKey) return

      if (e.key === '/') {
        e.preventDefault()
        setPaletteOpen(true)
        return
      }
      if (pendingG.current) {
        pendingG.current = false
        const target = NAV.flatMap((g) => g.items).find((i) => i.key === e.key.toLowerCase())
        if (target) {
          e.preventDefault()
          navigate(target.to)
        }
        return
      }
      if (e.key.toLowerCase() === 'g') {
        pendingG.current = true
        setTimeout(() => (pendingG.current = false), 1200)
      }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [navigate])

  return (
    <div className="shell">
      <aside className="sidebar">
        <div className="sidebar-brand">
          <span className="glyph" aria-hidden>
            E
          </span>
          <span className="name">Even Admin</span>
          <span className="env">ops</span>
        </div>
        <nav className="nav" aria-label="Sections">
          {NAV.map((group) => (
            <div key={group.group}>
              <div className="nav-group-label">{group.group}</div>
              {group.items.map((item) => (
                <NavLink
                  key={item.to}
                  to={item.to}
                  end={item.to === '/'}
                  className={({ isActive }) => `nav-item ${isActive ? 'active' : ''}`}
                >
                  <span>{item.label}</span>
                  <span className="key">g {item.key}</span>
                </NavLink>
              ))}
            </div>
          ))}
        </nav>
        <div className="sidebar-foot">
          <div className="who" title={admin.email}>
            {admin.email}
            <br />
            <span className="role">
              {admin.role === 'admin' ? 'Full access' : 'Read only'} · MFA on
            </span>
          </div>
        </div>
      </aside>

      <div className="main">
        <header className="topbar">
          <button className="btn-ghost btn-sm" onClick={() => setPaletteOpen(true)}>
            Search <kbd>⌘K</kbd>
          </button>
          <div className="topbar-actions">
            <select
              aria-label="Theme"
              value={theme}
              style={{ width: 'auto' }}
              onChange={(e) => setTheme(e.target.value as Theme)}
            >
              <option value="system">System theme</option>
              <option value="light">Light</option>
              <option value="dark">Dark</option>
            </select>
            <button className="btn-sm" onClick={onSignedOut}>
              Sign out
            </button>
          </div>
        </header>
        <main className="page">{children}</main>
      </div>

      {paletteOpen && <Palette onClose={() => setPaletteOpen(false)} />}
    </div>
  )
}

/** Page header used inside every route body, so the h1 and the description
 *  live with the page rather than being threaded through the shell. */
export function PageHeader({
  title,
  intro,
  actions,
}: {
  title: string
  intro?: ReactNode
  actions?: ReactNode
}) {
  return (
    <>
      <div className="row" style={{ marginBottom: 6 }}>
        <h1 style={{ fontSize: 19, margin: 0, letterSpacing: '-0.02em' }}>{title}</h1>
        {actions && <div style={{ marginLeft: 'auto' }}>{actions}</div>}
      </div>
      {intro && <p className="page-intro">{intro}</p>}
    </>
  )
}
