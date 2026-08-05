# Splash / Login / Onboarding module split

## Decision

Three SPM Feature targets; `AppReducer` owns routing and bootstrap.

| Module | Owns | State |
|---|---|---|
| `SplashFeature` | Boot chrome only | view-only |
| `LoginFeature` | Apple / debug email | struct (`working`, `error`) |
| `OnboardingFeature` | How-it-works pager | **enum** `.weigh` / `.drafts` / `.sunday` |

## App enum path

`.booting` → `.login` → `.onboarding` → `.householdSetup` → `.connections` → `.ready`

- Bootstrap `.signedOut` → login  
- Bootstrap `.needsHousehold` → household setup (skip how-it-works)  
- Login `.needsHousehold` → onboarding `.weigh`  
- Login `.alreadyReady` → ready  
- Onboarding `.finished` / skip → household setup  

## Enum-state pattern (Onboarding)

```swift
@ObservableState
public enum State: Equatable, Sendable {
  case weigh, drafts, sunday
}
```

Next / back / skip mutate or delegate; copy + art keyed off the case.
