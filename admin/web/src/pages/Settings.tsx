import { useState } from 'react'
import { ApiError, api, type Setting } from '../api'
import { Card, Modal } from '../components/Bits'
import { PageHeader } from '../components/Layout'
import { Async, Empty } from '../components/States'
import { useToast } from '../components/Toast'
import { fmtDateTime } from '../lib/format'
import { useAsync } from '../lib/useAsync'

export function Settings({ canWrite }: { canWrite: boolean }) {
  const state = useAsync(() => api.settings(), [])
  const [editing, setEditing] = useState<Setting | 'new' | null>(null)
  const [deleting, setDeleting] = useState<Setting | null>(null)
  const toast = useToast()

  const remove = async () => {
    if (!deleting) return
    try {
      await api.deleteSetting(deleting.key)
      toast('ok', `Deleted ${deleting.key}.`)
      setDeleting(null)
      state.reload()
    } catch (e) {
      toast('error', e instanceof ApiError ? e.message : 'Could not delete that.')
    }
  }

  return (
    <>
      <PageHeader
        title="Settings"
        intro="Operational key/value the console owns."
        actions={
          canWrite && (
            <button className="btn-primary btn-sm" onClick={() => setEditing('new')}>
              New key
            </button>
          )
        }
      />
      <Card bodyless note={state.data?.notice}>
        <Async
          state={state}
          skeletonCols={4}
          isEmpty={(d) => d.rows.length === 0}
          empty={<Empty title="No settings" detail="Create a key to record operational intent." />}
        >
          {(d) => (
            <div className="table-wrap">
              <table className="data">
                <thead>
                  <tr>
                    <th>Key</th>
                    <th>Value</th>
                    <th>Description</th>
                    <th>Updated</th>
                    {canWrite && <th />}
                  </tr>
                </thead>
                <tbody>
                  {d.rows.map((s) => (
                    <tr key={s.key}>
                      <td className="mono">{s.key}</td>
                      <td className="mono trunc" title={JSON.stringify(s.value)}>
                        {JSON.stringify(s.value)}
                      </td>
                      <td className="dim">{s.description ?? <span className="muted">—</span>}</td>
                      <td className="dim nowrap">
                        {fmtDateTime(s.updated_at)}
                        <div className="muted" style={{ fontSize: 11 }}>
                          {s.updated_by ?? '—'}
                        </div>
                      </td>
                      {canWrite && (
                        <td className="right nowrap">
                          <button className="btn-sm" onClick={() => setEditing(s)}>
                            Edit
                          </button>{' '}
                          <button className="btn-danger btn-sm" onClick={() => setDeleting(s)}>
                            Delete
                          </button>
                        </td>
                      )}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Async>
      </Card>

      {editing && (
        <SettingEditor
          setting={editing === 'new' ? null : editing}
          onClose={() => setEditing(null)}
          onSaved={() => {
            setEditing(null)
            state.reload()
          }}
        />
      )}

      {deleting && (
        <Modal
          title={`Delete ${deleting.key}?`}
          onClose={() => setDeleting(null)}
          footer={
            <>
              <button onClick={() => setDeleting(null)}>Cancel</button>
              <button className="btn-danger" onClick={remove}>
                Delete
              </button>
            </>
          }
        >
          <p>
            The key and its value go away. The current value is kept in the audit log, so this is
            recoverable by hand.
          </p>
        </Modal>
      )}
    </>
  )
}

function SettingEditor({
  setting,
  onClose,
  onSaved,
}: {
  setting: Setting | null
  onClose: () => void
  onSaved: () => void
}) {
  const [key, setKey] = useState(setting?.key ?? '')
  const [raw, setRaw] = useState(JSON.stringify(setting?.value ?? '', null, 2))
  const [description, setDescription] = useState(setting?.description ?? '')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const toast = useToast()

  // The value is jsonb, so it is validated here before it is sent — a syntax
  // error should be a red line under the textarea, not a 400 from the server.
  let parsed: unknown = null
  let parseError: string | null = null
  try {
    parsed = JSON.parse(raw)
  } catch (e) {
    parseError = e instanceof Error ? e.message : 'Not valid JSON.'
  }

  const save = async () => {
    setBusy(true)
    setError(null)
    try {
      await api.upsertSetting(key.trim(), parsed, description.trim() || undefined)
      toast('ok', `Saved ${key.trim()}.`)
      onSaved()
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Could not save that.')
    } finally {
      setBusy(false)
    }
  }

  return (
    <Modal
      title={setting ? `Edit ${setting.key}` : 'New setting'}
      onClose={() => !busy && onClose()}
      footer={
        <>
          <button onClick={onClose} disabled={busy}>
            Cancel
          </button>
          <button
            className="btn-primary"
            onClick={save}
            disabled={busy || !!parseError || key.trim() === ''}
          >
            {busy ? 'Saving…' : 'Save'}
          </button>
        </>
      }
    >
      <label className="field">
        <span className="lbl">Key</span>
        <input
          type="text"
          className="mono"
          value={key}
          disabled={!!setting}
          onChange={(e) => setKey(e.target.value)}
        />
        <span className="hint">Lowercase letters, digits and underscores.</span>
      </label>
      <label className="field">
        <span className="lbl">Value (JSON)</span>
        <textarea className="mono" value={raw} onChange={(e) => setRaw(e.target.value)} />
        {parseError ? (
          <span className="hint" style={{ color: 'var(--danger)' }}>
            {parseError}
          </span>
        ) : (
          <span className="hint">
            Any JSON: <code>true</code>, <code>30</code>, <code>"text"</code>, an object.
          </span>
        )}
      </label>
      <label className="field">
        <span className="lbl">Description</span>
        <input type="text" value={description} onChange={(e) => setDescription(e.target.value)} />
      </label>
      {error && (
        <div className="banner danger" role="alert">
          {error}
        </div>
      )}
    </Modal>
  )
}
