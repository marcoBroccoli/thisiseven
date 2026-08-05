# Household Setup motion

## Goal

Soft-fade step and chrome changes in `HouseholdSetupFeature` — no hard cuts.

## Scope

View-only in `HouseholdSetupView`. Reuse `EvenMotion` (`page`, `fadeUp`, `reveal`). No new tokens. No Login-style entrance stagger.

## Behavior

1. **Path change** (choice → create/join → inviteReveal/waiting): content replaces with `EvenMotion.fadeUp`, driven by `.animation(EvenMotion.page, value: store.path)`.
2. **Error** show/clear: `EvenMotion.fadeUp` + `.animation(EvenMotion.reveal, value: store.error)`.
3. **Working**: primary button opacity dims while `store.working` (same idea as Login), animated with reveal.

## Out of scope

App-root phase transitions, back navigation, Connections/Login motion.
