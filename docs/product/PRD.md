# Even — MVP PRD

**One-liner:** A two-person household app that makes invisible work visible: finished
tasks fall as weighted pebbles onto a balance scale, bills get approved (never
auto-added), money settles weekly, and Sunday ends with a ten-minute reset ritual.

**Users:** exactly one couple per household — Umur + Beste. MVP is iOS only.
**Design source of truth:** `docs/design/even-play.dc.html` (Claude Design export)
and the token table in `docs/design/README.md`. The design's "Ada/Umut" are
placeholder names; real names come from onboarding.

**Hard rule: no mock data.** The app ships empty. Every task, draft, expense,
appreciation and trade is created by a real signed-in user. Demo seeds
(`EvenDemoSeed`) are deleted in this milestone.

---

## Architecture (mirrors the Kilo house pattern, self-hosted auth)

```
iPhone (SwiftUI, EvenMobile target in this repo)
   │  Sign in with Apple → identityToken
   ▼
evend — Go backend (chi + pgx) in Docker on the Mac mini, 127.0.0.1:8091
   ├── /auth/* → reverse-proxies to GoTrue (Supabase Auth, same compose)
   │     Apple id_token grant → access/refresh JWTs (Keychain)
   └── /v1/*  → verifies GoTrue JWTs (HS256), owns all business logic
   ▼
Postgres 17 in Docker (same compose) — auth schema (GoTrue) + app schema
```

- **Why self-hosted Supabase Auth:** creating a cloud project is blocked —
  umuryavuz96 is at the 2-active-free-project limit (Vet App hosts Kilo's
  schema; Toolkit is Toolpile prod). `scripts/provision-supabase.sh` remains
  ready; moving to cloud later is a base-URL + secret swap after a Pro
  upgrade or freed slot. GoTrue speaks the exact same API
  (`/token?grant_type=id_token|password|refresh_token`).
- One origin for the app: Caddy route `even-api.home` → 8091 for LAN/tailnet
  devices; simulator uses `http://localhost:8091`. Public exposure
  (api.thisiseven.app via Cloudflare tunnel) is post-MVP, needs Umur's
  go-ahead.
- The docker Postgres is backend-private, so authorization lives in evend
  (every query is household-scoped), not RLS.
- Dev/testing auth path: email+password accounts via GoTrue
  (`GOTRUE_MAILER_AUTOCONFIRM=true`, debug builds only) so two-account
  pairing can be verified in the simulator, where Sign in with Apple is
  unreliable.

## Domain model

- **household** — name, 6-char invite code. Exactly 2 members max.
- **member** — supabase user id, display name, color role `clay` (terracotta
  #A6552F) or `teal` (pine #37756D). First member gets clay, partner teal.
- **week** — the app's heartbeat. One open week per household (Mon–Sun).
  Closing a week (Reset step 4) archives it and opens the next.
- **task** — title, section `chore`|`admin`, owner member, weight 1–3
  ("heft"), recurrence `none`|`daily`|`every_2_days`|`weekly`, optional due
  date. Created directly (Quick Add) or by approving a draft.
- **completion** — task × open week × member, snapshot of weight. Toggling a
  task off deletes it. Pebbles on the scale = completions of the open week.
- **draft** — the approval inbox item: label (who it's from), subject, summary,
  urgency 1–3, proposed title/owner/amount/due/reminder. Status
  `pending`|`approved`|`dismissed`. MVP source: partners propose them by hand
  ("Gmail discovery" is post-MVP; the UI keeps the review-then-approve
  contract). Approving creates an `admin` task and stamps "ON THE CALENDAR ✓"
  (real calendar write is post-MVP; the reminder offset is stored).
- **expense** — payer, title, amount EUR, date. Always split 50/50 in MVP.
- **settlement** — clears all currently-unsettled expenses; records payer →
  payee and amount. Running balance = (payer sums diff) / 2.
- **appreciation** — per week, per direction (A→B, B→A): optional text +
  "said" flag.
- **trade** — per week: a recurring task handed to the other partner. Accepted
  trades apply (owner swap) when the week closes.

## Screens (per design)

### Onboarding (not in the design file — minimal, same tokens)
1. Paper-textured welcome → Sign in with Apple button.
2. Choose: "Start our household" (name it → shows invite code to share) or
   "Join with a code".
3. Display name entry. Color auto-assigned. Solo state is legal (scale reads
   100/0) until the partner joins.

### Today
- Balance scale: beam rotates `clamp((50-A%)·0.5, ±8°)` with spring ease; two
  hanging pans; pebbles sized 8/11/14px by weight in member colors; big
  tabular percentages; WK label from the open week; caption logic from the
  design ("Empty pans…", "Level…", "Close to even…", "Leaning …").
- Sections **CHORES — TODAY** and **THE ADMIN** with rows: circle check
  (draws ✓, fills owner color), serif title (strikethrough on done), meta
  caps line, heft dots, owner initial chip.
- Quick Add (＋) → sheet: title, section, owner, weight, recurrence, due.
- Footer aphorism: "Heavier work, heavier pebble. The beam does the arithmetic."

### Inbox
- Header: "Approval Inbox", subtitle "Drafts, not tasks. Tap one to review."
- Draft cards (from-label, urgency, subject, owner·amount·due caps line).
- ＋ Propose draft (partner-sourced in MVP).
- Bottom sheet review: editable title, owner pills, reminder chips (on the
  day / 1 day / 3 days / 1 week before), Dismiss / **Approve → Calendar**.
- Ink-stamp toast: "ON THE CALENDAR ✓" / "DISMISSED — IGNORED".
- Empty state: mini scale illustration, "Inbox zero. Rare — enjoy it."
- Tab badge shows pending count.

### Money
- "Money, settled weekly." Running-balance card: € amount, "X owes Y" line,
  coin-between-avatars illustration; **Settle up** → records settlement, coin
  rolls across, button becomes "Settled ✓", stamp "SETTLED — EVEN ON MONEY".
- Expense list (payer chip, title, caps meta, tabular amount) + ＋ Add expense
  sheet (title, amount, payer, date). Settlement rows appear in the list.

### Reset (Sunday ritual, 4 steps + intro)
0. Intro: "The weekly reset" → Start.
1. **The week, honestly** — computed split bars: Chores, The admin (completion
   weight by section), Money fronted (expense sums). "The biggest carry" — a
   computed sentence naming the week's largest contribution.
2. **Say one kind thing** — two cards (each direction), optional typed text,
   tap-when-said. "The app can't do this part for you."
3. **Trade, don't tally** — propose/accept task-owner swaps for next week.
4. **Close the week — pour the pans** → transactional close: apply accepted
   trades, archive completions, reset recurring tasks, open next week. End
   screen: "Week N, poured out."

### Chrome
- Custom tab bar per design (scale / inbox·count / coins / reset icons, small
  caps labels), serif "Even" wordmark + floating scale glyph, dark-mode toggle
  (persisted), paper grain overlay, fadeUp/sheetUp/stamp/pebbleDrop/coinSlide
  animations approximated with SwiftUI springs.

## Visual tokens

Light: bg #F6F1E6, card #FBF7EE, ink #26201A, sub #8A7D69, line rgba(38,32,26,.14).
Dark: bg #17130F, card #211B15, ink #EDE5D6, sub #9A8F7C. Member colors —
clay #A6552F (dark-mode lift oklch(.74 .09 45)), teal #37756D (lift
oklch(.74 .07 195)). Type: Newsreader (display, italic accents) + Source Sans 3
(caps labels/meta), bundled TTFs. Grain: subtle noise overlay ~5% multiply.

## Out of scope (MVP)

Gmail discovery, Google Calendar writes, push notifications, Android, widgets,
uneven expense splits, >2 members, public API exposure, App Store/TestFlight
ship (needs explicit approval).

## Success = definition of done

Two real accounts in the simulator pair into one household and, with zero
seeded data: create + check tasks and watch the beam move; propose, edit,
approve a draft into THE ADMIN; add expenses, settle, see €0.00; run the full
reset, close the week, pans empty, accepted trade swaps the owner. Server
restart loses nothing. Screenshots of all four tabs (light + dark) in
`docs/screenshots/`.
