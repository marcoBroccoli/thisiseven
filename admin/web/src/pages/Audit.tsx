import { useState } from 'react'
import { Link } from 'react-router-dom'
import { api, type AuditRow } from '../api'
import { Card, Modal, Pager, Pill, SearchBox } from '../components/Bits'
import { PageHeader } from '../components/Layout'
import { Async, Empty } from '../components/States'
import { fmtDateTime, titleCase } from '../lib/format'
import { useAsync, useDebounced } from '../lib/useAsync'

export function Audit() {
  const [q, setQ] = useState('')
  const [action, setAction] = useState('')
  const [page, setPage] = useState(1)
  const [detail, setDetail] = useState<AuditRow | null>(null)
  const debounced = useDebounced(q)
  const state = useAsync(() => api.audit({ q: debounced, action, page }), [debounced, action, page])

  return (
    <>
      <PageHeader
        title="Audit log"
        intro="Every write the console has performed, with the whole row before and after. Reads are not logged — only changes."
      />
      <Card
        bodyless
        actions={
          <div className="row">
            <select
              aria-label="Filter by action"
              value={action}
              style={{ width: 'auto' }}
              onChange={(e) => {
                setAction(e.target.value)
                setPage(1)
              }}
            >
              <option value="">All actions</option>
              {(state.data?.actions ?? []).map((a) => (
                <option key={a} value={a}>
                  {a}
                </option>
              ))}
            </select>
            <SearchBox
              value={q}
              onChange={(v) => {
                setQ(v)
                setPage(1)
              }}
              placeholder="Search actor, action or target"
            />
          </div>
        }
      >
        <Async
          state={state}
          skeletonCols={5}
          isEmpty={(d) => d.rows.length === 0}
          empty={
            <Empty
              title={q || action ? 'No entry matches that' : 'Nothing logged yet'}
              detail={
                q || action
                  ? 'Clear the filters to see the whole log.'
                  : 'The log fills the first time someone changes something here.'
              }
            />
          }
        >
          {(d) => (
            <>
              <div className="table-wrap">
                <table className="data">
                  <thead>
                    <tr>
                      <th>When</th>
                      <th>Who</th>
                      <th>Action</th>
                      <th>What</th>
                      <th>Target</th>
                      <th />
                    </tr>
                  </thead>
                  <tbody>
                    {d.rows.map((row) => (
                      <tr key={row.id}>
                        <td className="dim nowrap" title={row.created_at}>
                          {fmtDateTime(row.created_at)}
                        </td>
                        <td className="trunc" title={row.actor_email}>
                          {row.actor_email}
                          {row.ip && (
                            <div className="muted mono" style={{ fontSize: 11 }}>
                              {row.ip}
                            </div>
                          )}
                        </td>
                        <td>
                          <Pill tone={row.action.includes('delete') ? 'danger' : 'accent'}>
                            {row.action}
                          </Pill>
                        </td>
                        <td className="dim">{row.summary ?? titleCase(row.action)}</td>
                        <td className="mono dim">
                          {row.target_type && row.target_id ? (
                            row.target_type === 'household' ? (
                              <Link to={`/households/${row.target_id}`}>
                                {row.target_id.slice(0, 8)}
                              </Link>
                            ) : (
                              <span title={row.target_id}>{row.target_id.slice(0, 24)}</span>
                            )
                          ) : (
                            <span className="muted">—</span>
                          )}
                        </td>
                        <td className="right">
                          {(row.before != null || row.after != null) && (
                            <button className="btn-sm" onClick={() => setDetail(row)}>
                              Diff
                            </button>
                          )}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              <Pager meta={d.page} onPage={setPage} loading={state.loading} />
            </>
          )}
        </Async>
      </Card>

      {detail && (
        <Modal
          wide
          title={detail.action}
          subtitle={`${detail.actor_email} · ${fmtDateTime(detail.created_at)}`}
          onClose={() => setDetail(null)}
          footer={<button onClick={() => setDetail(null)}>Close</button>}
        >
          <div className="grid grid-2">
            <div>
              <div className="lbl" style={{ fontWeight: 600, marginBottom: 4 }}>
                Before
              </div>
              <pre className="secret-line" style={{ whiteSpace: 'pre-wrap' }}>
                {detail.before ? JSON.stringify(detail.before, null, 2) : '—'}
              </pre>
            </div>
            <div>
              <div className="lbl" style={{ fontWeight: 600, marginBottom: 4 }}>
                After
              </div>
              <pre className="secret-line" style={{ whiteSpace: 'pre-wrap' }}>
                {detail.after ? JSON.stringify(detail.after, null, 2) : '—'}
              </pre>
            </div>
          </div>
        </Modal>
      )}
    </>
  )
}
