# AGENTS.md

Project guide for AI coding agents (Claude Code, Cursor, etc.).

**The full guide — project structure, what each part does, data model, build/test
commands, and conventions — lives in [`CLAUDE.md`](./CLAUDE.md).** Read it first.

Quick orientation:
- `backend/` — the `evend` Go API (all app data; auto-runs SQL migrations on start).
- SPM package **`EvenKit`** (one package): targets under `Sources/Core/`,
  `Sources/Feature/`, `Sources/Design/`, `Sources/Shared/` — folder layers,
  not separate packages.
- Open **`Even.xcworkspace`** (only `ios/Even.xcodeproj`). Platforms: iOS 18+ /
  watchOS 11+ — no macOS app. Build with `xcodebuild` / Xcode.
- `docs/even-design-system/` — MVP UI contract; Features map to those flows.
- Non-app resources live under `docs/` (see `docs/README.md`).
- `docs/ARCHITECTURE.md` + `docs/superpowers/specs/2026-08-05-evenkit-tca-design-system-adaptation.md`.
- `docs/product/API.md` — the **API contract, source of truth**. Keep it and
  `backend/internal/api/router.go` in sync.
- Secrets are referenced by NAME only (`~/.env` on the home server); never commit them.

**SwiftUI chrome (read `CLAUDE.md` → “SwiftUI chrome & paper”):**
- `.evenPaperBackground()` on content **inside** `NavigationStack`, not behind it.
- Clear toolbar background; use principal/inline + app serif for compact titles —
  no hand-rolled `← BACK` headers (Onboarding / HouseholdSetup pattern).
- Primary disabled = solid muted fill, never `.opacity` / system disabled fade
  over paper grain (`EvenPrimaryButton`).
- `.buttonStyle(.plain)` cards need `.contentShape` on the full shape or only
  text receives taps.
- Feature root = only `*Reducer` / `*View`; Watch stubs in `Watch/`, everything
  else in subfolders (`Preview/`, `Components/`, `Views/`, nested surfaces…).
- Peel into `Views/` only when the shell shows more than one state/step;
  single-screen Features stay inline on the main `*View` (atoms →
  `Components/`). Shell owns shared chrome — including the footer via
  `safeAreaInset` (Connections pattern).
- Flow CTAs: one shell footer, state-driven primary + optional secondary;
  morph the same control in place — never swap button view types per path.
  Pad the inset itself; keep path `.animation` on the body only (before inset).
- Never `.frame(..., alignment:)` a bare multi-child `@ViewBuilder` — stack
  first or children overlay at one origin.
- Portable kits (`ToastUI`, `SheetUI`, `VisualEffects`) stay brand-free; Even
  skin in Design. Toasts: `.evenToastHost()`. Loading: `.loading(Bool)` from
  VisualEffects — not hand-chained redacted + shimmer.
- Pack repeated nav chrome: `.evenPaperNavigationChrome()`,
  `.evenScrollOnPaper()`, `EvenBrandMark` — see `CLAUDE.md`.
- Factor Feature UI into narrow-input `View` structs (`*Components`), not giant
  computed `some View` properties on the shell.
- Skeletons: Feature-local placeholders, not `PreviewData`. Don’t flash
  `isLoading` on re-appear when content is already loaded. Empty pull-to-refresh
  re-enters skeleton; animate skeleton → content. Views only
  `await send(.refresh).finish()` — refresh/cancel policy lives in the reducer
  (see `CLAUDE.md` → Pull-to-refresh + TCA).
- Previews: `PreviewDelay` + client `previewValue`; Feature `PreviewSupport`
  only overrides what the canvas needs — see `CLAUDE.md` → Preview clients.
- Every Feature surface gets an in-file `#Preview` (main view, or shell + each
  `Views/` step when multi-step); fixtures from `*PreviewSupport` only —
  see `CLAUDE.md` → Hygiene.
- Flex variable-width rows (e.g. invite tiles) to the proposed width — don’t let
  fixed sizes blow the layout and clip leading content.
- `.scrollContentBackground(.hidden)` / `.evenScrollOnPaper()` on ScrollViews
  over paper.
- Short pagers: gate heavy art to the active page; reserve illustration height.
- Beam physics lives in `Design/`; Features only map domain → configuration.
- Setup route: household → **connections** (Gmail/Calendar) → ready.
