# Google Desktop OAuth Test Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Connect the macOS app to the user's Google desktop OAuth client and import Gmail messages labeled `HouseholdTodo`.

**Architecture:** Keep OAuth, PKCE, token exchange, and Gmail API request construction in `HouseholdCore` so they can be tested without launching the UI. Add a macOS-only connection coordinator in the app target that opens the browser, receives the local loopback callback, exchanges the authorization code, stores tokens in Keychain, and swaps Gmail import from demo data to live Gmail when connected.

**Tech Stack:** Swift Package Manager, SwiftUI, AppKit `NSWorkspace`, Network `NWListener`, Security Keychain APIs, URLSession, XCTest.

---

### Task 1: OAuth Core Requests

**Files:**
- Modify: `Sources/HouseholdCore/GoogleOAuth.swift`
- Test: `Tests/HouseholdCoreTests/GoogleIntegrationTests.swift`

- [ ] Add PKCE code challenge generation using SHA-256 and base64url encoding.
- [ ] Add OAuth token exchange and refresh request builders that never require a client secret.
- [ ] Test deterministic PKCE challenge output and token request bodies.

### Task 2: Gmail API Client

**Files:**
- Modify: `Sources/HouseholdCore/GoogleAPIModels.swift`
- Create: `Sources/HouseholdCore/GoogleGmailAPIClient.swift`
- Test: `Tests/HouseholdCoreTests/GoogleIntegrationTests.swift`

- [ ] Add testable HTTP transport and access token provider protocols.
- [ ] Add Gmail label lookup, labeled message listing, metadata fetch, and `SourceEmail` mapping.
- [ ] Test that `HouseholdTodo` is resolved to a label ID and only those messages are fetched.

### Task 3: macOS OAuth Coordinator

**Files:**
- Create: `Sources/HouseholdCommandCenter/GoogleDesktopOAuthCoordinator.swift`
- Create: `Sources/HouseholdCommandCenter/GoogleKeychainTokenStore.swift`
- Modify: `Sources/HouseholdCommandCenter/DemoHouseholdStore.swift`

- [ ] Add local loopback listener for `/oauth/callback`.
- [ ] Open Google authorization URL with a generated PKCE verifier/challenge.
- [ ] Exchange the returned authorization code for tokens.
- [ ] Persist tokens in Keychain and expose connection status.

### Task 4: Settings UI And Import Switch

**Files:**
- Modify: `Sources/HouseholdCommandCenter/HouseholdRootView.swift`
- Modify: `README.md`
- Modify: `docs/google-supabase-test-setup.md`

- [ ] Add Settings fields for client ID and expected test account.
- [ ] Add Connect, Disconnect, and Test Gmail Import actions.
- [ ] Use live Gmail import when connected and demo import otherwise.
- [ ] Document the exact run and connect steps.

### Verification

- [ ] Run `swift test`.
- [ ] Run `swift build`.
- [ ] Run `./scripts/run-mac-app.sh --build-only`.
