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
		"scope":         {"https://www.googleapis.com/auth/gmail.readonly https://www.googleapis.com/auth/calendar.events openid email profile"},
		"access_type":   {"offline"},
		"prompt":        {"consent"},
		"state":         {state},
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
	Summary     string        `json:"summary"`
	Description string        `json:"description"`
	Start       EventDate     `json:"start"`
	End         EventDate     `json:"end"`
	Reminders   EventReminder `json:"reminders"`
}

type EventDate struct {
	Date string `json:"date"` // YYYY-MM-DD, all-day
}

type EventReminder struct {
	UseDefault bool              `json:"useDefault"`
	Overrides  []ReminderOverride `json:"overrides"`
}

type ReminderOverride struct {
	Method  string `json:"method"`
	Minutes int    `json:"minutes"`
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

// BuildEvent renders the payload for an approved draft's task.
func BuildEvent(title, fromLabel string, amountCents *int64, dueOn time.Time, reminder string) EventPayload {
	desc := "Approved in Even — the household scale."
	if fromLabel != "" {
		desc += "\nFrom: " + fromLabel
	}
	if amountCents != nil {
		desc += fmt.Sprintf("\nAmount: €%d.%02d", *amountCents/100, *amountCents%100)
	}
	return EventPayload{
		Summary:     title,
		Description: desc,
		Start:       EventDate{Date: dueOn.Format("2006-01-02")},
		End:         EventDate{Date: dueOn.AddDate(0, 0, 1).Format("2006-01-02")},
		Reminders: EventReminder{
			UseDefault: false,
			Overrides:  []ReminderOverride{{Method: "popup", Minutes: ReminderMinutes(reminder)}},
		},
	}
}

// InsertEvent creates the event; returns (eventID, htmlLink).
func (c *Client) InsertEvent(ctx context.Context, accessToken, calendarID string, payload EventPayload) (string, string, error) {
	body, err := json.Marshal(payload)
	if err != nil {
		return "", "", err
	}
	path := "/calendar/v3/calendars/" + url.PathEscape(calendarID) + "/events?sendUpdates=none"
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.APIBase+path, bytes.NewReader(body))
	if err != nil {
		return "", "", err
	}
	req.Header.Set("Authorization", "Bearer "+accessToken)
	req.Header.Set("Content-Type", "application/json")
	resp, err := c.HTTP.Do(req)
	if err != nil {
		return "", "", err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return "", "", fmt.Errorf("calendar insert: http %d", resp.StatusCode)
	}
	var out struct {
		ID       string `json:"id"`
		HTMLLink string `json:"htmlLink"`
	}
	if err := json.Unmarshal(raw, &out); err != nil {
		return "", "", err
	}
	return out.ID, out.HTMLLink, nil
}

func (c *Client) getJSON(ctx context.Context, accessToken, path string, v any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.APIBase+path, nil)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+accessToken)
	resp, err := c.HTTP.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("google api %s: http %d", path, resp.StatusCode)
	}
	return json.Unmarshal(body, v)
}
