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
	ID          string `json:"id"`
	Actionable  bool   `json:"actionable"`
	Title       string `json:"title"`
	Summary     string `json:"summary"`
	AmountCents *int64 `json:"amount_cents"`
	DueOn       *string `json:"due_on"`
	Urgency     int    `json:"urgency"`
}

const systemPrompt = `You classify emails for "Even", a two-person household app. An email is ACTIONABLE only when it needs the couple to do something concrete for the household: a bill or invoice to pay, an appointment to confirm or attend, a renewal or contract decision, a delivery needing action, an official/government/admin letter, a repair or maintenance task. NOT actionable: newsletters, marketing and promotions, receipts or confirmations of already-completed payments, shipping notifications needing nothing, social or personal correspondence, product updates, security notices needing nothing.

For each actionable email, rewrite it in Even's product voice — warm, plain, imperative household language, no corporate phrasing, no shouting:
- "title": a short imperative task a partner reads at a glance, e.g. "Pay the Vattenfall energy bill" or "Confirm the dentist appointment". Never the raw subject line.
- "summary": one short line of the key facts, e.g. "July invoice, €112.40, due Jul 25" or "Cleaning on Tuesday at 16:30". Never the raw snippet.
- "amount_cents": the amount in euro cents if a specific amount is to be paid, else null.
- "due_on": the due/appointment date as YYYY-MM-DD if one is stated or clearly implied, else null. Resolve relative dates against the provided today's date.
- "urgency": 3 = overdue, final notice, or due within 3 days; 2 = due within ~2 weeks or needs a reply; 1 = informational deadline further out.

For non-actionable emails set actionable=false, title and summary to "", amount_cents and due_on to null, urgency to 1. Return one verdict per input email, same "id", same order.`

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
				},
				"required":             []string{"id", "actionable", "title", "summary", "amount_cents", "due_on", "urgency"},
				"additionalProperties": false,
			},
		},
	},
	"required":             []string{"verdicts"},
	"additionalProperties": false,
}

// Classify runs one batch of emails through the model. today is YYYY-MM-DD in
// the household's timezone.
func (c *Client) Classify(ctx context.Context, emails []EmailInput, today string) ([]Verdict, error) {
	if !c.Configured() {
		return nil, fmt.Errorf("claude: not configured")
	}
	userPayload, _ := json.Marshal(map[string]any{"today": today, "emails": emails})
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
