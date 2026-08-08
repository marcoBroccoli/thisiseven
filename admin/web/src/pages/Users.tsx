import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { api } from '../api'
import { Card, Pager, Pill, SearchBox } from '../components/Bits'
import { PageHeader } from '../components/Layout'
import { Async, Empty } from '../components/States'
import { fmtDateTime, fmtRelative, shortId } from '../lib/format'
import { useAsync, useDebounced } from '../lib/useAsync'

export function Users() {
  const [q, setQ] = useState('')
  const [page, setPage] = useState(1)
  const debounced = useDebounced(q)
  const state = useAsync(() => api.users({ q: debounced, page }), [debounced, page])
  const navigate = useNavigate()

  return (
    <>
      <PageHeader
        title="Users"
        intro="One row per GoTrue identity. A person may hold a member seat in several households — the counts below are across all of them."
      />
      <Card
        bodyless
        title="All users"
        actions={
          <SearchBox
            value={q}
            onChange={(v) => {
              setQ(v)
              setPage(1)
            }}
            placeholder="Search email, id or display name"
          />
        }
      >
        <Async
          state={state}
          skeletonCols={6}
          isEmpty={(d) => d.rows.length === 0}
          empty={
            <Empty
              title={debounced ? 'No user matches that' : 'No users yet'}
              detail={
                debounced
                  ? 'Try part of an email address, a display name or a user id.'
                  : 'Signups will appear here as soon as someone creates an account.'
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
                      <th>Email</th>
                      <th>Name in app</th>
                      <th>Provider</th>
                      <th className="num">Households</th>
                      <th>Signed up</th>
                      <th>Last activity</th>
                    </tr>
                  </thead>
                  <tbody>
                    {d.rows.map((u) => (
                      <tr
                        key={u.id}
                        className="clickable"
                        onClick={() => navigate(`/users/${u.id}`)}
                      >
                        <td>
                          <Link to={`/users/${u.id}`} onClick={(e) => e.stopPropagation()}>
                            {u.email ?? <span className="mono muted">{shortId(u.id)}</span>}
                          </Link>
                          {!u.confirmed && (
                            <>
                              {' '}
                              <Pill tone="warn">unconfirmed</Pill>
                            </>
                          )}
                        </td>
                        <td>{u.display_name ?? <span className="muted">—</span>}</td>
                        <td className="dim">{u.provider ?? 'email'}</td>
                        <td className="num">
                          {u.active_membership_count}
                          {u.household_count > u.active_membership_count && (
                            <span className="muted">
                              {' '}
                              (+{u.household_count - u.active_membership_count} left)
                            </span>
                          )}
                        </td>
                        <td className="dim nowrap" title={u.created_at}>
                          {fmtDateTime(u.created_at)}
                        </td>
                        <td className="dim nowrap" title={u.last_activity_at ?? ''}>
                          {fmtRelative(u.last_activity_at)}
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
