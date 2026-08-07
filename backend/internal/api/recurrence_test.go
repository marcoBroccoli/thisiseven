package api

import (
	"testing"
	"time"
)

func recurrenceDate(day int) time.Time {
	return time.Date(2026, 7, day, 12, 0, 0, 0, Amsterdam)
}

func TestRecursOnDateUsesAnchorAndInterval(t *testing.T) {
	anchor := recurrenceDate(20)
	cases := []struct {
		name       string
		recurrence string
		day        int
		want       bool
	}{
		{"daily starts at anchor", "daily", 20, true},
		{"daily repeats next day", "daily", 21, true},
		{"daily does not run early", "daily", 19, false},
		{"two day starts at anchor", "every_2_days", 20, true},
		{"two day skips intervening day", "every_2_days", 21, false},
		{"two day repeats on interval", "every_2_days", 22, true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := recursOnDate(tc.recurrence, &anchor, nil, anchor, recurrenceDate(tc.day)); got != tc.want {
				t.Fatalf("recursOnDate(%s, %d) = %t, want %t", tc.recurrence, tc.day, got, tc.want)
			}
		})
	}
}

func TestRecursOnDateStopsAtTheRecurrenceEnd(t *testing.T) {
	anchor := recurrenceDate(20)
	until := recurrenceDate(22)
	if !recursOnDate("daily", &anchor, &until, anchor, recurrenceDate(22)) {
		t.Fatal("the last scheduled day must still be togglable")
	}
	if recursOnDate("daily", &anchor, &until, anchor, recurrenceDate(23)) {
		t.Fatal("a finished series must not be togglable")
	}
}

func TestResolveRecurrenceEndTurnsACountIntoADate(t *testing.T) {
	anchor := recurrenceDate(20)
	count := 6
	until := recurrenceDate(31)

	// Six weekly occurrences span five intervals from the anchor.
	if end := resolveRecurrenceEnd("weekly", anchor, nil, &count); end == nil || dateStr(*end) != "2026-08-24" {
		t.Fatalf("weekly x6 end = %v, want 2026-08-24", end)
	}
	if end := resolveRecurrenceEnd("every_2_days", anchor, nil, &count); end == nil || dateStr(*end) != "2026-07-30" {
		t.Fatalf("every two days x6 end = %v, want 2026-07-30", end)
	}
	// One occurrence ends on the anchor itself.
	one := 1
	if end := resolveRecurrenceEnd("daily", anchor, nil, &one); end == nil || dateStr(*end) != "2026-07-20" {
		t.Fatalf("daily x1 end = %v, want 2026-07-20", end)
	}
	// A count wins over a date so the two spellings cannot disagree.
	if end := resolveRecurrenceEnd("daily", anchor, &until, &count); end == nil || dateStr(*end) != "2026-07-25" {
		t.Fatalf("count should derive the end, got %v", end)
	}
	// Unbounded and non-repeating both store nothing.
	if end := resolveRecurrenceEnd("weekly", anchor, nil, nil); end != nil {
		t.Fatalf("unbounded weekly end = %v, want nil", end)
	}
	if end := resolveRecurrenceEnd("none", anchor, &until, &count); end != nil {
		t.Fatalf("one-off end = %v, want nil", end)
	}
}

func TestNextOccurrenceStepsForwardAndRunsOut(t *testing.T) {
	anchor := recurrenceDate(20)
	until := recurrenceDate(27)

	if day, ok := nextOccurrence("weekly", anchor, nil, recurrenceDate(20)); !ok || dateStr(day) != "2026-07-20" {
		t.Fatalf("next from anchor = %v (%t), want the anchor", day, ok)
	}
	if day, ok := nextOccurrence("weekly", anchor, nil, recurrenceDate(21)); !ok || dateStr(day) != "2026-07-27" {
		t.Fatalf("next after anchor = %v (%t), want 2026-07-27", day, ok)
	}
	if day, ok := nextOccurrence("weekly", anchor, &until, recurrenceDate(27)); !ok || dateStr(day) != "2026-07-27" {
		t.Fatalf("the last occurrence must be reachable, got %v (%t)", day, ok)
	}
	if _, ok := nextOccurrence("weekly", anchor, &until, recurrenceDate(28)); ok {
		t.Fatal("a finished series has no next occurrence")
	}
	if _, ok := nextOccurrence("none", anchor, nil, anchor); ok {
		t.Fatal("a one-off has no recurrence to step")
	}
}

func TestCalendarOccurrencesCreatesStableIntervals(t *testing.T) {
	anchor := recurrenceDate(20)
	from := recurrenceDate(21)
	to := recurrenceDate(28)

	daily := calendarOccurrences("daily", &anchor, nil, anchor, from, to)
	if len(daily) != 8 || dateStr(daily[0]) != "2026-07-21" || dateStr(daily[7]) != "2026-07-28" {
		t.Fatalf("daily occurrences = %+v", daily)
	}

	everyTwoDays := calendarOccurrences("every_2_days", &anchor, nil, anchor, from, to)
	if got := []string{dateStr(everyTwoDays[0]), dateStr(everyTwoDays[1]), dateStr(everyTwoDays[2]), dateStr(everyTwoDays[3])}; got[0] != "2026-07-22" || got[1] != "2026-07-24" || got[2] != "2026-07-26" || got[3] != "2026-07-28" {
		t.Fatalf("every two days = %v", got)
	}

	weekly := calendarOccurrences("weekly", &anchor, nil, anchor, from, to)
	if len(weekly) != 1 || dateStr(weekly[0]) != "2026-07-27" {
		t.Fatalf("weekly occurrences = %+v", weekly)
	}
}

func TestCalendarOccurrencesStopAtTheRecurrenceEnd(t *testing.T) {
	anchor := recurrenceDate(20)
	until := recurrenceDate(24)

	bounded := calendarOccurrences("daily", &anchor, &until, anchor, recurrenceDate(21), recurrenceDate(28))
	if len(bounded) != 4 || dateStr(bounded[3]) != "2026-07-24" {
		t.Fatalf("bounded daily occurrences = %+v", bounded)
	}
	// A window that opens after the series closed expands to nothing.
	if got := calendarOccurrences("daily", &anchor, &until, anchor, recurrenceDate(25), recurrenceDate(28)); got != nil {
		t.Fatalf("finished series expanded to %+v", got)
	}
}
