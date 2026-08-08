import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { api } from '../api'
import { Card, Pager, Pill, SearchBox } from '../components/Bits'
import { PageHeader } from '../components/Layout'
import { Async, Empty } from '../components/States'
import { fmtDateTime, fmtRelative } from '../lib/format'
import { useAsync, useDebounced } from '../lib/useAsync'

export function Households() {
  const [q, setQ] = useState('')
  const [page, setPage] = useState(1)
  const debounced = useDebounced(q)
  const state = useAsync(() => api.households({ q: debounced, page }), [debounced, page])
  const navigate = useNavigate()

  return (
    <>
      <PageHeader
        title="Households"
        intro="A household holds at most two people. An empty seat with a pending invite is normal; an empty seat without one usually means someone left."
      />
      <Card
        bodyless
        title="All households"
        actions={
          <SearchBox
            value={q}
            onChange={(v) => {
              setQ(v)
              setPage(1)
            }}
            placeholder="Search name, invite code or member"
          />
        }
      >
        <Async
          state={state}
          skeletonCols={7}
          isEmpty={(d) => d.rows.length === 0}
          empty={
            <Empty
              title={debounced ? 'No household matches that' : 'No households yet'}
              detail={
                debounced
                  ? 'Try a household name, a member name or an invite code.'
                  : 'A household is created the first time someone finishes onboarding.'
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
                      <th>Name</th>
                      <th className="num">Members</th>
                      <th>Invite</th>
                      <th className="num">Open tasks</th>
                      <th className="num">Drafts</th>
                      <th>Calendar</th>
                      <th>Last activity</th>
                    </tr>
                  </thead>
                  <tbody>
                    {d.rows.map((h) => (
                      <tr
                        key={h.id}
                        className="clickable"
                        onClick={() => navigate(`/households/${h.id}`)}
                      >
                        <td>
                          <Link to={`/households/${h.id}`} onClick={(e) => e.stopPropagation()}>
                            {h.name}
                          </Link>
                          <div className="muted" style={{ fontSize: 11 }}>
                            created {fmtDateTime(h.created_at)}
                          </div>
                        </td>
                        <td className="num">
                          {h.active_members}
                          {h.departed_members > 0 && (
                            <span className="muted"> (+{h.departed_members} left)</span>
                          )}
                        </td>
                        <td>
                          <span className="mono dim">{h.invite_code}</span>
                          {h.pending_invite_email && (
                            <div style={{ fontSize: 11 }}>
                              <Pill tone="warn">pending</Pill>{' '}
                              <span className="muted">{h.pending_invite_email}</span>
                            </div>
                          )}
                        </td>
                        <td className="num">{h.open_tasks}</td>
                        <td className="num">
                          {h.pending_drafts > 0 ? (
                            <Pill tone="warn">{h.pending_drafts}</Pill>
                          ) : (
                            <span className="muted">0</span>
                          )}
                        </td>
                        <td>
                          {h.calendar_id === 'primary' ? (
                            <span className="muted">none</span>
                          ) : h.calendar_sync_issues > 0 ? (
                            <Pill tone="danger">{h.calendar_sync_issues} issues</Pill>
                          ) : (
                            <Pill tone="ok">shared</Pill>
                          )}
                        </td>
                        <td className="dim nowrap" title={h.last_activity_at ?? ''}>
                          {fmtRelative(h.last_activity_at)}
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
    </>
  )
}
