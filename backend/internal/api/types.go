package api

import (
	"fmt"
	"strings"
	"time"
)

// Amsterdam is the household's civil timezone — "today", due phrases and week
// boundaries are computed in it. tzdata is embedded via time/tzdata in main.
var Amsterdam *time.Location

func init() {
	loc, err := time.LoadLocation("Europe/Amsterdam")
	if err != nil {
		loc = time.UTC
	}
	Amsterdam = loc
}

func today() time.Time {
	y, m, d := time.Now().In(Amsterdam).Date()
	return time.Date(y, m, d, 0, 0, 0, 0, time.UTC)
}

// ---- wire DTOs (snake_case per docs/product/API.md) ----

type MemberJSON struct {
	ID          string `json:"id"`
	DisplayName string `json:"display_name"`
	Color       string `json:"color"`
	IsMe        bool   `json:"is_me"`
}

type HouseholdJSON struct {
	ID         string       `json:"id"`
	Name       string       `json:"name"`
	InviteCode string       `json:"invite_code"`
	Members    []MemberJSON `json:"members"`
}

type WeekJSON struct {
	ID        string  `json:"id"`
	Index     int     `json:"index"`
	StartedOn string  `json:"started_on"`
	ClosedAt  *string `json:"closed_at,omitempty"`
}

type TaskJSON struct {
	ID            string  `json:"id"`
	Title         string  `json:"title"`
	Section       string  `json:"section"`
	OwnerMemberID string  `json:"owner_member_id"`
	Weight        int     `json:"weight"`
	Recurrence    string  `json:"recurrence"`
	DueOn         *string `json:"due_on,omitempty"`
	// RecurrenceUntil is the last scheduled day of a bounded repeat, derived
	// from RecurrenceCount when the household picked a number of times.
	RecurrenceUntil      *string `json:"recurrence_until,omitempty"`
	RecurrenceCount      *int    `json:"recurrence_count,omitempty"`
	Done                 bool    `json:"done"`
	DoneByMemberID       *string `json:"done_by_member_id,omitempty"`
	MetaLine             string  `json:"meta_line"`
	GoogleEventURL       *string `json:"google_event_url,omitempty"`
	CalendarSyncState    string  `json:"calendar_sync_state"`
	CalendarLastSyncedAt *string `json:"calendar_last_synced_at,omitempty"`
	CalendarLastError    *string `json:"calendar_last_error,omitempty"`

	// Parsed values kept for server-side occurrence maths, never serialized.
	dueOnDate     *time.Time
	recurrenceEnd *time.Time
	createdAt     time.Time
}

type DraftJSON struct {
	ID                string  `json:"id"`
	FromLabel         string  `json:"from_label"`
	Subject           string  `json:"subject"`
	Summary           *string `json:"summary,omitempty"`
	Urgency           int     `json:"urgency"`
	Title             string  `json:"title"`
	OwnerMemberID     string  `json:"owner_member_id"`
	AmountCents       *int64  `json:"amount_cents,omitempty"`
	DueOn             *string `json:"due_on,omitempty"`
	Reminder          string  `json:"reminder"`
	Status            string  `json:"status"`
	CreatedByMemberID string  `json:"created_by_member_id"`
	SourceFrom        *string `json:"source_from,omitempty"`
	SourcePreview     *string `json:"source_preview,omitempty"`
	Gmail             bool    `json:"gmail"`
	GmailMessageID    *string `json:"gmail_message_id,omitempty"`
	Category          string  `json:"category"`
	NeedsReply        bool    `json:"needs_reply"`
	SuggestedReply    *string `json:"suggested_reply,omitempty"`
	ReplyText         *string `json:"reply_text,omitempty"`
	ReplyStatus       string  `json:"reply_status"`
}

type FeedItemJSON struct {
	Kind string `json:"kind"` // "expense" | "settlement"
	ID   string `json:"id"`
	// expense fields
	Title          string `json:"title,omitempty"`
	AmountCents    int64  `json:"amount_cents"`
	PaidByMemberID string `json:"paid_by_member_id,omitempty"`
	IncurredOn     string `json:"incurred_on,omitempty"`
	Settled        bool   `json:"settled,omitempty"`
	// settlement fields
	FromMemberID string `json:"from_member_id,omitempty"`
	ToMemberID   string `json:"to_member_id,omitempty"`
	CreatedAt    string `json:"created_at,omitempty"`
}

type AppreciationJSON struct {
	ID           string  `json:"id"`
	FromMemberID string  `json:"from_member_id"`
	ToMemberID   string  `json:"to_member_id"`
	Body         *string `json:"body,omitempty"`
	Said         bool    `json:"said"`
}

type TradeJSON struct {
	ID           string `json:"id"`
	TaskID       string `json:"task_id"`
	TaskTitle    string `json:"task_title"`
	FromMemberID string `json:"from_member_id"`
	ToMemberID   string `json:"to_member_id"`
	Accepted     bool   `json:"accepted"`
}

// ---- shared formatting ----

// dateStr formats a civil YYYY-MM-DD in Europe/Amsterdam (not the time's
// own location / UTC), so DATE/timestamptz scans stay on the household day.
func dateStr(t time.Time) string {
	return t.In(Amsterdam).Format("2006-01-02")
}

func strPtr(s string) *string { return &s }

// civilDaysBetween is the signed whole-day distance from `from` to `to` in
// Amsterdam civil dates. Prefer this over Sub().Hours()/24 — DST and
// timezone-aware midnights make hour math off-by-one (tomorrow → TODAY).
func civilDaysBetween(from, to time.Time) int {
	fy, fm, fd := from.In(Amsterdam).Date()
	ty, tm, td := to.In(Amsterdam).Date()
	a := time.Date(fy, fm, fd, 0, 0, 0, 0, time.UTC)
	b := time.Date(ty, tm, td, 0, 0, 0, 0, time.UTC)
	return int(b.Sub(a).Hours() / 24)
}

// metaLine renders the small-caps meta under a task title, e.g.
// "VATTENFALL · 2 DAYS OVER · WEEKLY".
type metaLineInput struct {
	OriginLabel     *string
	Recurrence      string
	DueOn           *time.Time
	RecurrenceUntil *time.Time
	RecurrenceCount *int
	CreatedAt       time.Time
}

func metaLine(in metaLineInput) string {
	var parts []string
	if in.OriginLabel != nil && *in.OriginLabel != "" {
		parts = append(parts, strings.ToUpper(*in.OriginLabel))
	}
	if day, ok := metaDueDay(in); ok {
		parts = append(parts, duePhrase(day))
	}
	switch in.Recurrence {
	case "daily":
		parts = append(parts, "DAILY")
	case "every_2_days":
		parts = append(parts, "EVERY 2 DAYS")
	case "weekly":
		parts = append(parts, "WEEKLY")
	}
	if end := metaEndPhrase(in); end != "" {
		parts = append(parts, end)
	}
	return strings.Join(parts, " · ")
}

// metaDueDay is the day the row should describe. A repeat describes its next
// occurrence rather than its anchor, so a weekly chore never reads as overdue
// while it is still on schedule. Daily and every-two-day repeats have no useful
// date — by construction they are only listed on a day they are due.
func metaDueDay(in metaLineInput) (time.Time, bool) {
	switch in.Recurrence {
	case "none":
		if in.DueOn == nil {
			return time.Time{}, false
		}
		return dateOnly(*in.DueOn), true
	case "daily", "every_2_days":
		return time.Time{}, false
	default:
		anchor := recurrenceAnchor(in.DueOn, in.CreatedAt)
		return nextOccurrence(in.Recurrence, anchor, in.RecurrenceUntil, today())
	}
}

func duePhrase(day time.Time) string {
	switch d := civilDaysBetween(today(), day); {
	case d == 0:
		return "TODAY"
	case d == 1:
		return "TOMORROW"
	case d == -1:
		return "1 DAY OVER"
	case d < -1:
		return fmt.Sprintf("%d DAYS OVER", -d)
	default:
		return strings.ToUpper(day.In(Amsterdam).Format("Jan 2"))
	}
}

// metaEndPhrase answers "until when?" for a bounded repeat, echoing whichever
// way the household expressed it.
func metaEndPhrase(in metaLineInput) string {
	if recurrenceInterval(in.Recurrence) == 0 {
		return ""
	}
	if in.RecurrenceCount != nil {
		return fmt.Sprintf("%d TIMES", *in.RecurrenceCount)
	}
	if in.RecurrenceUntil != nil {
		return "UNTIL " + strings.ToUpper(dateOnly(*in.RecurrenceUntil).In(Amsterdam).Format("Jan 2"))
	}
	return ""
}

// beamCaption mirrors the design's copy exactly (docs/design even-play).
func beamCaption(total, pctMe int, myName, partnerName string) string {
	if total == 0 {
		return "Empty pans. A new week, level by definition"
	}
	diff := pctMe - 50
	if diff < 0 {
		diff = -diff
	}
	switch {
	case diff <= 1:
		return "Level. Enjoy it while it lasts"
	case diff <= 4:
		return "Close to even. Not a competition — but noted"
	default:
		leaning := myName
		if pctMe < 50 {
			leaning = partnerName
		}
		return "Leaning " + leaning + " — mostly the admin and the remembering"
	}
}

func euros(cents int64) string {
	return fmt.Sprintf("€%d.%02d", cents/100, cents%100)
}
