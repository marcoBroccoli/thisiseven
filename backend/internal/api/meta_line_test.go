package api

import (
	"strings"
	"testing"
	"time"
)

func monthTip(day time.Time) string {
	return strings.ToUpper(day.In(Amsterdam).Format("Jan 2"))
}

func TestMetaLineOneOffUsesCivilDayDiff(t *testing.T) {
	tomorrow := today().AddDate(0, 0, 1)
	origin := "Vattenfall"

	if got := metaLine(metaLineInput{Recurrence: "none", DueOn: &tomorrow}); got != "TOMORROW" {
		t.Fatalf("metaLine = %q, want TOMORROW", got)
	}
	withOrigin := metaLine(metaLineInput{OriginLabel: &origin, Recurrence: "none", DueOn: &tomorrow})
	if withOrigin != "VATTENFALL · TOMORROW" {
		t.Fatalf("metaLine = %q, want VATTENFALL · TOMORROW", withOrigin)
	}

	// Hour math would call an Amsterdam midnight "tomorrow" TODAY in summer.
	dueAmsterdam := time.Date(2026, 8, 8, 0, 0, 0, 0, Amsterdam)
	todayUTC := time.Date(2026, 8, 7, 0, 0, 0, 0, time.UTC)
	if got := int(dueAmsterdam.Sub(todayUTC).Hours() / 24); got != 0 {
		t.Fatalf("precondition: Hours/24 = %d, want 0 (DST trap)", got)
	}
	if d := civilDaysBetween(todayUTC, dueAmsterdam); d != 1 {
		t.Fatalf("civilDaysBetween = %d, want 1", d)
	}
}

func TestMetaLineWeeklyDescribesNextOccurrenceNotAnchor(t *testing.T) {
	// A weekly chore anchored three weeks back is still perfectly on schedule.
	// Describing the anchor would read "21 DAYS OVER · WEEKLY".
	anchor := today().AddDate(0, 0, -21)
	if got := metaLine(metaLineInput{
		Recurrence: "weekly", DueOn: &anchor, CreatedAt: anchor,
	}); got != "TODAY · WEEKLY" {
		t.Fatalf("metaLine = %q, want TODAY · WEEKLY", got)
	}

	// Anchored yesterday: the next hit is six days out, so a month tip.
	yesterday := today().AddDate(0, 0, -1)
	want := monthTip(today().AddDate(0, 0, 6)) + " · WEEKLY"
	if got := metaLine(metaLineInput{
		Recurrence: "weekly", DueOn: &yesterday, CreatedAt: yesterday,
	}); got != want {
		t.Fatalf("metaLine = %q, want %q", got, want)
	}
}

func TestMetaLineKeepsDueAndRecurrenceTogether(t *testing.T) {
	// Regression: a newly created weekly todo used to render as bare "WEEKLY".
	tomorrow := today().AddDate(0, 0, 1)
	if got := metaLine(metaLineInput{
		Recurrence: "weekly", DueOn: &tomorrow, CreatedAt: today(),
	}); got != "TOMORROW · WEEKLY" {
		t.Fatalf("metaLine = %q, want TOMORROW · WEEKLY", got)
	}
}

func TestMetaLinePerOccurrenceRepeatsOmitTheDate(t *testing.T) {
	// Daily and every-two-day rows are only listed on a day they are due, so
	// the date would always read TODAY.
	anchor := today().AddDate(0, 0, -4)
	for recurrence, want := range map[string]string{
		"daily":        "DAILY",
		"every_2_days": "EVERY 2 DAYS",
	} {
		got := metaLine(metaLineInput{Recurrence: recurrence, DueOn: &anchor, CreatedAt: anchor})
		if got != want {
			t.Fatalf("metaLine(%s) = %q, want %q", recurrence, got, want)
		}
	}
}

func TestMetaLineAppendsTheRecurrenceEnd(t *testing.T) {
	anchor := today()
	until := today().AddDate(0, 0, 35)
	count := 6

	byDate := metaLine(metaLineInput{
		Recurrence: "weekly", DueOn: &anchor, CreatedAt: anchor, RecurrenceUntil: &until,
	})
	if want := "TODAY · WEEKLY · UNTIL " + monthTip(until); byDate != want {
		t.Fatalf("metaLine = %q, want %q", byDate, want)
	}

	// A count echoes how the household expressed the bound, not its end date.
	byCount := metaLine(metaLineInput{
		Recurrence: "weekly", DueOn: &anchor, CreatedAt: anchor,
		RecurrenceUntil: &until, RecurrenceCount: &count,
	})
	if byCount != "TODAY · WEEKLY · 6 TIMES" {
		t.Fatalf("metaLine = %q, want TODAY · WEEKLY · 6 TIMES", byCount)
	}

	// A one-off never carries an end phrase.
	if got := metaLine(metaLineInput{Recurrence: "none", DueOn: &anchor, RecurrenceUntil: &until}); got != "TODAY" {
		t.Fatalf("metaLine = %q, want TODAY", got)
	}
}

func TestMetaLineDropsTheDueTipOnceTheSeriesIsOver(t *testing.T) {
	// The series finished last week: there is no next occurrence to describe.
	anchor := today().AddDate(0, 0, -21)
	until := today().AddDate(0, 0, -7)
	if got := metaLine(metaLineInput{
		Recurrence: "weekly", DueOn: &anchor, CreatedAt: anchor, RecurrenceUntil: &until,
	}); got != "WEEKLY · UNTIL "+monthTip(until) {
		t.Fatalf("metaLine = %q, want no due tip", got)
	}
}

func TestDateStrFormatsInAmsterdam(t *testing.T) {
	// UTC evening that is already the next civil day in Amsterdam (CEST).
	utc := time.Date(2026, 8, 7, 22, 30, 0, 0, time.UTC)
	if got := dateStr(utc); got != "2026-08-08" {
		t.Fatalf("dateStr = %q, want 2026-08-08", got)
	}
}

func TestCivilDaysBetweenIgnoresDSTHourGap(t *testing.T) {
	// Spring-forward night 2026-03-29 in Amsterdam — 23h wall clock.
	from := time.Date(2026, 3, 28, 0, 0, 0, 0, Amsterdam)
	to := time.Date(2026, 3, 29, 0, 0, 0, 0, Amsterdam)
	if got := civilDaysBetween(from, to); got != 1 {
		t.Fatalf("civilDaysBetween across DST = %d, want 1", got)
	}
}
