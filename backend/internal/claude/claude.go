// Package claude is a minimal Anthropic Messages API client for evend's one
// job: classifying scanned Gmail into actionable household drafts, rewritten
// in Even's product voice. Raw HTTP against /v1/messages with JSON-schema
// forced output (output_config.format) and simple retries.
package claude

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"
)

const (
	defaultBase  = "https://api.anthropic.com"
	defaultModel = "claude-haiku-4-5-20251001"
	version      = "2023-06-01"
)

type Client struct {
	apiKey string
	base   string
	model  string
	http   *http.Client
}

func New(apiKey, base, model string) *Client {
	if base == "" {
		base = defaultBase
	}
	if model == "" {
		model = defaultModel
	}
	return &Client{apiKey: apiKey, base: base, model: model,
		http: &http.Client{Timeout: 60 * time.Second}}
}

// Configured reports whether classification is available; without a key the
// caller falls back to heuristics.
func (c *Client) Configured() bool { return c != nil && c.apiKey != "" }

// EmailInput is the metadata for one scanned Gmail message.
type EmailInput struct {
	ID      string `json:"id"`
	From    string `json:"from"`
	Subject string `json:"subject"`
	Snippet string `json:"snippet"`
	Date    string `json:"date"`
}

// Verdict is the classifier's output for one email. Title and Summary are
// REWRITTEN in Even's voice — never the raw subject/snippet.
type Verdict struct {
	ID          string  `json:"id"`
	Actionable  bool    `json:"actionable"`
	Title       string  `json:"title"`
	Summary     string  `json:"summary"`
	AmountCents *int64  `json:"amount_cents"`
	DueOn       *string `json:"due_on"`
	Urgency     int     `json:"urgency"`
	// DuplicateOf marks a non-actionable dupe: the id of the batch email it
	// repeats, or "existing" when it matches a pending draft already in the
	// inbox.
	DuplicateOf *string `json:"duplicate_of"`
	// Category groups the inbox: bills, appointments, subscriptions, admin, other.
	Category string `json:"category"`
}

const systemPrompt = `You classify emails for "Even", a two-person household app. An email is ACTIONABLE only when the couple genuinely must act on it for the household: a bill or invoice to pay, an appointment to confirm or attend, a renewal or contract decision, a delivery needing action, an official/government/admin letter, a repair or maintenance task. Hold a high bar — when in doubt, it is NOT actionable. NOT actionable: newsletters, marketing and promotions, receipts or confirmations of already-completed payments, shipping notifications needing nothing, social or personal correspondence, product updates, security notices needing nothing, and anything merely informational.

Deduplicate ruthlessly:
- If several emails in this batch are about the SAME underlying action (e.g. repeated payment-failure reminders from one vendor), only the NEWEST is actionable; every older one gets actionable=false and "duplicate_of" set to the id of the email you kept.
- The input includes "existing_pending": tasks already waiting in the couple's inbox. If an email is about the same underlying action as one of those, set actionable=false and "duplicate_of": "existing".
- Otherwise "duplicate_of" is null.

For each actionable email, rewrite it in Even's product voice — warm, plain, imperative household language, no corporate phrasing, no shouting:
- "title": a short imperative task a partner reads at a glance, e.g. "Pay the Vattenfall energy bill" or "Confirm the dentist appointment". NEVER the raw subject line, not even lightly edited — always rewrite from scratch as an instruction.
- "summary": one short line of the key facts, e.g. "July invoice, €112.40, due Jul 25" or "Cleaning on Tuesday at 16:30". Never the raw snippet.
- "amount_cents": the amount in euro cents if a specific amount is to be paid, else null.
- "due_on": the due/appointment date as YYYY-MM-DD if one is stated or clearly implied, else null. Resolve relative dates against the provided today's date.
- "urgency": 3 = overdue, final notice, or due within 3 days; 2 = due within ~2 weeks or needs a reply; 1 = informational deadline further out.
- "category": exactly one of "bills" (money owed, failed or upcoming payments), "appointments" (things to confirm or attend), "subscriptions" (renewals, price changes, plan decisions), "admin" (official letters, paperwork, home upkeep), "other".

For non-actionable emails set actionable=false, title and summary to "", amount_cents and due_on to null, urgency to 1, category to "other". Return one verdict per input email, same "id", same order.`

var outputSchema = map[string]any{
	"type": "object",
	"properties": map[string]any{
		"verdicts": map[string]any{
			"type": "array",
			"items": map[string]any{
				"type": "object",
				"properties": map[string]any{
					"id":           map[string]any{"type": "string"},
					"actionable":   map[string]any{"type": "boolean"},
					"title":        map[string]any{"type": "string"},
					"summary":      map[string]any{"type": "string"},
					"amount_cents": map[string]any{"type": []string{"integer", "null"}},
					"due_on":       map[string]any{"type": []string{"string", "null"}},
					"urgency":      map[string]any{"type": "integer", "enum": []int{1, 2, 3}},
					"duplicate_of": map[string]any{"type": []string{"string", "null"}},
					"category":     map[string]any{"type": "string", "enum": []string{"bills", "appointments", "subscriptions", "admin", "other"}},
				},
				"required":             []string{"id", "actionable", "title", "summary", "amount_cents", "due_on", "urgency", "duplicate_of", "category"},
				"additionalProperties": false,
			},
		},
	},
	"required":             []string{"verdicts"},
	"additionalProperties": false,
}

// Classify runs one batch of emails through the model. existingPending is the
// household's current pending draft titles (dedupe context); today is
// YYYY-MM-DD in the household's timezone. Verdicts whose title echoes the raw
// subject are retried once with feedback before being returned as-is (the
// caller applies a heuristic fix for any survivor).
func (c *Client) Classify(ctx context.Context, emails []EmailInput, existingPending []string, today string) ([]Verdict, error) {
	verdicts, err := c.classifyOnce(ctx, emails, existingPending, today, "")
	if err != nil {
		return nil, err
	}

	// One corrective pass for titles that echo the raw subject.
	subjects := map[string]string{}
	for _, e := range emails {
		subjects[e.ID] = e.Subject
	}
	var offenders []EmailInput
	for _, v := range verdicts {
		if v.Actionable && EchoesSubject(v.Title, subjects[v.ID]) {
			for _, e := range emails {
				if e.ID == v.ID {
					offenders = append(offenders, e)
				}
			}
		}
	}
	if len(offenders) > 0 {
		feedback := "Your previous titles for these emails echoed the raw subject line. Rewrite each title from scratch as a short imperative household instruction that does NOT reuse the subject's wording."
		if fixed, err := c.classifyOnce(ctx, offenders, existingPending, today, feedback); err == nil {
			byID := map[string]Verdict{}
			for _, v := range fixed {
				byID[v.ID] = v
			}
			for i, v := range verdicts {
				if f, ok := byID[v.ID]; ok && v.Actionable {
					verdicts[i].Title = f.Title
					verdicts[i].Summary = f.Summary
				}
			}
		}
	}
	return verdicts, nil
}

// EchoesSubject reports whether a title is essentially the raw subject.
func EchoesSubject(title, subject string) bool {
	norm := func(s string) string {
		var b []rune
		for _, r := range s {
			switch {
			case r >= 'A' && r <= 'Z':
				b = append(b, r+('a'-'A'))
			case (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9'):
				b = append(b, r)
			}
		}
		return string(b)
	}
	t, s := norm(title), norm(subject)
	if t == "" || s == "" {
		return false
	}
	if t == s {
		return true
	}
	// Near-echo: one contains the other and lengths are close.
	shorter, longer := t, s
	if len(shorter) > len(longer) {
		shorter, longer = longer, shorter
	}
	return len(shorter) >= 10 && strings.Contains(longer, shorter) &&
		float64(len(shorter))/float64(len(longer)) > 0.75
}

func (c *Client) classifyOnce(ctx context.Context, emails []EmailInput, existingPending []string, today, feedback string) ([]Verdict, error) {
	if !c.Configured() {
		return nil, fmt.Errorf("claude: not configured")
	}
	payload := map[string]any{"today": today, "existing_pending": existingPending, "emails": emails}
	if feedback != "" {
		payload["feedback"] = feedback
	}
	userPayload, _ := json.Marshal(payload)
	body := map[string]any{
		"model":      c.model,
		"max_tokens": 4096,
		"system":     systemPrompt,
		"messages": []map[string]any{
			{"role": "user", "content": string(userPayload)},
		},
		"output_config": map[string]any{
			"format": map[string]any{"type": "json_schema", "schema": outputSchema},
		},
	}
	raw, _ := json.Marshal(body)

	var lastErr error
	for attempt := 0; attempt < 3; attempt++ {
		if attempt > 0 {
			select {
			case <-ctx.Done():
				return nil, ctx.Err()
			case <-time.After(time.Duration(attempt*2) * time.Second):
			}
		}
		verdicts, retryable, err := c.call(ctx, raw)
		if err == nil {
			return verdicts, nil
		}
		lastErr = err
		if !retryable {
			return nil, err
		}
	}
	return nil, lastErr
}

func (c *Client) call(ctx context.Context, body []byte) (verdicts []Verdict, retryable bool, err error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		c.base+"/v1/messages", bytes.NewReader(body))
	if err != nil {
		return nil, false, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("x-api-key", c.apiKey)
	req.Header.Set("anthropic-version", version)

	resp, err := c.http.Do(req)
	if err != nil {
		return nil, true, err
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusTooManyRequests || resp.StatusCode >= 500 {
		return nil, true, fmt.Errorf("claude: http %d", resp.StatusCode)
	}
	if resp.StatusCode != http.StatusOK {
		var apiErr struct {
			Error struct {
				Message string `json:"message"`
			} `json:"error"`
		}
		_ = json.NewDecoder(resp.Body).Decode(&apiErr)
		return nil, false, fmt.Errorf("claude: http %d: %s", resp.StatusCode, apiErr.Error.Message)
	}

	var out struct {
		Content []struct {
			Type string `json:"type"`
			Text string `json:"text"`
		} `json:"content"`
		StopReason string `json:"stop_reason"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return nil, true, fmt.Errorf("claude: bad response body: %w", err)
	}
	if out.StopReason == "refusal" {
		return nil, false, fmt.Errorf("claude: refused")
	}
	for _, block := range out.Content {
		if block.Type != "text" {
			continue
		}
		var parsed struct {
			Verdicts []Verdict `json:"verdicts"`
		}
		if err := json.Unmarshal([]byte(block.Text), &parsed); err != nil {
			return nil, false, fmt.Errorf("claude: unparseable verdicts: %w", err)
		}
		return parsed.Verdicts, false, nil
	}
	return nil, false, fmt.Errorf("claude: no text content in response")
}
