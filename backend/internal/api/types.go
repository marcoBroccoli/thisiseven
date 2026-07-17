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
	ID             string  `json:"id"`
	Title          string  `json:"title"`
	Section        string  `json:"section"`
	OwnerMemberID  string  `json:"owner_member_id"`
	Weight         int     `json:"weight"`
	Recurrence     string  `json:"recurrence"`
	DueOn          *string `json:"due_on,omitempty"`
	Done           bool    `json:"done"`
	DoneByMemberID *string `json:"done_by_member_id,omitempty"`
	MetaLine       string  `json:"meta_line"`
	GoogleEventURL *string `json:"google_event_url,omitempty"`
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
}

type FeedItemJSON struct {
	Kind string `json:"kind"` // "expense" | "settlement"
	ID   string `json:"id"`
	// expense fields
	Title          string  `json:"title,omitempty"`
	AmountCents    int64   `json:"amount_cents"`
	PaidByMemberID string  `json:"paid_by_member_id,omitempty"`
	IncurredOn     string  `json:"incurred_on,omitempty"`
	Settled        bool    `json:"settled,omitempty"`
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

func dateStr(t time.Time) string { return t.Format("2006-01-02") }

func strPtr(s string) *string { return &s }

// metaLine renders the small-caps meta under a task title, e.g.
// "VATTENFALL · 2 DAYS OVER · WEEKLY".
func metaLine(originLabel *string, dueOn *time.Time, recurrence string) string {
	var parts []string
	if originLabel != nil && *originLabel != "" {
		parts = append(parts, strings.ToUpper(*originLabel))
	}
	if dueOn != nil {
		t := today()
		d := int(dueOn.Sub(t).Hours() / 24)
		switch {
		case d == 0:
			parts = append(parts, "TODAY")
		case d == 1:
			parts = append(parts, "TOMORROW")
		case d == -1:
			parts = append(parts, "1 DAY OVER")
		case d < -1:
			parts = append(parts, fmt.Sprintf("%d DAYS OVER", -d))
		default:
			parts = append(parts, strings.ToUpper(dueOn.Format("Jan 2")))
		}
	}
	switch recurrence {
	case "daily":
		parts = append(parts, "DAILY")
	case "every_2_days":
		parts = append(parts, "EVERY 2 DAYS")
	case "weekly":
		parts = append(parts, "WEEKLY")
	}
	return strings.Join(parts, " · ")
}

// beamCaption mirrors the design's copy exactly (docs/design even-play).
func beamCaption(total, pctMe int, myName, partnerName string) string {
	if total == 0 {
		return "Empty pans. A new week, level by definition."
	}
	diff := pctMe - 50
	if diff < 0 {
		diff = -diff
	}
	switch {
	case diff <= 1:
		return "Level. Enjoy it while it lasts."
	case diff <= 4:
		return "Close to even. Not a competition — but noted."
	default:
		leaning := myName
		if pctMe < 50 {
			leaning = partnerName
		}
		return "Leaning " + leaning + " — mostly the admin and the remembering."
	}
}

func euros(cents int64) string {
	return fmt.Sprintf("€%d.%02d", cents/100, cents%100)
}
