// The single seam between the SPA and the Go service.
//
// Every response goes through `request`, so there is exactly one place that
// knows about the {error:{code,message}} envelope, one place that notices a 401
// and one place that decides what an operator is shown when the server is down.

export class ApiError extends Error {
  code: string
  status: number
  constructor(status: number, code: string, message: string) {
    super(message)
    this.status = status
    this.code = code
  }
}

/** Fired on any 401 so the shell can drop back to the login screen without
 *  every caller having to check. */
export const SESSION_LOST = 'even-admin:session-lost'

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  let res: Response
  try {
    res = await fetch(`/api${path}`, {
      credentials: 'same-origin',
      headers: init?.body ? { 'Content-Type': 'application/json' } : undefined,
      ...init,
    })
  } catch (e) {
    throw new ApiError(0, 'offline', 'Could not reach the admin service.')
  }

  if (res.status === 204) return undefined as T

  const text = await res.text()
  let body: unknown = null
  if (text) {
    try {
      body = JSON.parse(text)
    } catch {
      throw new ApiError(res.status, 'bad_response', 'The server sent something that is not JSON.')
    }
  }

  if (!res.ok) {
    const env = body as { error?: { code?: string; message?: string } } | null
    const code = env?.error?.code ?? 'error'
    const message = env?.error?.message ?? `Request failed (${res.status}).`
    if (res.status === 401 && code === 'no_session') {
      window.dispatchEvent(new CustomEvent(SESSION_LOST))
    }
    throw new ApiError(res.status, code, message)
  }
  return body as T
}

const qs = (params: Record<string, string | number | undefined>) => {
  const out = new URLSearchParams()
  for (const [k, v] of Object.entries(params)) {
    if (v !== undefined && v !== '' && v !== null) out.set(k, String(v))
  }
  const s = out.toString()
  return s ? `?${s}` : ''
}

export const api = {
  // auth
  me: () => request<{ admin: Admin }>('/auth/me'),
  login: (email: string, password: string) =>
    request<LoginStage>('/auth/login', {
      method: 'POST',
      body: JSON.stringify({ email, password }),
    }),
  totp: (code: string) =>
    request<{ admin: Admin }>('/auth/totp', { method: 'POST', body: JSON.stringify({ code }) }),
  logout: () => request<{ ok: boolean }>('/auth/logout', { method: 'POST' }),
  changePassword: (current_password: string, new_password: string) =>
    request<{ ok: boolean }>('/auth/password', {
      method: 'POST',
      body: JSON.stringify({ current_password, new_password }),
    }),

  // read
  dashboard: () => request<Dashboard>('/dashboard'),
  users: (p: PageParams) => request<Paged<UserRow>>(`/users${qs(p)}`),
  user: (id: string) => request<UserDetail>(`/users/${id}`),
  households: (p: PageParams) => request<Paged<HouseholdRow>>(`/households${qs(p)}`),
  household: (id: string) => request<HouseholdDetail>(`/households/${id}`),
  ops: () => request<Ops>('/ops'),
  settings: () => request<{ rows: Setting[]; notice: string }>('/settings'),
  notifications: (p: PageParams & { status?: string }) =>
    request<Paged<Outbox> & { notice: string }>(`/notifications${qs(p)}`),
  notificationTargets: (q?: string) =>
    request<{ households: PickerOption[]; users: PickerOption[]; all_recipients: number }>(
      `/notifications/targets${qs({ q })}`,
    ),
  audit: (p: PageParams & { action?: string }) =>
    request<Paged<AuditRow> & { actions: string[] }>(`/audit${qs(p)}`),
  health: () => request<Health>('/health'),

  // write
  revokeInvite: (householdId: string, inviteId: string) =>
    request<{ ok: boolean }>(`/households/${householdId}/invites/${inviteId}/revoke`, {
      method: 'POST',
    }),
  regenerateCode: (householdId: string) =>
    request<{ ok: boolean; invite_code: string }>(
      `/households/${householdId}/invite-code/regenerate`,
      { method: 'POST' },
    ),
  upsertSetting: (key: string, value: unknown, description?: string) =>
    request<{ ok: boolean }>(`/settings/${encodeURIComponent(key)}`, {
      method: 'PUT',
      body: JSON.stringify({ key, value, description: description ?? null }),
    }),
  deleteSetting: (key: string) =>
    request<{ ok: boolean }>(`/settings/${encodeURIComponent(key)}`, { method: 'DELETE' }),
  queueNotification: (payload: NotificationDraft) =>
    request<{ ok: boolean; id: string; recipient_count: number }>('/notifications', {
      method: 'POST',
      body: JSON.stringify(payload),
    }),
  cancelNotification: (id: string) =>
    request<{ ok: boolean }>(`/notifications/${id}/cancel`, { method: 'POST' }),
}

// ------------------------------------------------------------------ types

export type PageParams = { q?: string; page?: number; per_page?: number }

export type PageMeta = { page: number; per_page: number; total: number; total_pages: number }
export type Paged<T> = { rows: T[]; page: PageMeta }

export type Admin = {
  id: string
  email: string
  role: 'admin' | 'viewer'
  mfa_enrolled: boolean
  session_expires_at: string
}

export type LoginStage = {
  stage: 'totp' | 'enroll'
  otpauth_uri?: string
  secret?: string
  issuer?: string
  account?: string
}

export type StatTile = { key: string; label: string; value: number; sub?: string }
export type TrendSeries = { key: string; label: string; points: number[] }
export type AttentionRow = {
  kind: string
  label: string
  count: number
  href: string
  severity: 'warn' | 'info'
}
export type Dashboard = {
  tiles: StatTile[]
  days: string[]
  series: TrendSeries[]
  attention: AttentionRow[]
  generated_at: string
}

export type UserRow = {
  id: string
  email: string | null
  created_at: string
  last_sign_in_at: string | null
  provider: string | null
  confirmed: boolean
  household_count: number
  active_membership_count: number
  display_name: string | null
  last_activity_at: string | null
}

export type UserMembership = {
  member_id: string
  household_id: string
  household_name: string
  display_name: string
  color: string
  has_avatar: boolean
  joined_at: string
  left_at: string | null
  google_email: string | null
  google_last_sync_at: string | null
  google_last_sync_count: number
  drafts_pending: number
  drafts_total: number
  tasks_created: number
  completions: number
  is_calendar_owner: boolean
}

export type ActivityRow = { at: string; kind: string; title: string; where: string }

export type InviteRow = {
  id: string
  household_id: string
  household_name: string
  email: string
  status: 'pending' | 'accepted' | 'declined' | 'revoked'
  invited_by: string
  created_at: string
  responded_at: string | null
}

export type UserDetail = {
  user: UserRow
  memberships: UserMembership[]
  invites: InviteRow[]
  activity: ActivityRow[]
}

export type HouseholdRow = {
  id: string
  name: string
  invite_code: string
  created_at: string
  active_members: number
  departed_members: number
  open_tasks: number
  pending_drafts: number
  google_accounts: number
  pending_invite_email: string | null
  calendar_id: string
  last_activity_at: string | null
  calendar_sync_issues: number
}

export type MemberRow = {
  id: string
  user_id: string
  email: string | null
  display_name: string
  color: string
  has_avatar: boolean
  joined_at: string
  left_at: string | null
  google_email: string | null
  google_last_sync_at: string | null
  google_last_sync_count: number
  calendar_listed_at: string | null
  is_calendar_owner: boolean
  drafts_total: number
  completions: number
}

export type WeekRow = {
  id: string
  index: number
  started_on: string
  closed_at: string | null
  completions: number
}

export type CalendarSyncState =
  | 'not_scheduled'
  | 'synced'
  | 'external_changed'
  | 'external_deleted'
  | 'retry_required'

export type TaskRow = {
  id: string
  title: string
  section: 'chore' | 'admin'
  weight: number
  recurrence: string
  due_on: string | null
  due_time: string | null
  owner_name: string
  owner_member_id: string
  archived_at: string | null
  created_at: string
  calendar_sync_state: CalendarSyncState
  calendar_last_synced_at: string | null
  calendar_last_error: string | null
  google_event_url: string | null
  origin_label: string | null
  done_in_open_week: boolean
}

export type MoneyRow = {
  id: string
  kind: 'expense' | 'settlement'
  title: string
  amount_cents: number
  who: string
  when: string
  settled: boolean
  counterparty: string | null
}

export type CalendarInfo = {
  calendar_id: string
  owner_member_id: string | null
  owner_name: string | null
  last_sync_at: string | null
  synced: number
  retry_required: number
  external_deleted: number
  external_changed: number
  not_scheduled: number
}

export type HouseholdDetail = {
  household: HouseholdRow
  members: MemberRow[]
  weeks: WeekRow[]
  tasks: TaskRow[]
  invites: InviteRow[]
  money: MoneyRow[]
  activity: ActivityRow[]
  calendar: CalendarInfo
}

export type MailboxRow = {
  member_id: string
  member_name: string
  household_id: string
  household_name: string
  email: string
  client_kind: string
  connected_at: string
  last_sync_at: string | null
  last_sync_count: number
  stale_hours: number | null
  scanned_messages: number
  actionable_messages: number
  drafts_pending: number
  drafts_approved: number
  drafts_dismissed: number
  drafts_needing_reply: number
  member_left: boolean
}

export type CalendarIssueRow = {
  task_id: string
  title: string
  household_id: string
  household_name: string
  owner_name: string
  calendar_sync_state: CalendarSyncState
  calendar_last_error: string | null
  calendar_last_synced_at: string | null
  due_on: string | null
  google_event_url: string | null
}

export type Ops = {
  mailboxes: MailboxRow[]
  calendar_issues: CalendarIssueRow[]
  draft_funnel: { label: string; count: number }[]
  totals: Record<string, number>
  generated_at: string
}

export type Setting = {
  key: string
  value: unknown
  description: string | null
  updated_at: string
  updated_by: string | null
}

export type Outbox = {
  id: string
  audience: 'all' | 'household' | 'user'
  household_id: string | null
  household_name: string | null
  user_id: string | null
  user_email: string | null
  title: string
  body: string
  scheduled_at: string
  status: 'queued' | 'sending' | 'sent' | 'failed' | 'cancelled'
  recipient_count: number
  delivered_count: number
  error: string | null
  created_by: string
  created_at: string
  sent_at: string | null
}

export type NotificationDraft = {
  audience: 'all' | 'household' | 'user'
  household_id?: string | null
  user_id?: string | null
  title: string
  body: string
  scheduled_at?: string
}

export type PickerOption = { id: string; label: string; sub: string }

export type AuditRow = {
  id: number
  actor_email: string
  action: string
  target_type: string | null
  target_id: string | null
  summary: string | null
  before: unknown
  after: unknown
  ip: string | null
  created_at: string
}

export type Health = {
  dependencies: { name: string; ok: boolean; detail: string; latency_ms: number }[]
  pool: Record<string, number>
  database: { name?: string; size?: string; backends?: number }
  tables: { schema: string; table: string; rows: number }[]
  admin_migrations: string[]
  logins_24h: Record<string, number>
  checked_at: string
}
