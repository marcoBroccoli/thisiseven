import { useEffect, useState } from 'react'
import { ApiError, api, type NotificationDraft, type PickerOption } from '../api'
import { Card, Modal, Pager, Pill, SearchBox, StatusPill } from '../components/Bits'
import { PageHeader } from '../components/Layout'
import { Async, Empty } from '../components/States'
import { useToast } from '../components/Toast'
import { fmtDateTime, fmtNumber } from '../lib/format'
import { useAsync, useDebounced } from '../lib/useAsync'

export function Notifications({ canWrite }: { canWrite: boolean }) {
  const [q, setQ] = useState('')
  const [status, setStatus] = useState('')
  const [page, setPage] = useState(1)
  const [composing, setComposing] = useState(false)
  const debounced = useDebounced(q)
  const state = useAsync(
    () => api.notifications({ q: debounced, status, page }),
    [debounced, status, page],
  )
  const toast = useToast()

  const cancel = async (id: string) => {
    try {
      await api.cancelNotification(id)
      toast('ok', 'Cancelled.')
      state.reload()
    } catch (e) {
      toast('error', e instanceof ApiError ? e.message : 'Could not cancel that.')
    }
  }

  return (
    <>
      <PageHeader
        title="Notifications"
        intro="Compose a push and queue it. Delivery is not wired up yet — these rows sit in the outbox until the APNs sender ships."
        actions={
          canWrite && (
            <button className="btn-primary btn-sm" onClick={() => setComposing(true)}>
              Compose
            </button>
          )
        }
      />

      <Card
        bodyless
        title="Outbox"
        note={state.data?.notice}
        actions={
          <div className="row">
            <select
              aria-label="Filter by status"
              value={status}
              style={{ width: 'auto' }}
              onChange={(e) => {
                setStatus(e.target.value)
                setPage(1)
              }}
            >
              <option value="">All statuses</option>
              <option value="queued">Queued</option>
              <option value="sending">Sending</option>
              <option value="sent">Sent</option>
              <option value="failed">Failed</option>
              <option value="cancelled">Cancelled</option>
            </select>
            <SearchBox
              value={q}
              onChange={(v) => {
                setQ(v)
                setPage(1)
              }}
              placeholder="Search title, body or author"
            />
          </div>
        }
      >
        <Async
          state={state}
          skeletonCols={6}
          isEmpty={(d) => d.rows.length === 0}
          empty={
            <Empty
              title={q || status ? 'No notification matches that' : 'Nothing queued'}
              detail={
                q || status
                  ? 'Clear the filters to see the whole outbox.'
                  : 'Composed pushes will appear here.'
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
                      <th>Message</th>
                      <th>Audience</th>
                      <th className="num">Recipients</th>
                      <th>Scheduled</th>
                      <th>Status</th>
                      <th>By</th>
                      {canWrite && <th />}
                    </tr>
                  </thead>
                  <tbody>
                    {d.rows.map((n) => (
                      <tr key={n.id}>
                        <td>
                          <strong>{n.title}</strong>
                          <div className="dim trunc" title={n.body}>
                            {n.body}
                          </div>
                        </td>
                        <td>
                          <Pill tone={n.audience === 'all' ? 'warn' : 'accent'}>{n.audience}</Pill>
                          {n.household_name && (
                            <div className="muted" style={{ fontSize: 11 }}>
                              {n.household_name}
                            </div>
                          )}
                          {n.user_email && (
                            <div className="muted" style={{ fontSize: 11 }}>
                              {n.user_email}
                            </div>
                          )}
                        </td>
                        <td className="num">{fmtNumber(n.recipient_count)}</td>
                        <td className="dim nowrap">{fmtDateTime(n.scheduled_at)}</td>
                        <td>
                          <StatusPill status={n.status} />
                          {n.error && (
                            <div className="muted trunc" style={{ fontSize: 11 }} title={n.error}>
                              {n.error}
                            </div>
                          )}
                        </td>
                        <td className="dim trunc" title={n.created_by}>
                          {n.created_by}
                          <div className="muted" style={{ fontSize: 11 }}>
                            {fmtDateTime(n.created_at)}
                          </div>
                        </td>
                        {canWrite && (
                          <td className="right">
                            {n.status === 'queued' && (
                              <button className="btn-danger btn-sm" onClick={() => cancel(n.id)}>
                                Cancel
                              </button>
                            )}
                          </td>
                        )}
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

      {composing && (
        <Compose
          onClose={() => setComposing(false)}
          onQueued={() => {
            setComposing(false)
            setPage(1)
            state.reload()
          }}
        />
      )}
    </>
  )
}

function Compose({ onClose, onQueued }: { onClose: () => void; onQueued: () => void }) {
  const [audience, setAudience] = useState<NotificationDraft['audience']>('household')
  const [targetQuery, setTargetQuery] = useState('')
  const [targetId, setTargetId] = useState('')
  const [title, setTitle] = useState('')
  const [body, setBody] = useState('')
  const [when, setWhen] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [options, setOptions] = useState<{
    households: PickerOption[]
    users: PickerOption[]
    all_recipients: number
  } | null>(null)
  const debounced = useDebounced(targetQuery, 250)
  const toast = useToast()

  useEffect(() => {
    let live = true
    api
      .notificationTargets(debounced)
      .then((res) => live && setOptions(res))
      .catch(() => live && setOptions(null))
    return () => {
      live = false
    }
  }, [debounced])

  // Switching audience must drop the previous pick, or "all" could be queued
  // carrying a stale household id the server would then reject.
  useEffect(() => setTargetId(''), [audience])

  const list = audience === 'household' ? (options?.households ?? []) : (options?.users ?? [])
  const recipients =
    audience === 'all'
      ? (options?.all_recipients ?? 0)
      : audience === 'user'
        ? 1
        : list.find((o) => o.id === targetId)
          ? Number((list.find((o) => o.id === targetId)?.sub ?? '0').split(' ')[0]) || 0
          : 0

  const submit = async () => {
    setBusy(true)
    setError(null)
    try {
      const payload: NotificationDraft = {
        audience,
        title: title.trim(),
        body: body.trim(),
        household_id: audience === 'household' ? targetId : null,
        user_id: audience === 'user' ? targetId : null,
        scheduled_at: when ? new Date(when).toISOString() : undefined,
      }
      const res = await api.queueNotification(payload)
      toast('ok', `Queued for ${res.recipient_count} recipient(s). Nothing is delivered yet.`)
      onQueued()
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Could not queue that.')
    } finally {
      setBusy(false)
    }
  }

  const ready =
    title.trim().length > 0 &&
    body.trim().length > 0 &&
    (audience === 'all' || targetId !== '')

  return (
    <Modal
      title="Compose a notification"
      subtitle="It is queued, not sent."
      onClose={() => !busy && onClose()}
      footer={
        <>
          <button onClick={onClose} disabled={busy}>
            Cancel
          </button>
          <button className="btn-primary" onClick={submit} disabled={!ready || busy}>
            {busy ? 'Queueing…' : 'Queue it'}
          </button>
        </>
      }
    >
      <div className="banner warn" style={{ marginBottom: 14 }}>
        Even has no APNs sender yet. This writes a row to the outbox so the message and its
        audience are recorded; nothing reaches a phone.
      </div>

      <label className="field">
        <span className="lbl">Audience</span>
        <select value={audience} onChange={(e) => setAudience(e.target.value as never)}>
          <option value="household">One household</option>
          <option value="user">One user</option>
          <option value="all">Everyone with an active membership</option>
        </select>
      </label>

      {audience !== 'all' && (
        <>
          <label className="field">
            <span className="lbl">Find {audience === 'household' ? 'a household' : 'a user'}</span>
            <input
              type="search"
              value={targetQuery}
              placeholder={audience === 'household' ? 'Household name' : 'Email address'}
              onChange={(e) => setTargetQuery(e.target.value)}
            />
          </label>
          <label className="field">
            <span className="lbl">Pick one</span>
            <select value={targetId} onChange={(e) => setTargetId(e.target.value)}>
              <option value="">— choose —</option>
              {list.map((o) => (
                <option key={o.id} value={o.id}>
                  {o.label} · {o.sub}
                </option>
              ))}
            </select>
            {list.length === 0 && (
              <span className="hint">Nothing matched. Try a shorter search.</span>
            )}
          </label>
        </>
      )}

      <label className="field">
        <span className="lbl">Title</span>
        <input
          type="text"
          maxLength={80}
          value={title}
          onChange={(e) => setTitle(e.target.value)}
        />
        <span className="hint">{title.length}/80</span>
      </label>

      <label className="field">
        <span className="lbl">Body</span>
        <textarea maxLength={400} value={body} onChange={(e) => setBody(e.target.value)} />
        <span className="hint">{body.length}/400</span>
      </label>

      <label className="field">
        <span className="lbl">Send at</span>
        <input type="datetime-local" value={when} onChange={(e) => setWhen(e.target.value)} />
        <span className="hint">Leave empty to queue for immediate delivery.</span>
      </label>

      <div className="banner">
        Estimated recipients: <strong>{fmtNumber(recipients)}</strong>
      </div>

      {error && (
        <div className="banner danger" role="alert" style={{ marginTop: 10 }}>
          {error}
        </div>
      )}
    </Modal>
  )
}
