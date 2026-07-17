# Even — onboarding prompts (functional only)

Context line to prepend once per session:
"iPhone screens (402×874) for Even, a household app for exactly two partners.
Onboarding flow. Design style is up to you, consistent with the existing Even
Play design in this project."

1. **Splash** — app launch screen. Brand mark and app name only. Show the
   entrance animation states.
2. **Welcome / sign-in** — first screen. App name, one-line tagline, Sign in
   with Apple button, one line of privacy reassurance.
3. **How it works (3-page pager)** — swipeable intro with skip. Page 1: how
   completed tasks affect the shared balance. Page 2: how emails become
   drafts that need a partner's approval before becoming tasks/calendar
   events. Page 3: the weekly reset ritual.
4. **Path choice** — after sign-in: either create a new household or join an
   existing one with a code. Sign-out escape hatch.
5. **Create household** — form: household name + user's display name. Submit
   creates the household.
6. **Invite code reveal** — shows the generated 6-character code after
   creating, with a share action and a hint on what the partner does next.
7. **Join household** — form: 6-character invite code + user's display name.
   Error state for a wrong/full code.
8. **Connect Google** — optional step after household setup: explains that
   Gmail is scanned read-only for bills/appointments which become approval
   drafts, and approved ones create calendar events. Connect button (opens
   Google's sign-in) and a skip option.
9. **Waiting for partner** — the main Today screen in solo state: invite code
   still accessible, balance shows 100/0, partner slot empty.
10. **Notifications ask** — pre-permission screen: one weekly reminder + an
    approval ping, no other notifications. Accept and not-now actions.
