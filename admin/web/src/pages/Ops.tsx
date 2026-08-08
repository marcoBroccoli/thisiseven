import { Link } from 'react-router-dom'
import { api } from '../api'
import { Card, Pill, SyncPill } from '../components/Bits'
import { Funnel } from '../components/Chart'
import { PageHeader } from '../components/Layout'
import { Async, Empty } from '../components/States'
import { fmtDate, fmtNumber, fmtRelative } from '../lib/format'
import { useAsync } from '../lib/useAsync'

export function Ops() {
  const state = useAsync(() => api.ops(), [])

  return (
    <>
      <PageHeader
        title="Gmail & Calendar"
        intro="The two integrations that fail quietly. A mailbox that has not synced in a day and a todo stuck on retry are the two things worth chasing."
        actions={
          <button className="btn-sm" onClick={state.reload}>
            Refresh
          </button>
        }
      />
      <Async state={state} skeletonRows={6} skeletonCols={5}>
        {(d) => (
          <div className="stack">
            <div className="grid grid-tiles">
              {[
                ['Connected mailboxes', d.totals.mailboxes, ''],
                ['Stale over 24h', d.totals.stale_mailboxes, 'warn'],
                ['Retry required', d.totals.retry_required, 'danger'],
                ['Deleted in Google', d.totals.external_deleted, 'warn'],
                ['Drafts pending', d.totals.drafts_pending, ''],
                ['Awaiting a reply', d.totals.drafts_need_reply, ''],
              ].map(([label, value, tone]) => (
                <div className="card tile" key={label as string}>
                  <div className="label">{label as string}</div>
                  <div
                    className="value"
                    style={
                      tone && (value as number) > 0
                        ? { color: tone === 'danger' ? 'var(--danger)' : 'var(--warn)' }
                        : undefined
                    }
                  >
                    {fmtNumber((value as number) ?? 0)}
                  </div>
                </div>
              ))}
            </div>

            <div className="grid grid-2">
              <Card title="Email → todo funnel">
                <Funnel rows={d.draft_funnel} />
              </Card>
              <Card title="Calendar states">
                <div className="row">
                  <Pill tone="danger">{d.totals.retry_required} retry required</Pill>
                  <Pill tone="warn">{d.totals.external_deleted} deleted in Google</Pill>
                  <Pill tone="info">{d.totals.external_changed} changed in Google</Pill>
                  <Pill tone="ok">{d.totals.households_with_cal} households with a shared calendar</Pill>
                </div>
                <p className="dim" style={{ marginBottom: 0 }}>
                  “Deleted in Google” keeps the todo alive in Even until someone restores or
                  archives it — that is the local-first rule, not a bug. “Retry required” is a
                  write evend could not land and will attempt again.
                </p>
              </Card>
            </div>

            <Card title={`Connected mailboxes (${d.mailboxes.length})`} bodyless>
              {d.mailboxes.length === 0 ? (
                <Empty
                  title="No Google connections"
                  detail="Nobody has connected a mailbox, so the inbox stays empty by design."
                />
              ) : (
                <div className="table-wrap">
                  <table className="data">
                    <thead>
                      <tr>
                        <th>Mailbox</th>
                        <th>Member</th>
                        <th>Last sync</th>
                        <th className="num">Last pass</th>
                        <th className="num">Scanned</th>
                        <th className="num">Actionable</th>
                        <th className="num">Pending</th>
                        <th className="num">Needs reply</th>
                      </tr>
                    </thead>
                    <tbody>
                      {d.mailboxes.map((m) => (
                        <tr key={m.member_id}>
                          <td>
                            <div className="trunc" title={m.email}>
                              {m.email}
                            </div>
                            <div className="muted" style={{ fontSize: 11 }}>
                              {m.client_kind} client · connected {fmtRelative(m.connected_at)}
                            </div>
                          </td>
                          <td>
                            <Link to={`/households/${m.household_id}`}>{m.member_name}</Link>
                            <div className="muted" style={{ fontSize: 11 }}>
                              {m.household_name}
                              {m.member_left && ' · departed'}
                            </div>
                          </td>
                          <td className="nowrap">
                            {m.stale_hours === null ? (
                              <Pill tone="warn">never</Pill>
                            ) : m.stale_hours >= 24 ? (
                              <Pill tone="warn">{fmtRelative(m.last_sync_at)}</Pill>
                            ) : (
                              <span className="dim">{fmtRelative(m.last_sync_at)}</span>
                            )}
                          </td>
                          <td className="num">{m.last_sync_count}</td>
                          <td className="num">{m.scanned_messages}</td>
                          <td className="num">{m.actionable_messages}</td>
                          <td className="num">
                            {m.drafts_pending > 0 ? (
                              <Pill tone="warn">{m.drafts_pending}</Pill>
                            ) : (
                              <span className="muted">0</span>
                            )}
                          </td>
                          <td className="num">
                            {m.drafts_needing_reply > 0 ? (
                              <Pill tone="info">{m.drafts_needing_reply}</Pill>
                            ) : (
                              <span className="muted">0</span>
                            )}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </Card>

            <Card
              title={`Calendar issues (${d.calendar_issues.length})`}
              bodyless
              note={
                d.calendar_issues.length >= 200
                  ? 'Showing the first 200 — worst state first.'
                  : undefined
              }
            >
              {d.calendar_issues.length === 0 ? (
                <Empty
                  title="Every todo is in sync"
                  detail="No retries pending, nothing deleted behind Even's back."
                />
              ) : (
                <div className="table-wrap">
                  <table className="data">
                    <thead>
                      <tr>
                        <th>Todo</th>
                        <th>Household</th>
                        <th>Owner</th>
                        <th>Due</th>
                        <th>State</th>
                        <th>Error</th>
                      </tr>
                    </thead>
                    <tbody>
                      {d.calendar_issues.map((c) => (
                        <tr key={c.task_id}>
                          <td>
                            <div className="trunc" title={c.title}>
                              {c.google_event_url ? (
                                <a href={c.google_event_url} target="_blank" rel="noreferrer">
                                  {c.title}
                                </a>
                              ) : (
                                c.title
                              )}
                            </div>
                          </td>
                          <td>
                            <Link to={`/households/${c.household_id}`}>{c.household_name}</Link>
                          </td>
                          <td className="dim">{c.owner_name}</td>
                          <td className="dim nowrap">
                            {c.due_on ? fmtDate(c.due_on) : <span className="muted">—</span>}
                          </td>
                          <td>
                            <SyncPill state={c.calendar_sync_state} />
                          </td>
                          <td className="dim trunc" title={c.calendar_last_error ?? ''}>
                            {c.calendar_last_error ?? <span className="muted">—</span>}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </Card>
          </div>
        )}
      </Async>
    </>
  )
}
