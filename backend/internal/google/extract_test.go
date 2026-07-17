package google

import (
	"testing"
	"time"
)

var now = time.Date(2026, 7, 17, 12, 0, 0, 0, time.UTC)

func TestExtractBillWithAmountAndDue(t *testing.T) {
	e := Extract("Your July energy bill is ready",
		"Amount: €112.40. Please pay by 25 July 2026.", "Vattenfall <no-reply@vattenfall.nl>", now)
	if e.AmountCents == nil || *e.AmountCents != 11240 {
		t.Fatalf("amount = %v, want 11240", e.AmountCents)
	}
	if e.DueOn == nil || e.DueOn.Format("2006-01-02") != "2026-07-25" {
		t.Fatalf("due = %v, want 2026-07-25", e.DueOn)
	}
	if e.Confidence < confidenceGate {
		t.Fatalf("confidence = %v, want >= gate", e.Confidence)
	}
	if e.Urgency != 1 {
		t.Fatalf("urgency = %d, want 1 (due in 8 days > 7-day window)", e.Urgency)
	}
}

func TestExtractCommaDecimalEuro(t *testing.T) {
	e := Extract("Factuur", "Totaal EUR 39,99 due in 3 days", "Vodafone", now)
	if e.AmountCents == nil || *e.AmountCents != 3999 {
		t.Fatalf("amount = %v, want 3999", e.AmountCents)
	}
	if e.DueOn == nil || e.DueOn.Format("2006-01-02") != "2026-07-20" {
		t.Fatalf("due = %v, want 2026-07-20", e.DueOn)
	}
}

func TestExtractUrgentOverdue(t *testing.T) {
	e := Extract("FINAL NOTICE: payment overdue", "Your invoice is past due.", "Incasso", now)
	if e.Urgency != 3 {
		t.Fatalf("urgency = %d, want 3", e.Urgency)
	}
}

func TestExtractLowConfidenceBlanksActionables(t *testing.T) {
	// No bill keyword, no amount — only a due phrase: 0.42+0.18 = 0.60 is at
	// the gate; drop the due phrase too for a clearly-low case.
	e := Extract("Hoi!", "Zullen we zaterdag koffie doen?", "Anne", now)
	if e.AmountCents != nil || e.DueOn != nil {
		t.Fatalf("low-confidence extraction should blank amount/due, got %v %v", e.AmountCents, e.DueOn)
	}
	if e.Urgency != 1 {
		t.Fatalf("urgency = %d, want 1", e.Urgency)
	}
}

func TestExtractDueTomorrowIsImmediate(t *testing.T) {
	e := Extract("Dentist appointment", "Please confirm, due tomorrow. Invoice attached.", "Tandarts Jordaan", now)
	if e.DueOn == nil || e.DueOn.Format("2006-01-02") != "2026-07-18" {
		t.Fatalf("due = %v, want tomorrow", e.DueOn)
	}
	if e.Urgency != 3 {
		t.Fatalf("urgency = %d, want 3", e.Urgency)
	}
}

func TestExtractEndOfMonth(t *testing.T) {
	e := Extract("Subscription renewal bill", "Renew by end of month to keep your plan. €15.99", "Netflix", now)
	if e.DueOn == nil || e.DueOn.Format("2006-01-02") != "2026-07-31" {
		t.Fatalf("due = %v, want 2026-07-31", e.DueOn)
	}
}

func TestExtractNumericDateRollsForward(t *testing.T) {
	// due 05/01 with no year: Jan 5 already passed in 2026 → next year.
	e := Extract("Tax bill", "Betaal due 05/01 online. Amount: 250.00", "Belastingdienst", now)
	if e.DueOn == nil || e.DueOn.Format("2006-01-02") != "2027-01-05" {
		t.Fatalf("due = %v, want 2027-01-05", e.DueOn)
	}
}

func TestSenderDisplay(t *testing.T) {
	cases := map[string]string{
		`"Vattenfall Klantenservice" <no-reply@vattenfall.nl>`: "VATTENFALL KLANTENSERVICE",
		`Gemeente Amsterdam <noreply@amsterdam.nl>`:            "GEMEENTE AMSTERDAM",
		`no-reply@vattenfall.nl`:                               "VATTENFALL",
	}
	for in, want := range cases {
		if got := SenderDisplay(in); got != want {
			t.Errorf("SenderDisplay(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestReminderMinutes(t *testing.T) {
	cases := map[string]int{"on_day": 0, "1_day": 900, "3_days": 3780, "1_week": 9540}
	for in, want := range cases {
		if got := ReminderMinutes(in); got != want {
			t.Errorf("ReminderMinutes(%q) = %d, want %d", in, got, want)
		}
	}
}

func TestBuildEventPayload(t *testing.T) {
	amount := int64(11240)
	due := time.Date(2026, 7, 25, 0, 0, 0, 0, time.UTC)
	p := BuildEvent("Pay Vattenfall energy bill — July", "VATTENFALL", &amount, due, "3_days")
	if p.Start.Date != "2026-07-25" || p.End.Date != "2026-07-26" {
		t.Fatalf("all-day range wrong: %+v", p)
	}
	if p.Reminders.UseDefault || len(p.Reminders.Overrides) != 1 || p.Reminders.Overrides[0].Minutes != 3780 {
		t.Fatalf("reminders wrong: %+v", p.Reminders)
	}
	if p.Summary != "Pay Vattenfall energy bill — July" {
		t.Fatalf("summary wrong: %q", p.Summary)
	}
}
