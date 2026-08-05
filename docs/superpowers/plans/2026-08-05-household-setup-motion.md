# Household Setup Motion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Soft-fade HouseholdSetup path steps, error banner, and working button state using existing `EvenMotion`.

**Architecture:** View-only changes in `HouseholdSetupView`. Mirror Login/Onboarding: `.animation` on path/error/working + `EvenMotion.fadeUp` transitions. Reducer unchanged.

**Tech Stack:** SwiftUI, TCA `@ViewAction`, Design `EvenMotion`.

## Global Constraints

- Reuse `EvenMotion` only — no new animation tokens.
- No app-root or Login entrance choreography.
- Keep E2E accessibility identifiers unchanged.

---

## Task 1: Animate HouseholdSetupView

**Files:**
- Modify: `Sources/Feature/HouseholdSetupFeature/HouseholdSetupView.swift`

- [x] Wrap `content` switch in a container with `.id(store.path)`, `.transition(EvenMotion.fadeUp)`, `.animation(EvenMotion.page, value: store.path)`
- [x] Add `.transition(EvenMotion.fadeUp)` on error text; `.animation(EvenMotion.reveal, value: store.error)`
- [x] Dim primary buttons when `store.working` (opacity) with reveal animation on working
- [x] Send path taps with `animation: EvenMotion.page` (`createTapped`, `joinTapped`)
- [x] Preview / build sanity check
