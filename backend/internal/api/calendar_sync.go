package api

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/marcoBroccoli/thisiseven/backend/internal/google"
	"github.com/marcoBroccoli/thisiseven/backend/internal/httpx"
)

var errSharedCalendarNotReady = errors.New("shared calendar is not ready")

// CalendarSyncJSON describes one bounded reconciliation pass. It is
// intentionally additive: a remote deletion never silently removes a local
// todo, and direct Calendar events become normal household todos.
type CalendarSyncJSON struct {
	CalendarID   string `json:"calendar_id"`
	Imported     int    `json:"imported"`
	Updated      int    `json:"updated"`
	Deleted      int    `json:"deleted"`
	Unchanged    int    `json:"unchanged"`
	LastSyncedAt string `json:"last_synced_at"`
}

type calendarMappedTask struct {
	ID    string
	Title string
	DueOn time.Time
}

// POST /v1/calendar/sync reconciles the dedicated household Calendar with
// local dated todos. The shared calendar is the only calendar read, so the
// integration never scans a connected person's primary calendar.
func (a *API) SyncCalendar(w http.ResponseWriter, r *http.Request) {
	m := membership(r)
	if !a.googleReady(w) {
		return
	}
	out, err := a.syncCalendar(r.Context(), m)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, http.StatusConflict, "not_connected", "connect the household Google account first")
		return
	}
	if errors.Is(err, errSharedCalendarNotReady) {
		httpx.Error(w, http.StatusConflict, "calendar_not_ready",
			"add a due date to create the shared Google Calendar first")
		return
	}
	if errors.Is(err, google.ErrInvalidGrant) {
		httpx.Error(w, http.StatusConflict, "google_reconnect_required",
			"Google access expired — reconnect the household account")
		return
	}
	if err != nil {
		httpx.Error(w, http.StatusBadGateway, "calendar_sync_failed", "Google Calendar could not be synchronized")
		return
	}
	httpx.JSON(w, http.StatusOK, out)
}

func (a *API) syncCalendar(ctx context.Context, m *Membership) (CalendarSyncJSON, error) {
	g, err := a.googleAccount(ctx, m.HouseholdID)
	if err != nil {
		return CalendarSyncJSON{}, err
	}
	if g.CalendarID == "" || g.CalendarID == "primary" {
		return CalendarSyncJSON{}, errSharedCalendarNotReady
	}
	token, err := a.Google.AccessToken(ctx, m.HouseholdID, g.RefreshToken, g.ClientKind)
	if errors.Is(err, google.ErrInvalidGrant) {
		_, _ = a.DB.Exec(ctx, `delete from google_accounts where household_id = $1`, m.HouseholdID)
		a.Google.Forget(m.HouseholdID)
	}
	if err != nil {
		return CalendarSyncJSON{}, err
	}

	now := time.Now().UTC()
	events, err := a.Google.ListEvents(ctx, token, g.CalendarID,
		now.AddDate(0, -6, 0), now.AddDate(1, 6, 0))
	if err != nil {
		return CalendarSyncJSON{}, err
	}

	mapped, err := a.mappedCalendarTasks(ctx, m.HouseholdID)
	if err != nil {
		return CalendarSyncJSON{}, err
	}
	out := CalendarSyncJSON{CalendarID: g.CalendarID}
	for _, event := range events {
		if event.ID == "" {
			continue
		}
		local, isMapped := mapped[event.ID]
		isRecurringInstance := false
		if !isMapped && event.RecurringEventID != "" {
			local, isMapped = mapped[event.RecurringEventID]
			isRecurringInstance = isMapped
		}
		// Google expands RRULEs because ListEvents uses singleEvents=true. An
		// expanded instance belongs to its master Even todo; it must never be
		// imported as a second direct Calendar todo. A renamed or cancelled
		// instance is surfaced for review because Even does not model per-date
		// Calendar exceptions yet.
		if isRecurringInstance {
			changed := event.Status == "cancelled"
			message := "A recurring Calendar occurrence was removed"
			if title := strings.TrimSpace(event.Summary); !changed && title != "" && title != local.Title {
				changed = true
				message = "A recurring Calendar occurrence was edited"
			}
			if changed {
				if _, err := a.DB.Exec(ctx, `
					update tasks set calendar_sync_state = 'external_changed',
						calendar_last_synced_at = $1, calendar_last_error = $2
					where id = $3 and household_id = $4`, now, message, local.ID, m.HouseholdID); err != nil {
					return CalendarSyncJSON{}, err
				}
				out.Updated++
			} else {
				if _, err := a.DB.Exec(ctx, `
					update tasks set calendar_last_synced_at = $1
					where id = $2 and household_id = $3`, now, local.ID, m.HouseholdID); err != nil {
					return CalendarSyncJSON{}, err
				}
				out.Unchanged++
			}
			continue
		}
		if event.Status == "cancelled" {
			if isMapped {
				if _, err := a.DB.Exec(ctx, `
					update tasks set calendar_sync_state = 'external_deleted',
						calendar_last_synced_at = $1,
						calendar_last_error = 'Removed in Google Calendar'
					where id = $2 and household_id = $3`, now, local.ID, m.HouseholdID); err != nil {
					return CalendarSyncJSON{}, err
				}
				out.Deleted++
			}
			continue
		}

		dueOn, usable := event.DueOn()
		title := strings.TrimSpace(event.Summary)
		if !usable || title == "" {
			continue
		}
		due, err := time.Parse("2006-01-02", dueOn)
		if err != nil {
			continue
		}

		if isMapped {
			if local.Title != title || dateStr(local.DueOn) != dueOn {
				if _, err := a.DB.Exec(ctx, `
					update tasks set title = $1, due_on = $2, google_event_url = nullif($3, ''),
						calendar_sync_state = 'external_changed', calendar_last_synced_at = $4,
						calendar_last_error = null
					where id = $5 and household_id = $6`,
					title, due, event.HTMLLink, now, local.ID, m.HouseholdID); err != nil {
					return CalendarSyncJSON{}, err
				}
				out.Updated++
			} else {
				if _, err := a.DB.Exec(ctx, `
					update tasks set google_event_url = nullif($1, ''),
						calendar_sync_state = case when calendar_sync_state = 'external_changed'
							then calendar_sync_state else 'synced' end,
						calendar_last_synced_at = $2, calendar_last_error = null
					where id = $3 and household_id = $4`, event.HTMLLink, now, local.ID, m.HouseholdID); err != nil {
					return CalendarSyncJSON{}, err
				}
				out.Unchanged++
			}
			continue
		}

		// Events made directly in the dedicated Calendar become lightweight,
		// editable todos. New items belong to the person who ran the sync;
		// assignment remains a normal todo action in the app.
		tag, err := a.DB.Exec(ctx, `
			insert into tasks (household_id, title, section, owner_member_id, weight,
				recurrence, due_on, origin_label, created_by, google_event_id,
				google_event_url, calendar_sync_state, calendar_last_synced_at)
			values ($1, $2, 'admin', $3, 1, 'none', $4, 'CALENDAR · IMPORTED',
				$3, $5, nullif($6, ''), 'synced', $7)
			on conflict do nothing`,
			m.HouseholdID, title, m.MemberID, due, event.ID, event.HTMLLink, now)
		if err != nil {
			return CalendarSyncJSON{}, err
		}
		if tag.RowsAffected() > 0 {
			out.Imported++
		}
	}

	if _, err := a.DB.Exec(ctx, `
		update google_accounts set calendar_last_sync_at = $1 where household_id = $2`,
		now, m.HouseholdID); err != nil {
		return CalendarSyncJSON{}, err
	}
	out.LastSyncedAt = now.Format(time.RFC3339)
	return out, nil
}

func (a *API) mappedCalendarTasks(ctx context.Context, householdID string) (map[string]calendarMappedTask, error) {
	rows, err := a.DB.Query(ctx, `
		select id, title, due_on, google_event_id from tasks
		where household_id = $1 and archived_at is null and google_event_id is not null
		and due_on is not null`, householdID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	items := map[string]calendarMappedTask{}
	for rows.Next() {
		var item calendarMappedTask
		var eventID string
		if err := rows.Scan(&item.ID, &item.Title, &item.DueOn, &eventID); err != nil {
			return nil, err
		}
		items[eventID] = item
	}
	return items, rows.Err()
}
