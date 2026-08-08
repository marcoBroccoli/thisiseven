import { api } from '../api'
import { Card, Pill } from '../components/Bits'
import { PageHeader } from '../components/Layout'
import { Async } from '../components/States'
import { fmtDateTime, fmtNumber } from '../lib/format'
import { useAsync } from '../lib/useAsync'

export function Health() {
  const state = useAsync(() => api.health(), [])

  return (
    <>
      <PageHeader
        title="Health"
        intro="What this service can reach right now, and how big the database actually is."
        actions={
          <button className="btn-sm" onClick={state.reload}>
            Re-check
          </button>
        }
      />
      <Async state={state} skeletonRows={6} skeletonCols={3}>
        {(d) => (
          <div className="stack">
            <div className="grid grid-2">
              <Card title="Dependencies" bodyless>
                <div className="table-wrap">
                  <table className="data">
                    <tbody>
                      {d.dependencies.map((dep) => (
                        <tr key={dep.name}>
                          <td style={{ width: 100 }}>
                            <strong>{dep.name}</strong>
                          </td>
                          <td>
                            {dep.ok ? <Pill tone="ok">up</Pill> : <Pill tone="danger">down</Pill>}
                          </td>
                          <td className="dim trunc" title={dep.detail}>
                            {dep.detail}
                          </td>
                          <td className="num dim nowrap">{dep.latency_ms} ms</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </Card>

              <Card title="Database">
                <div className="row" style={{ gap: 14, marginBottom: 12 }}>
                  <div>
                    <div className="muted" style={{ fontSize: 11.5 }}>
                      Name
                    </div>
                    <strong className="mono">{d.database.name ?? '—'}</strong>
                  </div>
                  <div>
                    <div className="muted" style={{ fontSize: 11.5 }}>
                      Size
                    </div>
                    <strong>{d.database.size ?? '—'}</strong>
                  </div>
                  <div>
                    <div className="muted" style={{ fontSize: 11.5 }}>
                      Backends
                    </div>
                    <strong>{d.database.backends ?? '—'}</strong>
                  </div>
                </div>
                <div className="row" style={{ gap: 6 }}>
                  {Object.entries(d.pool).map(([k, v]) => (
                    <Pill key={k}>
                      {k.replace(/_/g, ' ')}: {fmtNumber(v)}
                    </Pill>
                  ))}
                </div>
                <div className="row" style={{ gap: 6, marginTop: 10 }}>
                  <Pill tone="ok">{d.logins_24h.ok ?? 0} sign-ins in 24h</Pill>
                  <Pill tone={(d.logins_24h.failed ?? 0) > 0 ? 'warn' : 'neutral'}>
                    {d.logins_24h.failed ?? 0} failed
                  </Pill>
                </div>
              </Card>
            </div>

            <div className="grid grid-2">
              <Card title="Row counts" bodyless>
                <div className="table-wrap">
                  <table className="data">
                    <thead>
                      <tr>
                        <th>Table</th>
                        <th className="num">Rows</th>
                      </tr>
                    </thead>
                    <tbody>
                      {d.tables.map((t) => (
                        <tr key={`${t.schema}.${t.table}`}>
                          <td className="mono">
                            <span className="muted">{t.schema}.</span>
                            {t.table}
                          </td>
                          <td className="num">{fmtNumber(t.rows)}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </Card>

              <Card title="Admin schema migrations">
                <p className="dim" style={{ marginTop: 0 }}>
                  Applied by this service at boot, tracked in{' '}
                  <span className="mono">admin.schema_migrations</span>. Separate from evend's
                  chain on purpose.
                </p>
                <ul className="mono" style={{ paddingLeft: 18, margin: 0 }}>
                  {d.admin_migrations.map((m) => (
                    <li key={m}>{m}</li>
                  ))}
                </ul>
              </Card>
            </div>

            <p className="muted" style={{ fontSize: 11.5 }}>
              Checked {fmtDateTime(d.checked_at)}.
            </p>
          </div>
        )}
      </Async>
    </>
  )
}
