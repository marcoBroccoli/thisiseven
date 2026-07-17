package google

import (
	"regexp"
	"strconv"
	"strings"
	"time"
)

// Extraction is the heuristic read of one household email, ported from
// HouseholdHeuristicEmailExtractor.swift. Below the confidence gate the
// actionable fields (amount, due) are blanked; the title suggestion stays.
type Extraction struct {
	Title       string
	AmountCents *int64
	DueOn       *time.Time
	Urgency     int // 1..3
	Confidence  float64
}

const confidenceGate = 0.60

var (
	amountRe = regexp.MustCompile(`(?i)(?:€|\$|eur|usd|amount:?|total:?)\s*([0-9]+(?:[.,][0-9]{1,2})?)|([0-9]+[.,][0-9]{2})`)
	inDaysRe = regexp.MustCompile(`(?:due|by|before|in)\s+(?:in\s+)?([0-9]{1,2})\s+days?`)

	monthPat   = `jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?`
	dayMonthRe = regexp.MustCompile(`(?i)(?:due|by|before|on)\s+(?:on\s+)?([0-9]{1,2})(?:st|nd|rd|th)?\s+(` + monthPat + `)(?:\s*,?\s*([0-9]{4}))?`)
	monthDayRe = regexp.MustCompile(`(?i)(?:due|by|before|on)\s+(?:on\s+)?(` + monthPat + `)\s+([0-9]{1,2})(?:st|nd|rd|th)?(?:\s*,?\s*([0-9]{4}))?`)
	numericRe  = regexp.MustCompile(`(?:due|by|before|on)\s+(?:on\s+)?([0-9]{1,2})[/-]([0-9]{1,2})(?:[/-]([0-9]{2,4}))?`)

	urgentWords = []string{"urgent", "overdue", "final notice", "past due", "last reminder", "action required"}
	billWords   = []string{"bill", "invoice", "renew"}
	replyWords  = []string{"reply", "confirm", "respond"}

	weekdays = []string{"sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"}
	months   = []string{"january", "february", "march", "april", "may", "june",
		"july", "august", "september", "october", "november", "december"}
)

// Extract runs the heuristics over subject + snippet + sender.
func Extract(subject, snippet, from string, now time.Time) Extraction {
	text := subject + " " + snippet + " " + from
	lower := strings.ToLower(text)
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, time.UTC)

	amount := amountCents(text)
	due := dueDate(lower, today)
	conf := confidence(amount, due, lower)

	e := Extraction{
		Title:       strings.TrimSpace(subject),
		Urgency:     urgency(lower, due, today),
		Confidence:  conf,
		AmountCents: amount,
		DueOn:       due,
	}
	if conf < confidenceGate {
		e.AmountCents = nil
		e.DueOn = nil
	}
	return e
}

func amountCents(text string) *int64 {
	m := amountRe.FindStringSubmatch(text)
	if m == nil {
		return nil
	}
	for _, g := range m[1:] {
		if g == "" {
			continue
		}
		f, err := strconv.ParseFloat(strings.ReplaceAll(g, ",", "."), 64)
		if err != nil {
			continue
		}
		cents := int64(f*100 + 0.5)
		if cents > 0 {
			return &cents
		}
	}
	return nil
}

func dueDate(lower string, today time.Time) *time.Time {
	day := func(t time.Time) *time.Time { return &t }

	if strings.Contains(lower, "due tomorrow") || strings.Contains(lower, "by tomorrow") {
		return day(today.AddDate(0, 0, 1))
	}
	if strings.Contains(lower, "due today") || strings.Contains(lower, "by today") {
		return day(today)
	}
	if m := inDaysRe.FindStringSubmatch(lower); m != nil {
		if n, err := strconv.Atoi(m[1]); err == nil {
			return day(today.AddDate(0, 0, n))
		}
	}
	if strings.Contains(lower, "end of month") || strings.Contains(lower, "month end") {
		firstNext := time.Date(today.Year(), today.Month(), 1, 0, 0, 0, 0, time.UTC).AddDate(0, 1, 0)
		return day(firstNext.AddDate(0, 0, -1))
	}
	if t := absoluteDate(lower, today); t != nil {
		return t
	}
	for i, wd := range weekdays {
		next := []string{"due next " + wd, "by next " + wd, "before next " + wd, "on next " + wd}
		if containsAny(lower, next) {
			return day(nextWeekday(today, time.Weekday(i), true))
		}
		this := []string{"due " + wd, "by " + wd, "before " + wd, "on " + wd}
		if containsAny(lower, this) {
			return day(nextWeekday(today, time.Weekday(i), false))
		}
	}
	return nil
}

func nextWeekday(today time.Time, wd time.Weekday, followingWeek bool) time.Time {
	d := (int(wd) - int(today.Weekday()) + 7) % 7
	if d == 0 {
		d = 7
	}
	t := today.AddDate(0, 0, d)
	if followingWeek {
		t = t.AddDate(0, 0, 7)
	}
	return t
}

func absoluteDate(lower string, today time.Time) *time.Time {
	build := func(dayS, monthName, yearS string, monthNum int) *time.Time {
		d, err := strconv.Atoi(dayS)
		if err != nil || d < 1 || d > 31 {
			return nil
		}
		month := monthNum
		if month == 0 {
			for i, m := range months {
				if strings.HasPrefix(m, strings.ToLower(monthName)[:3]) &&
					(strings.ToLower(monthName) == m || len(monthName) <= 4 || strings.ToLower(monthName) == m) {
					month = i + 1
					break
				}
			}
			// tolerate short forms
			if month == 0 {
				for i, m := range months {
					if strings.HasPrefix(m, strings.ToLower(monthName)) {
						month = i + 1
						break
					}
				}
			}
		}
		if month < 1 || month > 12 {
			return nil
		}
		year := today.Year()
		hadYear := false
		if yearS != "" {
			if y, err := strconv.Atoi(yearS); err == nil {
				hadYear = true
				if y < 100 {
					y += 2000
				}
				year = y
			}
		}
		t := time.Date(year, time.Month(month), d, 0, 0, 0, 0, time.UTC)
		if !hadYear && t.Before(today) {
			t = t.AddDate(1, 0, 0)
		}
		return &t
	}

	if m := dayMonthRe.FindStringSubmatch(lower); m != nil {
		if t := build(m[1], m[2], m[3], 0); t != nil {
			return t
		}
	}
	if m := monthDayRe.FindStringSubmatch(lower); m != nil {
		if t := build(m[2], m[1], m[3], 0); t != nil {
			return t
		}
	}
	if m := numericRe.FindStringSubmatch(lower); m != nil {
		if mo, err := strconv.Atoi(m[2]); err == nil {
			if t := build(m[1], "", m[3], mo); t != nil {
				return t
			}
		}
	}
	return nil
}

// urgency maps the mac's four levels onto the draft's 1..3:
// immediate→3, soon/normal→2, low→1.
func urgency(lower string, due *time.Time, today time.Time) int {
	if containsAny(lower, urgentWords) {
		return 3
	}
	if due == nil {
		if containsAny(lower, replyWords) {
			return 2
		}
		return 1
	}
	days := int(due.Sub(today).Hours() / 24)
	switch {
	case days <= 1:
		return 3
	case days <= 7:
		return 2
	default:
		return 1
	}
}

// confidence ports the mac scoring minus the area term (mobile has no areas):
// base 0.42, +0.14 amount, +0.18 due date, +0.08 bill/invoice/renew keyword.
func confidence(amount *int64, due *time.Time, lower string) float64 {
	score := 0.42
	if amount != nil {
		score += 0.14
	}
	if due != nil {
		score += 0.18
	}
	if containsAny(lower, billWords) {
		score += 0.08
	}
	if score > 0.92 {
		score = 0.92
	}
	return score
}

func containsAny(s string, subs []string) bool {
	for _, sub := range subs {
		if strings.Contains(s, sub) {
			return true
		}
	}
	return false
}
