// Package google is a minimal Gmail + Calendar client for evend: refresh-token
// OAuth, HouseholdTodo/discovery message listing, metadata fetch, and all-day
// event insertion. Ported from the proven macOS prototype (HouseholdCore).
package google

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

// ErrInvalidGrant means the refresh token is dead — the household must reconnect.
var ErrInvalidGrant = errors.New("google: invalid_grant")

// ErrNotConfigured means GOOGLE_OAUTH_CLIENT_ID/SECRET are absent.
var ErrNotConfigured = errors.New("google: oauth client not configured")

// ErrInsufficientScope means the stored grant predates the full Calendar
// scope (or the user revoked it): the token is alive, Google simply refuses
// the calendar/ACL/list call. It must surface as "reconnect Google", never as
// a silent success.
var ErrInsufficientScope = errors.New("google: calendar scope missing — reconnect Google")

// ErrNotFound is a 404 from a Google API call (missing calendar, missing ACL
// rule, calendar not on the caller's list).
var ErrNotFound = errors.New("google: not found")

// APIError is one non-2xx Google API response, kept structured so callers can
// tell "you need to re-consent" from "that calendar is gone" from "try later".
type APIError struct {
	Op      string
	Status  int
	Reason  string
	Message string
}

func (e *APIError) Error() string {
	s := fmt.Sprintf("%s: http %d", e.Op, e.Status)
	if e.Reason != "" {
		s += " " + e.Reason
	}
	if e.Message != "" {
		s += ": " + e.Message
	}
	return s
}

// Unwrap maps the wire shape onto the two conditions the product reacts to.
func (e *APIError) Unwrap() error {
	switch {
	case e.IsInsufficientScope():
		return ErrInsufficientScope
	case e.Status == http.StatusNotFound:
		return ErrNotFound
	}
	return nil
}

// IsInsufficientScope reports a grant that cannot perform the call. Google
// answers 401 for a dead/blank token and 403 with an insufficient-permission
// reason when the scope string is too narrow; both mean "re-consent".
func (e *APIError) IsInsufficientScope() bool {
	if e.Status == http.StatusUnauthorized {
		return true
	}
	if e.Status != http.StatusForbidden {
		return false
	}
	switch e.Reason {
	case "insufficientPermissions", "insufficientScope", "forbidden", "accessNotConfigured", "":
		return true
	}
	return strings.Contains(strings.ToLower(e.Message), "insufficient")
}

// DiscoveryQuery mirrors GoogleGmailAPIClient.householdDiscoveryQuery, with the
// window tightened to 30d for the mobile poller.
const DiscoveryQuery = "newer_than:30d (bill OR invoice OR due OR renewal OR payment OR subscription OR appointment OR reminder OR rent OR insurance OR tax OR school OR dentist OR doctor OR maintenance OR repair)"

const householdLabel = "HouseholdTodo"

type Client struct {
	ClientID     string
	ClientSecret string
	IOSClientID  string // in-app PKCE flow; no secret
	OAuthBase    string // default https://oauth2.googleapis.com
	APIBase      string // default https://www.googleapis.com
	HTTP         *http.Client

	mu    sync.Mutex
	cache map[string]cachedToken // key: household id
}

type cachedToken struct {
	token   string
	expires time.Time
}

func New(clientID, clientSecret, iosClientID, oauthBase, apiBase string) *Client {
	if oauthBase == "" {
		oauthBase = "https://oauth2.googleapis.com"
	}
	if apiBase == "" {
		apiBase = "https://www.googleapis.com"
	}
	return &Client{
		ClientID:     clientID,
		ClientSecret: clientSecret,
		IOSClientID:  iosClientID,
		OAuthBase:    oauthBase,
		APIBase:      apiBase,
		HTTP:         &http.Client{Timeout: 20 * time.Second},
		cache:        map[string]cachedToken{},
	}
}

func (c *Client) Configured() bool {
	return c != nil && ((c.ClientID != "" && c.ClientSecret != "") || c.IOSClientID != "")
}

// ---- OAuth ----

type tokenResponse struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	ExpiresIn    int    `json:"expires_in"`
	IDToken      string `json:"id_token"`
	Error        string `json:"error"`
	ErrorDesc    string `json:"error_description"`
}

// ExchangeCode swaps an authorization code for tokens; returns the refresh
// token, the Google account email (id_token claims), and which client kind
// performed the exchange. A present codeVerifier selects the iOS PKCE client
// (no secret) so any number of app users can connect concurrently.
func (c *Client) ExchangeCode(ctx context.Context, code, redirectURI, codeVerifier string) (refreshToken, email, clientKind string, err error) {
	form := url.Values{
		"grant_type":   {"authorization_code"},
		"code":         {code},
		"redirect_uri": {redirectURI},
	}
	switch {
	case codeVerifier != "" && c.IOSClientID != "":
		clientKind = "ios"
		form.Set("client_id", c.IOSClientID)
		form.Set("code_verifier", codeVerifier)
	case c.ClientID != "" && c.ClientSecret != "":
		clientKind = "desktop"
		form.Set("client_id", c.ClientID)
		form.Set("client_secret", c.ClientSecret)
		if codeVerifier != "" {
			form.Set("code_verifier", codeVerifier)
		}
	default:
		return "", "", "", ErrNotConfigured
	}
	tr, err := c.tokenCall(ctx, form)
	if err != nil {
		return "", "", "", err
	}
	if tr.RefreshToken == "" {
		return "", "", "", fmt.Errorf("google: no refresh token in exchange (use access_type=offline&prompt=consent)")
	}
	return tr.RefreshToken, emailFromIDToken(tr.IDToken), clientKind, nil
}

// AccessToken returns a live access token for the household, refreshing and
// caching (60s early expiry) under a single lock. clientKind must match the
// client that minted the refresh token ("ios" or "desktop").
func (c *Client) AccessToken(ctx context.Context, householdID, refreshToken, clientKind string) (string, error) {
	if !c.Configured() {
		return "", ErrNotConfigured
	}
	c.mu.Lock()
	if t, ok := c.cache[householdID]; ok && time.Now().Before(t.expires) {
		c.mu.Unlock()
		return t.token, nil
	}
	c.mu.Unlock()

	form := url.Values{
		"grant_type":    {"refresh_token"},
		"refresh_token": {refreshToken},
	}
	if clientKind == "ios" && c.IOSClientID != "" {
		form.Set("client_id", c.IOSClientID)
	} else {
		form.Set("client_id", c.ClientID)
		form.Set("client_secret", c.ClientSecret)
	}
	tr, err := c.tokenCall(ctx, form)
	if err != nil {
		return "", err
	}
	c.mu.Lock()
	c.cache[householdID] = cachedToken{
		token:   tr.AccessToken,
		expires: time.Now().Add(time.Duration(tr.ExpiresIn-60) * time.Second),
	}
	c.mu.Unlock()
	return tr.AccessToken, nil
}

func (c *Client) Forget(householdID string) {
	c.mu.Lock()
	delete(c.cache, householdID)
	c.mu.Unlock()
}

func (c *Client) tokenCall(ctx context.Context, form url.Values) (*tokenResponse, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		c.OAuthBase+"/token", strings.NewReader(form.Encode()))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	resp, err := c.HTTP.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	var tr tokenResponse
	_ = json.Unmarshal(body, &tr)
	if tr.Error == "invalid_grant" {
		return nil, ErrInvalidGrant
	}
	if resp.StatusCode != http.StatusOK || tr.Error != "" {
		return nil, fmt.Errorf("google token endpoint: http %d %s %s", resp.StatusCode, tr.Error, tr.ErrorDesc)
	}
	return &tr, nil
}

// emailFromIDToken decodes the (already TLS-trusted) id_token payload without
// signature verification — we only display the email, never authorize by it.
func emailFromIDToken(idToken string) string {
	parts := strings.Split(idToken, ".")
	if len(parts) != 3 {
		return ""
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return ""
	}
	var claims struct {
		Email string `json:"email"`
	}
	_ = json.Unmarshal(payload, &claims)
	return claims.Email
}

// AuthURL builds the consent URL for the authorize helper script.
func (c *Client) AuthURL(redirectURI, state string) string {
	q := url.Values{
		"client_id":     {c.ClientID},
		"redirect_uri":  {redirectURI},
		"response_type": {"code"},
		// Full calendar scope, not calendar.events: Even creates the shared
		// secondary calendar, grants the partner reader ACL, and adds it to
		// their CalendarList. Existing grants must re-consent (see README).
		"scope":       {"https://www.googleapis.com/auth/gmail.readonly https://www.googleapis.com/auth/calendar openid email profile"},
		"access_type": {"offline"},
		"prompt":      {"consent"},
		"state":       {state},
	}
	return "https://accounts.google.com/o/oauth2/v2/auth?" + q.Encode()
}

// ---- Gmail ----

// Message is the metadata evend needs from one Gmail message.
type Message struct {
	ID      string
	From    string
	Subject string
	Date    time.Time
	Snippet string
}

// ListHouseholdMessages prefers the HouseholdTodo label, falling back to the
// discovery search (same behavior as the mac app).
func (c *Client) ListHouseholdMessages(ctx context.Context, accessToken string, max int) ([]string, error) {
	labelID, err := c.labelID(ctx, accessToken, householdLabel)
	if err != nil {
		return nil, err
	}
	q := url.Values{"maxResults": {fmt.Sprint(max)}}
	if labelID != "" {
		q.Set("labelIds", labelID)
	} else {
		q.Set("q", DiscoveryQuery)
	}
	var out struct {
		Messages []struct {
			ID string `json:"id"`
		} `json:"messages"`
	}
	if err := c.getJSON(ctx, accessToken, "/gmail/v1/users/me/messages?"+q.Encode(), &out); err != nil {
		return nil, err
	}
	ids := make([]string, 0, len(out.Messages))
	for _, m := range out.Messages {
		ids = append(ids, m.ID)
	}
	return ids, nil
}

func (c *Client) labelID(ctx context.Context, accessToken, name string) (string, error) {
	var out struct {
		Labels []struct {
			ID   string `json:"id"`
			Name string `json:"name"`
		} `json:"labels"`
	}
	if err := c.getJSON(ctx, accessToken, "/gmail/v1/users/me/labels", &out); err != nil {
		return "", err
	}
	for _, l := range out.Labels {
		if l.Name == name {
			return l.ID, nil
		}
	}
	return "", nil
}

func (c *Client) MessageMeta(ctx context.Context, accessToken, id string) (*Message, error) {
	var out struct {
		ID      string `json:"id"`
		Snippet string `json:"snippet"`
		Payload struct {
			Headers []struct {
				Name  string `json:"name"`
				Value string `json:"value"`
			} `json:"headers"`
		} `json:"payload"`
		InternalDate string `json:"internalDate"`
	}
	path := "/gmail/v1/users/me/messages/" + url.PathEscape(id) +
		"?format=metadata&metadataHeaders=From&metadataHeaders=Subject&metadataHeaders=Date"
	if err := c.getJSON(ctx, accessToken, path, &out); err != nil {
		return nil, err
	}
	m := &Message{ID: out.ID, Snippet: cleanHeader(out.Snippet)}
	for _, h := range out.Payload.Headers {
		switch strings.ToLower(h.Name) {
		case "from":
			m.From = cleanHeader(h.Value)
		case "subject":
			m.Subject = cleanHeader(h.Value)
		}
	}
	var ms int64
	_, _ = fmt.Sscan(out.InternalDate, &ms)
	if ms > 0 {
		m.Date = time.UnixMilli(ms)
	}
	return m, nil
}

// cleanHeader decodes RFC 2047 encoded words when present and strips any
// invalid UTF-8 bytes — Gmail metadata occasionally carries legacy-charset
// headers (e.g. ISO-8859-9) that Postgres rejects on insert.
func cleanHeader(v string) string {
	s := strings.TrimSpace(v)
	if strings.Contains(s, "=?") {
		dec := mime.WordDecoder{
			CharsetReader: func(_ string, input io.Reader) (io.Reader, error) {
				// Unknown charsets: pass bytes through; ToValidUTF8 cleans up.
				return input, nil
			},
		}
		if d, err := dec.DecodeHeader(s); err == nil {
			s = d
		}
	}
	return strings.ToValidUTF8(s, "")
}

// SenderDisplay extracts a clean display name from a From header:
// `"Vattenfall Klantenservice" <no-reply@vattenfall.nl>` → "Vattenfall Klantenservice".
func SenderDisplay(from string) string {
	s := strings.TrimSpace(from)
	if i := strings.Index(s, "<"); i > 0 {
		s = strings.TrimSpace(s[:i])
	}
	s = strings.Trim(s, `"' `)
	if s == "" || strings.Contains(s, "@") {
		// bare address — use the domain's first label: no-reply@vattenfall.nl → vattenfall
		at := strings.Index(from, "@")
		if at >= 0 {
			rest := strings.Trim(from[at+1:], "> ")
			if dot := strings.Index(rest, "."); dot > 0 {
				return strings.ToUpper(rest[:dot])
			}
			return strings.ToUpper(rest)
		}
		return "UNKNOWN SENDER"
	}
	return strings.ToUpper(s)
}

// ---- Calendar ----

// EventPayload mirrors GoogleCalendarPayloadFactory, all-day variant.
type EventPayload struct {
	Summary            string                   `json:"summary"`
	Description        string                   `json:"description"`
	Start              EventDate                `json:"start"`
	End                EventDate                `json:"end"`
	Reminders          EventReminder            `json:"reminders"`
	Recurrence         []string                 `json:"recurrence,omitempty"`
	ExtendedProperties *EventExtendedProperties `json:"extendedProperties,omitempty"`
}

type EventExtendedProperties struct {
	Private map[string]string `json:"private,omitempty"`
}

type EventDate struct {
	Date     string `json:"date"`     // YYYY-MM-DD, all-day
	DateTime string `json:"dateTime"` // RFC3339 for a direct timed event
}

type EventReminder struct {
	UseDefault bool               `json:"useDefault"`
	Overrides  []ReminderOverride `json:"overrides"`
}

type ReminderOverride struct {
	Method  string `json:"method"`
	Minutes int    `json:"minutes"`
}

// CalendarEvent is the intentionally small subset of a Google event needed
// to make the shared Calendar authoritative for dated household todos.
type CalendarEvent struct {
	ID                 string    `json:"id"`
	RecurringEventID   string    `json:"recurringEventId"`
	HTMLLink           string    `json:"htmlLink"`
	Summary            string    `json:"summary"`
	Status             string    `json:"status"`
	Start              EventDate `json:"start"`
	ExtendedProperties struct {
		Private map[string]string `json:"private"`
	} `json:"extendedProperties"`
}

// DueOn accepts the all-day events Even writes and date-time events created
// directly in the shared Calendar. The latter keeps its calendar-day value.
func (e CalendarEvent) DueOn() (string, bool) {
	if len(e.Start.Date) == len("2006-01-02") {
		return e.Start.Date, true
	}
	if t, err := time.Parse(time.RFC3339, e.Start.DateTime); err == nil {
		if amsterdam, err := time.LoadLocation("Europe/Amsterdam"); err == nil {
			return t.In(amsterdam).Format("2006-01-02"), true
		}
		return t.Format("2006-01-02"), true
	}
	return "", false
}

// ReminderMinutes maps a draft reminder to popup minutes before the all-day
// event's midnight start, aiming for 09:00 on the earlier day (on_day fires
// at midnight — 09:00 same-day would be after the start).
func ReminderMinutes(reminder string) int {
	switch reminder {
	case "1_day":
		return 1*1440 - 540 // 09:00 the day before
	case "3_days":
		return 3*1440 - 540
	case "1_week":
		return 7*1440 - 540
	default: // on_day
		return 0
	}
}

// RecurrenceRule renders Even's repeat values as a Google Calendar RRULE. A
// bounded series carries its bound so Calendar stops when Even does: COUNT when
// the household picked a number of times, UNTIL when they picked a date.
func RecurrenceRule(recurrence string, until *time.Time, count *int) []string {
	var rule string
	switch recurrence {
	case "daily":
		rule = "RRULE:FREQ=DAILY"
	case "every_2_days":
		rule = "RRULE:FREQ=DAILY;INTERVAL=2"
	case "weekly":
		rule = "RRULE:FREQ=WEEKLY"
	default:
		return nil
	}
	switch {
	case count != nil && *count >= 1:
		rule += fmt.Sprintf(";COUNT=%d", *count)
	case until != nil:
		rule += ";UNTIL=" + until.Format("20060102")
	}
	return []string{rule}
}

// BuildEvent renders the payload for a shared household todo. recurrence is
// optional for compatibility with one-off callers; repeat values become a
// Google Calendar RRULE rather than a chain of copied events.
func BuildEvent(title, fromLabel string, amountCents *int64, dueOn time.Time, reminder string, recurrence ...string) EventPayload {
	desc := "Managed in Even — shared household todo."
	if fromLabel != "" {
		desc += "\nFrom: " + fromLabel
	}
	if amountCents != nil {
		desc += fmt.Sprintf("\nAmount: €%d.%02d", *amountCents/100, *amountCents%100)
	}
	payload := EventPayload{
		Summary:     title,
		Description: desc,
		Start:       EventDate{Date: dueOn.Format("2006-01-02")},
		End:         EventDate{Date: dueOn.AddDate(0, 0, 1).Format("2006-01-02")},
		Reminders: EventReminder{
			UseDefault: false,
			Overrides:  []ReminderOverride{{Method: "popup", Minutes: ReminderMinutes(reminder)}},
		},
	}
	if len(recurrence) > 0 {
		payload.Recurrence = RecurrenceRule(recurrence[0], nil, nil)
	}
	return payload
}

// CreateCalendar makes a secondary Google calendar (the shared household
// calendar) and returns its id.
func (c *Client) CreateCalendar(ctx context.Context, accessToken, summary string) (string, error) {
	var out struct {
		ID string `json:"id"`
	}
	in := map[string]string{"summary": summary, "timeZone": "Europe/Amsterdam"}
	if err := c.call(ctx, http.MethodPost, accessToken, "/calendar/v3/calendars",
		"calendar create", in, &out); err != nil {
		return "", err
	}
	if out.ID == "" {
		return "", fmt.Errorf("calendar create: empty id")
	}
	return out.ID, nil
}

// InsertEvent creates the event; returns (eventID, htmlLink).
func (c *Client) InsertEvent(ctx context.Context, accessToken, calendarID string, payload EventPayload) (string, string, error) {
	path := "/calendar/v3/calendars/" + url.PathEscape(calendarID) + "/events?sendUpdates=none"
	var out struct {
		ID       string `json:"id"`
		HTMLLink string `json:"htmlLink"`
	}
	if err := c.call(ctx, http.MethodPost, accessToken, path, "calendar insert", payload, &out); err != nil {
		return "", "", err
	}
	return out.ID, out.HTMLLink, nil
}

// UpdateEvent replaces the mutable parts of an Even-managed event after a
// household member edits its todo. Google preserves the event id and link.
func (c *Client) UpdateEvent(ctx context.Context, accessToken, calendarID, eventID string, payload EventPayload) (string, string, error) {
	path := "/calendar/v3/calendars/" + url.PathEscape(calendarID) + "/events/" +
		url.PathEscape(eventID) + "?sendUpdates=none"
	var out struct {
		ID       string `json:"id"`
		HTMLLink string `json:"htmlLink"`
	}
	if err := c.call(ctx, http.MethodPut, accessToken, path, "calendar update", payload, &out); err != nil {
		return "", "", err
	}
	return out.ID, out.HTMLLink, nil
}

// DeleteEvent removes an archived todo from the shared Calendar. Deletion is
// best-effort at the API layer; local archival must never be blocked by a
// temporary Google outage.
func (c *Client) DeleteEvent(ctx context.Context, accessToken, calendarID, eventID string) error {
	path := "/calendar/v3/calendars/" + url.PathEscape(calendarID) + "/events/" +
		url.PathEscape(eventID) + "?sendUpdates=none"
	return c.call(ctx, http.MethodDelete, accessToken, path, "calendar event delete", nil, nil)
}

// ListEvents reads a bounded window from the dedicated shared Calendar.
// showDeleted is required so direct event deletions become a visible todo
// state rather than an invisible divergence.
func (c *Client) ListEvents(ctx context.Context, accessToken, calendarID string, from, to time.Time) ([]CalendarEvent, error) {
	q := url.Values{
		"singleEvents": {"true"},
		"showDeleted":  {"true"},
		"orderBy":      {"startTime"},
		"maxResults":   {"2500"},
		"timeMin":      {from.UTC().Format(time.RFC3339)},
		"timeMax":      {to.UTC().Format(time.RFC3339)},
	}
	var events []CalendarEvent
	for {
		path := "/calendar/v3/calendars/" + url.PathEscape(calendarID) + "/events?" + q.Encode()
		var page struct {
			Items         []CalendarEvent `json:"items"`
			NextPageToken string          `json:"nextPageToken"`
		}
		if err := c.getJSON(ctx, accessToken, path, &page); err != nil {
			return nil, err
		}
		events = append(events, page.Items...)
		if page.NextPageToken == "" {
			break
		}
		q.Set("pageToken", page.NextPageToken)
	}
	return events, nil
}

func (c *Client) getJSON(ctx context.Context, accessToken, path string, v any) error {
	return c.call(ctx, http.MethodGet, accessToken, path, "google api "+path, nil, v)
}

// call is the one place a Google REST call is made: it attaches the bearer
// token, decodes an optional body, and turns every non-2xx into an *APIError
// so callers can ask "is this a re-consent?" instead of matching strings.
func (c *Client) call(ctx context.Context, method, accessToken, path, op string, in, out any) error {
	var body io.Reader
	if in != nil {
		raw, err := json.Marshal(in)
		if err != nil {
			return err
		}
		body = bytes.NewReader(raw)
	}
	req, err := http.NewRequestWithContext(ctx, method, c.APIBase+path, body)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+accessToken)
	if in != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := c.HTTP.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return parseAPIError(op, resp.StatusCode, raw)
	}
	if out == nil || len(bytes.TrimSpace(raw)) == 0 {
		return nil
	}
	return json.Unmarshal(raw, out)
}

func parseAPIError(op string, status int, raw []byte) error {
	e := &APIError{Op: op, Status: status}
	var wire struct {
		Error struct {
			Message string `json:"message"`
			Status  string `json:"status"`
			Errors  []struct {
				Reason  string `json:"reason"`
				Message string `json:"message"`
			} `json:"errors"`
		} `json:"error"`
	}
	if json.Unmarshal(raw, &wire) == nil {
		e.Message = wire.Error.Message
		if len(wire.Error.Errors) > 0 {
			e.Reason = wire.Error.Errors[0].Reason
			if e.Message == "" {
				e.Message = wire.Error.Errors[0].Message
			}
		}
		if e.Reason == "" {
			e.Reason = wire.Error.Status
		}
	}
	return e
}

// ---- Calendar sharing (ACL + CalendarList) ----

// ACLRole values Even uses. The partner is a reader on purpose: the mirror is
// read-only in Google, editing belongs in Even. Owner is only ever used to
// hand the calendar over when its owning account disconnects.
const (
	ACLRoleReader = "reader"
	ACLRoleWriter = "writer"
	ACLRoleOwner  = "owner"
)

// ACLRuleID is the deterministic rule id Google assigns a user-scoped grant,
// so a grant can be patched or deleted without listing the ACL first.
func ACLRuleID(email string) string {
	return "user:" + email
}

// InsertACL grants one Google account a role on the shared calendar. Runs
// with the *owner's* token. sendNotifications is off: the partner confirms
// inside Even, an emailed invite would be a second, confusing path.
func (c *Client) InsertACL(ctx context.Context, accessToken, calendarID, email, role string) error {
	path := "/calendar/v3/calendars/" + url.PathEscape(calendarID) + "/acl?sendNotifications=false"
	in := map[string]any{
		"role":  role,
		"scope": map[string]string{"type": "user", "value": email},
	}
	return c.call(ctx, http.MethodPost, accessToken, path, "calendar acl insert", in, nil)
}

// PatchACL changes an existing grant's role (reader → owner during a
// handover). Google may refuse an owner-role change for an OAuth client; the
// caller falls back to recreating the calendar.
func (c *Client) PatchACL(ctx context.Context, accessToken, calendarID, email, role string) error {
	path := "/calendar/v3/calendars/" + url.PathEscape(calendarID) +
		"/acl/" + url.PathEscape(ACLRuleID(email)) + "?sendNotifications=false"
	return c.call(ctx, http.MethodPatch, accessToken, path,
		"calendar acl patch", map[string]any{"role": role}, nil)
}

// DeleteACL revokes a grant. Best-effort everywhere it is used.
func (c *Client) DeleteACL(ctx context.Context, accessToken, calendarID, email string) error {
	path := "/calendar/v3/calendars/" + url.PathEscape(calendarID) +
		"/acl/" + url.PathEscape(ACLRuleID(email))
	return c.call(ctx, http.MethodDelete, accessToken, path, "calendar acl delete", nil, nil)
}

// InsertCalendarList puts an already-shared calendar on this account's list,
// which is what makes it appear in the Google Calendar UI without hunting for
// a sharing email. Runs with the *partner's* token.
func (c *Client) InsertCalendarList(ctx context.Context, accessToken, calendarID string) error {
	return c.call(ctx, http.MethodPost, accessToken, "/calendar/v3/users/me/calendarList",
		"calendarList insert", map[string]any{"id": calendarID}, nil)
}

// CalendarListed reports whether the calendar is already on this account's
// CalendarList. ErrNotFound is the normal "not yet added" answer.
func (c *Client) CalendarListed(ctx context.Context, accessToken, calendarID string) (bool, error) {
	path := "/calendar/v3/users/me/calendarList/" + url.PathEscape(calendarID)
	err := c.call(ctx, http.MethodGet, accessToken, path, "calendarList get", nil, nil)
	if errors.Is(err, ErrNotFound) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	return true, nil
}

// DeleteCalendar removes a secondary calendar entirely. Only used to tidy up
// an abandoned calendar after a recreate-and-migrate handover, with the
// disconnecting owner's dying token — never allowed to fail a disconnect.
func (c *Client) DeleteCalendar(ctx context.Context, accessToken, calendarID string) error {
	path := "/calendar/v3/calendars/" + url.PathEscape(calendarID)
	return c.call(ctx, http.MethodDelete, accessToken, path, "calendar delete", nil, nil)
}
