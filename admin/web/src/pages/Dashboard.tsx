import { Link } from 'react-router-dom'
import { api } from '../api'
import { Card, Pill } from '../components/Bits'
import { TrendChart } from '../components/Chart'
import { PageHeader } from '../components/Layout'
import { Async } from '../components/States'
import { fmtNumber, fmtRelative } from '../lib/format'
import { useAsync } from '../lib/useAsync'

export function Dashboard() {
  const state = useAsync(() => api.dashboard(), [])

  return (
    <>
      <PageHeader
        title="Dashboard"
        intro="Every number is a live count against the production database. Nothing here is cached."
        actions={
          <button className="btn-sm" onClick={state.reload}>
            Refresh
          </button>
        }
      />
      <Async state={state} skeletonRows={4} skeletonCols={4}>
        {(d) => (
          <div className="stack">
            <div className="grid grid-tiles">
              {d.tiles.map((t) => (
                <div className="card tile" key={t.key}>
                  <div className="label">{t.label}</div>
                  <div className="value">{fmtNumber(t.value)}</div>
                  {t.sub && <div className="sub">{t.sub}</div>}
                </div>
              ))}
            </div>

            <div className="grid grid-2">
              <Card title="Last 14 days">
                <TrendChart days={d.days} series={d.series} />
              </Card>

              <Card title="Needs attention" bodyless>
                {d.attention.every((a) => a.count === 0) ? (
                  <div className="state">
                    <div className="title">All clear</div>
                    <div>No stuck calendar writes, no stale mailboxes, no empty households.</div>
                  </div>
                ) : (
                  <div className="table-wrap">
                    <table className="data">
                      <tbody>
                        {d.attention
                          .filter((a) => a.count > 0)
                          .map((a) => (
                            <tr key={a.kind}>
                              <td>
                                <Link to={a.href}>{a.label}</Link>
                              </td>
                              <td className="num" style={{ width: 90 }}>
                                <Pill tone={a.severity === 'warn' ? 'warn' : 'info'}>
                                  {fmtNumber(a.count)}
                                </Pill>
                              </td>
                            </tr>
                          ))}
                        {d.attention
                          .filter((a) => a.count === 0)
                          .map((a) => (
                            <tr key={a.kind}>
                              <td className="muted">{a.label}</td>
                              <td className="num muted" style={{ width: 90 }}>
                                0
                              </td>
                            </tr>
                          ))}
                      </tbody>
                    </table>
                  </div>
                )}
              </Card>
            </div>

            <p className="muted" style={{ fontSize: 11.5 }}>
              Generated {fmtRelative(d.generated_at)}.
            </p>
          </div>
        )}
      </Async>
    </>
  )
}
