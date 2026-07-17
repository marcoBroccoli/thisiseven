# Even — onboarding page prompts for Claude Design

Paste the **style preamble** first, then any page prompt below it. Each page
prompt is self-contained. Target: iPhone frame 402×874.

---

## Style preamble (prepend to every prompt)

> Design a single iPhone screen (402×874) for **Even**, a two-person household
> app ("the house, weighed honestly"). Visual language — warm paper, not
> fintech: background #F6F1E6 (deep paper #E9E1D2), raised card #FBF7EE,
> espresso ink #26201A, muted stone #8A7D69 for secondary text, hairlines
> rgba(38,32,26,.14). Two member accent colors: clay #A6552F and teal #37756D.
> Type: Newsreader serif for display and body (italic for warmth/asides),
> Source Sans 3 for tracked ALL-CAPS micro-labels. Subtle paper-grain texture
> (~5% multiply). Motion language: things gently land and settle, never just
> fade. Buttons: full-width, 10px radius, ink-filled with paper text; ghost
> buttons are hairline-outlined. The brand mark is a hand-drawn balance scale
> glyph (tilted beam line, pointer triangle, short base line). Voice: warm,
> ritual-based, a little literary — "the pans", "the weekly reset", "say one
> kind thing" — never corporate.

---

## 1 · Splash

The app's first breath. Empty paper, centered scale glyph that draws itself
in as a single stroke (show the mid-draw state), then the italic serif
wordmark "Even" landing 8px up beneath it. Nothing else — no spinner, no
progress. Design both the mid-animation frame and the settled frame.

## 2 · Welcome / sign-in

The first real screen. Centered: scale glyph floating gently, giant italic
serif "Even", tagline "The house, weighed honestly." in italic stone. Bottom
third: a black Sign in with Apple button (system style, 50pt), and beneath it
a one-line italic reassurance: "Two people, one household. Your data stays on
your own server." Feels like the cover page of a beautiful notebook.

## 3 · How it works — pager (3 pages)

Three swipeable explainer pages, dot indicators, SKIP top-right in caps micro-label.
- **3a — The scale.** Illustration: the balance beam with clay pebbles in one
  pan, teal in the other, slightly tilted. Headline "Finished work becomes
  weight." Body: "Check something off and a pebble drops into your pan.
  Heavier jobs, heavier pebbles. The beam does the arithmetic."
- **3b — The approval inbox.** Illustration: a draft card with an ink-stamp
  "ON THE CALENDAR ✓" hitting it at a slight angle. Headline "Bills arrive as
  drafts, not tasks." Body: "Even reads the household mail. Nothing becomes
  shared work — or touches the calendar — until one of you approves it."
- **3c — The Sunday reset.** Illustration: two pans pouring pebbles out,
  scattered dots below. Headline "Ten minutes on Sunday." Body: "Look at the
  week honestly, say one kind thing each, trade what isn't working — then
  pour the pans and start level."

## 4 · Path choice

After sign-in. Caps kicker "ALMOST THERE", big serif "Set up your household."
Two stacked choices: primary ink button "Start our household", ghost button
"I have an invite code". Small italic footnote: "One household, exactly two
of you." Quiet SIGN OUT micro-label at the bottom.

## 5 · Start the household

A form that feels like inking a ledger's first page. Caps kicker "NEW
HOUSEHOLD". Two underline-only fields (serif input text, italic stone
placeholders): "Household name — e.g. Prinsengracht 12" and "Your name — what
your partner calls you". Note under the name field in caps micro: "YOU'LL BE
CLAY · YOUR PARTNER GETS TEAL" with the two color dots. Primary button:
"Create — get the invite code".

## 6 · Invite code reveal

The celebration moment after creating. Centered oversized 6-character code
(e.g. "WBL5EM") in serif with wide letter-spacing, sitting on a dashed-border
card like a ticket stub. Above: "Bring your partner in." Below: share button
(ink, full width) "Send the code", and italic: "They tap 'I have an invite
code' — that's it. The scale stays 100/0 until they arrive." Mini level-scale
illustration with one clay dot and one empty teal spot.

## 7 · Join the household

Mirror of 5 for the second partner. Caps kicker "JOINING". Underline field
"Invite code — 6 characters" (monospaced-feel wide tracking), then "Your name".
Primary button "Join the household". Italic footnote: "You'll be teal. The
pans are waiting."

## 8 · Connect Google

Post-household step, skippable. Caps kicker "ONE MORE THING — OPTIONAL".
Serif headline "Let Even read the mail pile." Body: "Even scans your Gmail
for bills, renewals and appointments and turns them into drafts in the
approval inbox. Approve one and it lands on your calendar with a reminder.
Nothing is ever sent, deleted, or added without your yes." A small
illustration: envelope → draft card → tiny calendar, connected by a dotted
ink line. Primary button "Connect Google", ghost "Later — it lives in the
Inbox too". Micro-caps trust line: "READ-ONLY MAIL ACCESS · EVENTS ONLY ON
APPROVAL".

## 9 · Waiting for your partner (solo Today)

The Today screen in solo state: dashed invite banner up top ("WAITING FOR
YOUR PARTNER · Invite code: WBL5EM" + share icon), the beam tilted fully to
the signed-in member's side reading 100 / 0, second pan empty with a ghosted
name slot, caption italic: "All yours so far — send the code." Task list
below with one or two rows to show life.

## 10 · Notifications ask (later)

Pre-permission screen before the system prompt. Serif headline "A nudge on
Sunday, silence otherwise." Body: "One reminder for the weekly reset, and a
quiet ping when a draft needs your approval. No streaks, no guilt." Primary
"Sound good", ghost "Not now". Illustration: the scale glyph with a single
small notification dot balanced on one pan.
