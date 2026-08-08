import { useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { ApiError, api } from '../api'
import { Card, ColorDot, KV, Modal, Pill, StatusPill, SyncPill } from '../components/Bits'
import { PageHeader } from '../components/Layout'
import { Async, Empty } from '../components/States'
import { useToast } from '../components/Toast'
import { fmtDate, fmtDateTime, fmtMoney, fmtRelative, titleCase } from '../lib/format'
import { useAsync } from '../lib/useAsync'

type Tab = 'members' | 'tasks' | 'weeks' | 'money' | 'activity'

export function HouseholdDetail({ canWrite }: { canWrite: boolean }) {
  const { id = '' } = useParams()
  const state = useAsync(() => api.household(id), [id])
  const [tab, setTab] = useState<Tab>('members')
  const [confirm, setConfirm] = useState<null | { kind: 'regen' } | { kind: 'revoke'; inviteId: string; email: string }>(
    null,
  )
  const [busy, setBusy] = useState(false)
  const toast = useToast()

  const act = async () => {
    if (!confirm) return
    setBusy(true)
    try {
      if (confirm.kind === 'regen') {
        const res = await api.regenerateCode(id)
        toast('ok', `New invite code: ${res.invite_code}`)
      } else {
        await api.revokeInvite(id, confirm.inviteId)
        toast('ok', `Invite to ${confirm.email} revoked.`)
      }
      setConfirm(null)
      state.reload()
    } catch (e) {
      toast('error', e instanceof ApiError ? e.message : 'That did not work.')
    } finally {
      setBusy(false)
    }
  }

  return (
    <Async state={state} skeletonRows={8}>
      {(d) => {
        const pending = d.invites.find((i) => i.status === 'pending')
        return (
          <>
            <PageHeader
              title={d.household.name}
              intro={
                <>
                  Household <span className="mono">{d.household.id}</span> · created{' '}
                  {fmtDateTime(d.household.created_at)}
                </>
              }
              actions={
                <div className="row">
                  <button className="btn-sm" onClick={state.reload}>
                    Refresh
                  </button>
                  {canWrite && (
                    <button className="btn-sm" onClick={() => setConfirm({ kind: 'regen' })}>
                      Regenerate invite code
                    </button>
                  )}
                </div>
              }
            />

            <div className="stack">
              <div className="grid grid-2">
                <Card title="At a glance">
                  <KV
                    items={[
                      ['Invite code', <span className="mono">{d.household.invite_code}</span>],
                      [
                        'Seats',
                        <>
                          {d.household.active_members} active
                          {d.household.departed_members > 0 && (
                            <span className="muted"> · {d.household.departed_members} departed</span>
                          )}
                        </>,
                      ],
                      ['Open tasks', d.household.open_tasks],
                      ['Pending drafts', d.household.pending_drafts],
                      ['Google mailboxes', d.household.google_accounts],
                      ['Last activity', fmtRelative(d.household.last_activity_at)],
                    ]}
                  />
                </Card>

                <Card title="Shared calendar">
                  {d.calendar.calendar_id === 'primary' ? (
                    <div className="banner">
                      No shared calendar yet. Even creates the secondary “Even — {d.household.name}”
                      calendar lazily, the first time a dated todo needs one.
                    </div>
                  ) : (
                    <>
                      <KV
                        items={[
                          [
                            'Calendar id',
                            <span className="mono trunc" title={d.calendar.calendar_id}>
                              {d.calendar.calendar_id}
                            </span>,
                          ],
                          ['Owner', d.calendar.owner_name ?? <span className="muted">unknown</span>],
                          ['Last sync', fmtRelative(d.calendar.last_sync_at)],
                        ]}
                      />
                      <div className="row" style={{ marginTop: 12 }}>
                        <Pill tone="ok">{d.calendar.synced} synced</Pill>
                        {d.calendar.retry_required > 0 && (
                          <Pill tone="danger">{d.calendar.retry_required} retry required</Pill>
                        )}
                        {d.calendar.external_deleted > 0 && (
                          <Pill tone="warn">{d.calendar.external_deleted} deleted in Google</Pill>
                        )}
                        {d.calendar.external_changed > 0 && (
                          <Pill tone="info">{d.calendar.external_changed} changed in Google</Pill>
                        )}
                        <Pill>{d.calendar.not_scheduled} not scheduled</Pill>
                      </div>
                    </>
                  )}
                </Card>
              </div>

              <Card title={`Invites (${d.invites.length})`} bodyless>
                {d.invites.length === 0 ? (
                  <Empty
                    title="No invites"
                    detail="Nobody has been invited by email. The invite code still works."
                  />
                ) : (
                  <div className="table-wrap">
                    <table className="data">
                      <thead>
                        <tr>
                          <th>Email</th>
                          <th>Invited by</th>
                          <th>Status</th>
                          <th>Sent</th>
                          <th>Responded</th>
                          {canWrite && <th />}
                        </tr>
                      </thead>
                      <tbody>
                        {d.invites.map((i) => (
                          <tr key={i.id}>
                            <td>{i.email}</td>
                            <td className="dim">{i.invited_by}</td>
                            <td>
                              <StatusPill status={i.status} />
                            </td>
                            <td className="dim nowrap">{fmtDateTime(i.created_at)}</td>
                            <td className="dim nowrap">{fmtDateTime(i.responded_at)}</td>
                            {canWrite && (
                              <td className="right">
                                {i.status === 'pending' && (
                                  <button
                                    className="btn-danger btn-sm"
                                    onClick={() =>
                                      setConfirm({ kind: 'revoke', inviteId: i.id, email: i.email })
                                    }
                                  >
                                    Revoke
                                  </button>
                                )}
                              </td>
                            )}
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}
              </Card>

              <div>
                <div className="tabs" role="tablist">
                  {(
                    [
                      ['members', `Members (${d.members.length})`],
                      ['tasks', `Tasks (${d.tasks.length})`],
                      ['weeks', `Weeks (${d.weeks.length})`],
                      ['money', `Money (${d.money.length})`],
                      ['activity', 'Activity'],
                    ] as [Tab, string][]
                  ).map(([key, label]) => (
                    <button
                      key={key}
                      role="tab"
                      aria-selected={tab === key}
                      onClick={() => setTab(key)}
                    >
                      {label}
                    </button>
                  ))}
                </div>

                {tab === 'members' && <MembersTable rows={d.members} />}
                {tab === 'tasks' && <TasksTable rows={d.tasks} />}
                {tab === 'weeks' && <WeeksTable rows={d.weeks} />}
                {tab === 'money' && <MoneyTable rows={d.money} />}
                {tab === 'activity' && (
                  <Card>
                    {d.activity.length === 0 ? (
                      <Empty title="Nothing yet" detail="No tasks, drafts, money or completions." />
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
                )}
              </div>
            </div>

            {confirm && (
              <Modal
                title={confirm.kind === 'regen' ? 'Regenerate invite code?' : 'Revoke this invite?'}
                onClose={() => !busy && setConfirm(null)}
                footer={
                  <>
                    <button onClick={() => setConfirm(null)} disabled={busy}>
                      Cancel
                    </button>
                    <button className="btn-primary" onClick={act} disabled={busy}>
                      {busy ? 'Working…' : confirm.kind === 'regen' ? 'Regenerate' : 'Revoke'}
                    </button>
                  </>
                }
              >
                {confirm.kind === 'regen' ? (
                  <p>
                    The current code <span className="mono">{d.household.invite_code}</span> stops
                    working immediately. Anyone mid-join will have to be given the new one. The old
                    value is kept in the audit log.
                  </p>
                ) : (
                  <p>
                    <strong>{confirm.email}</strong> will no longer see this household waiting for
                    them. The seat stays open and the household can invite again.
                  </p>
                )}
                {pending && confirm.kind === 'regen' && (
                  <div className="banner warn">
                    There is also a pending email invite to {pending.email}. Regenerating the code
                    does not touch it.
                  </div>
                )}
              </Modal>
            )}
          </>
        )
      }}
    </Async>
  )
}

function MembersTable({ rows }: { rows: import('../api').MemberRow[] }) {
  if (rows.length === 0)
    return (
      <Card>
        <Empty title="No members" detail="Every seat in this household is empty." />
      </Card>
    )
  return (
    <Card bodyless>
      <div className="table-wrap">
        <table className="data">
          <thead>
            <tr>
              <th>Member</th>
              <th>Account</th>
              <th>Google</th>
              <th className="num">Drafts</th>
              <th className="num">Done</th>
              <th>Joined</th>
              <th>State</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((m) => (
              <tr key={m.id}>
                <td>
                  <span className="row" style={{ gap: 6 }}>
                    <ColorDot color={m.color} />
                    {m.display_name}
                    {m.is_calendar_owner && <Pill tone="accent">calendar owner</Pill>}
                  </span>
                </td>
                <td>
                  <Link to={`/users/${m.user_id}`}>{m.email ?? m.user_id.slice(0, 8)}</Link>
                </td>
                <td className="dim">
                  {m.google_email ? (
                    <>
                      <div className="trunc" title={m.google_email}>
                        {m.google_email}
                      </div>
                      <div className="muted" style={{ fontSize: 11 }}>
                        synced {fmtRelative(m.google_last_sync_at)}
                        {m.calendar_listed_at ? ' · calendar added' : ' · calendar not added'}
                      </div>
                    </>
                  ) : (
                    <span className="muted">not connected</span>
                  )}
                </td>
                <td className="num">{m.drafts_total}</td>
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
    </Card>
  )
}

function TasksTable({ rows }: { rows: import('../api').TaskRow[] }) {
  const [showArchived, setShowArchived] = useState(false)
  const visible = showArchived ? rows : rows.filter((t) => !t.archived_at)
  const archivedCount = rows.length - rows.filter((t) => !t.archived_at).length
  return (
    <Card
      bodyless
      title="Tasks"
      actions={
        archivedCount > 0 && (
          <button className="btn-sm" onClick={() => setShowArchived((v) => !v)}>
            {showArchived ? 'Hide' : 'Show'} {archivedCount} archived
          </button>
        )
      }
    >
      {visible.length === 0 ? (
        <Empty title="No tasks" detail="This household has not created any todos yet." />
      ) : (
        <div className="table-wrap">
          <table className="data">
            <thead>
              <tr>
                <th>Title</th>
                <th>Section</th>
                <th>Owner</th>
                <th className="num">Weight</th>
                <th>Repeat</th>
                <th>Due</th>
                <th>Calendar</th>
              </tr>
            </thead>
            <tbody>
              {visible.map((t) => (
                <tr key={t.id} style={t.archived_at ? { opacity: 0.55 } : undefined}>
                  <td>
                    <div className="trunc" title={t.title}>
                      {t.title}
                    </div>
                    {t.origin_label && (
                      <div className="muted" style={{ fontSize: 11 }}>
                        from {t.origin_label}
                      </div>
                    )}
                  </td>
                  <td className="dim">{t.section}</td>
                  <td className="dim">{t.owner_name}</td>
                  <td className="num">{t.weight}</td>
                  <td className="dim">{t.recurrence === 'none' ? '—' : t.recurrence}</td>
                  <td className="dim nowrap">
                    {t.due_on ? (
                      <>
                        {fmtDate(t.due_on)}
                        {t.due_time && <span className="muted"> {t.due_time}</span>}
                      </>
                    ) : (
                      <span className="muted">—</span>
                    )}
                  </td>
                  <td>
                    <SyncPill state={t.calendar_sync_state} />
                    {t.calendar_last_error && (
                      <div
                        className="muted trunc"
                        style={{ fontSize: 11 }}
                        title={t.calendar_last_error}
                      >
                        {t.calendar_last_error}
                      </div>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </Card>
  )
}

function WeeksTable({ rows }: { rows: import('../api').WeekRow[] }) {
  if (rows.length === 0)
    return (
      <Card>
        <Empty title="No weeks" detail="The weekly ritual has not started for this household." />
      </Card>
    )
  return (
    <Card bodyless>
      <div className="table-wrap">
        <table className="data">
          <thead>
            <tr>
              <th className="num">Week</th>
              <th>Started</th>
              <th>Closed</th>
              <th className="num">Completions</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((w) => (
              <tr key={w.id}>
                <td className="num">{w.index}</td>
                <td className="dim">{fmtDate(w.started_on)}</td>
                <td>
                  {w.closed_at ? (
                    <span className="dim">{fmtDateTime(w.closed_at)}</span>
                  ) : (
                    <Pill tone="accent">open</Pill>
                  )}
                </td>
                <td className="num">{w.completions}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </Card>
  )
}

function MoneyTable({ rows }: { rows: import('../api').MoneyRow[] }) {
  if (rows.length === 0)
    return (
      <Card>
        <Empty title="No money yet" detail="No expenses recorded and nothing settled." />
      </Card>
    )
  return (
    <Card bodyless>
      <div className="table-wrap">
        <table className="data">
          <thead>
            <tr>
              <th>What</th>
              <th>Who</th>
              <th className="num">Amount</th>
              <th>When</th>
              <th>State</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((m) => (
              <tr key={`${m.kind}-${m.id}`}>
                <td>
                  {m.title}
                  {m.counterparty && <span className="muted"> → {m.counterparty}</span>}
                </td>
                <td className="dim">{m.who}</td>
                <td className="num mono">{fmtMoney(m.amount_cents)}</td>
                <td className="dim nowrap">{fmtDateTime(m.when)}</td>
                <td>
                  {m.kind === 'settlement' ? (
                    <Pill tone="accent">settlement</Pill>
                  ) : m.settled ? (
                    <Pill tone="ok">settled</Pill>
                  ) : (
                    <Pill tone="warn">open</Pill>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </Card>
  )
}
