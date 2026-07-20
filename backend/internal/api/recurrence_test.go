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
			if got := recursOnDate(tc.recurrence, &anchor, anchor, recurrenceDate(tc.day)); got != tc.want {
				t.Fatalf("recursOnDate(%s, %d) = %t, want %t", tc.recurrence, tc.day, got, tc.want)
			}
		})
	}
}

func TestCalendarOccurrencesCreatesStableIntervals(t *testing.T) {
	anchor := recurrenceDate(20)
	from := recurrenceDate(21)
	to := recurrenceDate(28)

	daily := calendarOccurrences("daily", &anchor, anchor, from, to)
	if len(daily) != 8 || dateStr(daily[0]) != "2026-07-21" || dateStr(daily[7]) != "2026-07-28" {
		t.Fatalf("daily occurrences = %+v", daily)
	}

	everyTwoDays := calendarOccurrences("every_2_days", &anchor, anchor, from, to)
	if got := []string{dateStr(everyTwoDays[0]), dateStr(everyTwoDays[1]), dateStr(everyTwoDays[2]), dateStr(everyTwoDays[3])}; got[0] != "2026-07-22" || got[1] != "2026-07-24" || got[2] != "2026-07-26" || got[3] != "2026-07-28" {
		t.Fatalf("every two days = %v", got)
	}

	weekly := calendarOccurrences("weekly", &anchor, anchor, from, to)
	if len(weekly) != 1 || dateStr(weekly[0]) != "2026-07-27" {
		t.Fatalf("weekly occurrences = %+v", weekly)
	}
}
