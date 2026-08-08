import { useEffect, useRef, useState } from 'react'
import QRCode from 'qrcode'
import { ApiError, api, type Admin, type LoginStage } from '../api'

/** Sign-in is two screens on purpose.
 *
 *  The password step never issues a session; only a verified TOTP code does. On
 *  a first login the server hands back a candidate secret and this screen draws
 *  the QR locally (the qrcode package is bundled — nothing is fetched), and the
 *  secret is only written to the account once a code proves the phone has it. */
export function Login({ onSignedIn }: { onSignedIn: (admin: Admin) => void }) {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [stage, setStage] = useState<LoginStage | null>(null)
  const [code, setCode] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [qr, setQr] = useState<string | null>(null)
  const codeRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    if (stage?.otpauth_uri) {
      QRCode.toDataURL(stage.otpauth_uri, { margin: 1, width: 220, errorCorrectionLevel: 'M' })
        .then(setQr)
        .catch(() => setQr(null))
    }
    if (stage) codeRef.current?.focus()
  }, [stage])

  const submitPassword = async (e: React.FormEvent) => {
    e.preventDefault()
    setBusy(true)
    setError(null)
    try {
      setStage(await api.login(email, password))
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Sign-in failed.')
    } finally {
      setBusy(false)
    }
  }

  const submitCode = async (e: React.FormEvent) => {
    e.preventDefault()
    setBusy(true)
    setError(null)
    try {
      const { admin } = await api.totp(code.trim())
      onSignedIn(admin)
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Verification failed.')
      setCode('')
      // A rate-limited or expired challenge means starting over; keeping the
      // code box on screen would just collect wrong guesses.
      if (err instanceof ApiError && (err.code === 'no_challenge' || err.code === 'totp_exhausted')) {
        setStage(null)
        setPassword('')
      }
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="login-page">
      <div className="card login-card">
        <div className="card-body">
          <div className="login-brand">
            <span className="glyph" aria-hidden>
              E
            </span>
            <strong>Even Admin</strong>
          </div>

          {!stage ? (
            <>
              <h1>Sign in</h1>
              <p className="dim" style={{ marginTop: 0 }}>
                Operations console. Every change you make here is recorded.
              </p>
              <form onSubmit={submitPassword}>
                <label className="field">
                  <span className="lbl">Email</span>
                  <input
                    type="email"
                    autoComplete="username"
                    required
                    autoFocus
                    value={email}
                    data-testid="login-email"
                    onChange={(e) => setEmail(e.target.value)}
                  />
                </label>
                <label className="field">
                  <span className="lbl">Password</span>
                  <input
                    type="password"
                    autoComplete="current-password"
                    required
                    value={password}
                    data-testid="login-password"
                    onChange={(e) => setPassword(e.target.value)}
                  />
                </label>
                {error && (
                  <div className="banner danger" role="alert" style={{ marginBottom: 12 }}>
                    {error}
                  </div>
                )}
                <button
                  className="btn-primary"
                  type="submit"
                  disabled={busy}
                  style={{ width: '100%', justifyContent: 'center' }}
                  data-testid="login-submit"
                >
                  {busy ? 'Checking…' : 'Continue'}
                </button>
              </form>
            </>
          ) : (
            <>
              <h1>{stage.stage === 'enroll' ? 'Set up two-factor' : 'Two-factor code'}</h1>
              {stage.stage === 'enroll' ? (
                <>
                  <p className="dim" style={{ marginTop: 0 }}>
                    Scan this with your authenticator app, then enter the six-digit code it
                    shows. This is your only chance to capture the secret.
                  </p>
                  {qr && (
                    <div className="qr-holder">
                      <img src={qr} alt="Two-factor QR code" width={200} height={200} />
                    </div>
                  )}
                  {stage.secret && (
                    <div className="secret-line" style={{ marginBottom: 12 }}>
                      {stage.secret}
                    </div>
                  )}
                </>
              ) : (
                <p className="dim" style={{ marginTop: 0 }}>
                  Enter the six-digit code from your authenticator app.
                </p>
              )}
              <form onSubmit={submitCode}>
                <label className="field">
                  <span className="lbl">Code</span>
                  <input
                    ref={codeRef}
                    className="code-input"
                    inputMode="numeric"
                    autoComplete="one-time-code"
                    pattern="[0-9]{6}"
                    maxLength={6}
                    required
                    value={code}
                    data-testid="login-totp"
                    onChange={(e) => setCode(e.target.value.replace(/\D/g, ''))}
                  />
                </label>
                {error && (
                  <div className="banner danger" role="alert" style={{ marginBottom: 12 }}>
                    {error}
                  </div>
                )}
                <button
                  className="btn-primary"
                  type="submit"
                  disabled={busy || code.length !== 6}
                  style={{ width: '100%', justifyContent: 'center' }}
                >
                  {busy ? 'Verifying…' : 'Verify and sign in'}
                </button>
              </form>
              <button
                className="btn-ghost btn-sm"
                style={{ marginTop: 10 }}
                onClick={() => {
                  setStage(null)
                  setCode('')
                  setError(null)
                }}
              >
                ← Back
              </button>
            </>
          )}
        </div>
      </div>
    </div>
  )
}
