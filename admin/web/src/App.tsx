import { useCallback, useEffect, useState } from 'react'
import { BrowserRouter, Route, Routes } from 'react-router-dom'
import { ApiError, SESSION_LOST, api, type Admin } from './api'
import { Layout } from './components/Layout'
import { ToastHost } from './components/Toast'
import { Audit } from './pages/Audit'
import { Dashboard } from './pages/Dashboard'
import { Health } from './pages/Health'
import { HouseholdDetail } from './pages/HouseholdDetail'
import { Households } from './pages/Households'
import { Login } from './pages/Login'
import { Notifications } from './pages/Notifications'
import { Ops } from './pages/Ops'
import { Settings } from './pages/Settings'
import { UserDetail } from './pages/UserDetail'
import { Users } from './pages/Users'

export function App() {
  const [admin, setAdmin] = useState<Admin | null>(null)
  const [booting, setBooting] = useState(true)

  // The session lives in an httpOnly cookie, so the only way to know whether we
  // are signed in is to ask. One call on boot; a 401 is the normal answer for a
  // fresh browser, not an error worth showing.
  useEffect(() => {
    api
      .me()
      .then((res) => setAdmin(res.admin))
      .catch((e) => {
        if (!(e instanceof ApiError) || e.status !== 401) {
          // A genuinely broken server still lands on the login screen — there
          // is nothing else the operator can usefully do from here.
        }
        setAdmin(null)
      })
      .finally(() => setBooting(false))
  }, [])

  // Any 401 from anywhere drops back to the login screen exactly once.
  useEffect(() => {
    const onLost = () => setAdmin(null)
    window.addEventListener(SESSION_LOST, onLost)
    return () => window.removeEventListener(SESSION_LOST, onLost)
  }, [])

  const signOut = useCallback(async () => {
    try {
      await api.logout()
    } finally {
      setAdmin(null)
    }
  }, [])

  if (booting) {
    return (
      <div className="login-page">
        <div className="dim">Loading…</div>
      </div>
    )
  }

  if (!admin) return <Login onSignedIn={setAdmin} />

  const canWrite = admin.role === 'admin'

  return (
    <BrowserRouter>
      <ToastHost>
        <Layout admin={admin} onSignedOut={signOut}>
          <Routes>
            <Route path="/" element={<Dashboard />} />
            <Route path="/users" element={<Users />} />
            <Route path="/users/:id" element={<UserDetail />} />
            <Route path="/households" element={<Households />} />
            <Route path="/households/:id" element={<HouseholdDetail canWrite={canWrite} />} />
            <Route path="/ops" element={<Ops />} />
            <Route path="/notifications" element={<Notifications canWrite={canWrite} />} />
            <Route path="/settings" element={<Settings canWrite={canWrite} />} />
            <Route path="/audit" element={<Audit />} />
            <Route path="/health" element={<Health />} />
            <Route
              path="*"
              element={
                <div className="state">
                  <div className="title">No such page</div>
                  <div>Check the address, or press ⌘K to jump somewhere.</div>
                </div>
              }
            />
          </Routes>
        </Layout>
      </ToastHost>
    </BrowserRouter>
  )
}
