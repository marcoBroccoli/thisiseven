import { Link, useParams } from 'react-router-dom'
import { api } from '../api'
import { Card, ColorDot, KV, Pill, StatusPill } from '../components/Bits'
import { PageHeader } from '../components/Layout'
import { Async, Empty } from '../components/States'
import { fmtDateTime, fmtRelative, titleCase } from '../lib/format'
import { useAsync } from '../lib/useAsync'

export function UserDetail() {
  const { id = '' } = useParams()
  const state = useAsync(() => api.user(id), [id])

  return (
    <Async state={state} skeletonRows={8}>
      {(d) => (
        <>
          <PageHeader
            title={d.user.email ?? d.user.id}
            intro={
              <>
                GoTrue identity <span className="mono">{d.user.id}</span>. Read only — the
                console does not edit accounts.
              </>
            }
            actions={
              <button className="btn-sm" onClick={state.reload}>
                Refresh
              </button>
            }
          />

          <div className="stack">
            <div className="grid grid-2">
              <Card title="Identity">
                <KV
                  items={[
                    ['Email', d.user.email ?? <span className="muted">none</span>],
                    ['User id', <span className="mono">{d.user.id}</span>],
                    ['Provider', d.user.provider ?? 'email'],
                    [
                      'Confirmed',
                      d.user.confirmed ? (
                        <Pill tone="ok">yes</Pill>
                      ) : (
                        <Pill tone="warn">no</Pill>
                      ),
                    ],
                    ['Signed up', fmtDateTime(d.user.created_at)],
                    ['Last sign-in', fmtDateTime(d.user.last_sign_in_at)],
                    ['Last activity', fmtRelative(d.user.last_activity_at)],
                  ]}
                />
              </Card>

              <Card title="Invites addressed to this email" bodyless>
                {d.invites.length === 0 ? (
                  <Empty title="No invites" detail="Nobody has invited this address to a household." />
                ) : (
                  <div className="table-wrap">
                    <table className="data">
                      <thead>
                        <tr>
                          <th>Household</th>
                          <th>From</th>
                          <th>Status</th>
                          <th>Sent</th>
                        </tr>
                      </thead>
                      <tbody>
                        {d.invites.map((i) => (
                          <tr key={i.id}>
                            <td>
                              <Link to={`/households/${i.household_id}`}>{i.household_name}</Link>
                            </td>
                            <td className="dim">{i.invited_by}</td>
                            <td>
                              <StatusPill status={i.status} />
                            </td>
                            <td className="dim nowrap">{fmtDateTime(i.created_at)}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}
              </Card>
            </div>

            <Card title={`Households (${d.memberships.length})`} bodyless>
              {d.memberships.length === 0 ? (
                <Empty
                  title="Not in any household"
                  detail="This account has signed up but never completed household setup."
                />
              ) : (
                <div className="table-wrap">
                  <table className="data">
                    <thead>
                      <tr>
                        <th>Household</th>
                        <th>Name used</th>
                        <th>Google mailbox</th>
                        <th className="num">Drafts</th>
                        <th className="num">Tasks made</th>
                        <th className="num">Done</th>
                        <th>Joined</th>
                        <th>State</th>
                      </tr>
                    </thead>
                    <tbody>
                      {d.memberships.map((m) => (
                        <tr key={m.member_id}>
                          <td>
                            <Link to={`/households/${m.household_id}`}>{m.household_name}</Link>
                            {m.is_calendar_owner && (
                              <>
                                {' '}
                                <Pill tone="accent">calendar owner</Pill>
                              </>
                            )}
                          </td>
                          <td>
                            <span className="row" style={{ gap: 6 }}>
                              <ColorDot color={m.color} />
                              {m.display_name}
                              {m.has_avatar && <span className="muted">· photo</span>}
                            </span>
                          </td>
                          <td className="dim trunc" title={m.google_email ?? ''}>
                            {m.google_email ?? <span className="muted">not connected</span>}
                            {m.google_email && (
                              <div className="muted" style={{ fontSize: 11 }}>
                                synced {fmtRelative(m.google_last_sync_at)} ·{' '}
                                {m.google_last_sync_count} last pass
                              </div>
                            )}
                          </td>
                          <td className="num">
                            {m.drafts_total}
                            {m.drafts_pending > 0 && (
                              <span className="muted"> ({m.drafts_pending} pending)</span>
                            )}
                          </td>
                          <td className="num">{m.tasks_created}</td>
                          <td className="num">{m.completions}</td>
                          <td className="dim nowrap">{fmtDateTime(m.joined_at)}</td>
                          <td>
                            {m.left_at ? (
                              <span title={m.left_at}>
                                <Pill tone="warn">left {fmtRelative(m.left_at)}</Pill>
                              </span>
                            ) : (
                              <Pill tone="ok">active</Pill>
                            )}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </Card>

            <Card title="Recent activity">
              {d.activity.length === 0 ? (
                <Empty title="Nothing logged" detail="No tasks, drafts, completions or expenses." />
              ) : (
                <div className="timeline">
                  {d.activity.map((a, i) => (
                    <div className="timeline-item" key={`${a.at}-${i}`}>
                      <span className="when" title={a.at}>
                        {fmtDateTime(a.at)}
                      </span>
                      <span className="dim">{titleCase(a.kind)}</span>
                      <span>
                        {a.title} <span className="muted">· {a.where}</span>
                      </span>
                    </div>
                  ))}
                </div>
              )}
            </Card>
          </div>
        </>
      )}
    </Async>
  )
}
