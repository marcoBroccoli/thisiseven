package api

import (
	"strconv"
	"time"
)

func itoa(n int) string { return strconv.Itoa(n) }

// rfc3339 renders a timestamp scanned as `any` (pgx hands back time.Time) into
// the one string format the SPA parses. A NULL becomes "" rather than the zero
// year, so the UI can test for emptiness instead of for 0001-01-01.
func rfc3339(v any) string {
	switch t := v.(type) {
	case time.Time:
		if t.IsZero() {
			return ""
		}
		return t.UTC().Format(time.RFC3339)
	case *time.Time:
		if t == nil || t.IsZero() {
			return ""
		}
		return t.UTC().Format(time.RFC3339)
	default:
		return ""
	}
}

// tsPtr is the nullable form used in DTOs: a JSON null instead of "".
func tsPtr(t *time.Time) *string {
	if t == nil || t.IsZero() {
		return nil
	}
	s := t.UTC().Format(time.RFC3339)
	return &s
}

// dateOnly renders a `date` column (pgx gives time.Time at midnight UTC).
func dateOnly(t *time.Time) *string {
	if t == nil || t.IsZero() {
		return nil
	}
	s := t.Format("2006-01-02")
	return &s
}
