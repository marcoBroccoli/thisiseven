// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "EvenKit",
    platforms: [
        .iOS(.v18),
        .watchOS(.v11),
    ],
    products: [
        .library(name: "EvenCore", targets: ["EvenCore"]),
        .library(name: "ToastUI", targets: ["ToastUI"]),
        .library(name: "SheetUI", targets: ["SheetUI"]),
        .library(name: "VisualEffects", targets: ["VisualEffects"]),
        .library(name: "IGTabBar", targets: ["IGTabBar"]),
        .library(name: "Design", targets: ["Design"]),
        .library(name: "AuthClient", targets: ["AuthClient"]),
        .library(name: "HouseholdClient", targets: ["HouseholdClient"]),
        .library(name: "HouseholdRealtimeClient", targets: ["HouseholdRealtimeClient"]),
        .library(name: "GoogleClient", targets: ["GoogleClient"]),
        .library(name: "DraftsClient", targets: ["DraftsClient"]),
        .library(name: "TasksClient", targets: ["TasksClient"]),
        .library(name: "SummaryClient", targets: ["SummaryClient"]),
        .library(name: "CalendarClient", targets: ["CalendarClient"]),
        .library(name: "WidgetClient", targets: ["WidgetClient"]),
        .library(name: "NotificationsClient", targets: ["NotificationsClient"]),
        .library(name: "ToastClient", targets: ["ToastClient"]),
        .library(name: "DI", targets: ["DI"]),
        .library(name: "SplashFeature", targets: ["SplashFeature"]),
        .library(name: "LoginFeature", targets: ["LoginFeature"]),
        .library(name: "OnboardingFeature", targets: ["OnboardingFeature"]),
        .library(name: "HouseholdSetupFeature", targets: ["HouseholdSetupFeature"]),
        .library(name: "ConnectionsFeature", targets: ["ConnectionsFeature"]),
        .library(name: "InboxFeature", targets: ["InboxFeature"]),
        .library(name: "TodayFeature", targets: ["TodayFeature"]),
        .library(name: "ProfileFeature", targets: ["ProfileFeature"]),
        .library(name: "EvenApp", targets: ["EvenApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.26.1"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.4.0"),
    ],
    targets: {
        let deps = Target.Dependency.product(name: "Dependencies", package: "swift-dependencies")
        let depsMacros = Target.Dependency.product(name: "DependenciesMacros", package: "swift-dependencies")
        let tca = Target.Dependency.product(name: "ComposableArchitecture", package: "swift-composable-architecture")

        /// Layer folders under `Sources/`: Core / Feature / Design.
        func client(_ name: String) -> Target {
            .target(
                name: name,
                dependencies: ["EvenCore", deps, depsMacros],
                path: "Sources/Core/\(name)"
            )
        }
        func clientLive(_ name: String) -> Target {
            .target(
                name: "\(name)Live",
                dependencies: [Target.Dependency.byName(name: name), "EvenCore", deps],
                path: "Sources/Core/\(name)Live"
            )
        }
        func feature(_ name: String, extra: [Target.Dependency] = []) -> Target {
            .target(
                name: name,
                dependencies: ["EvenCore", "Design", tca] + extra,
                path: "Sources/Feature/\(name)"
            )
        }

        // iOS-only kit — SPM still compiles Feature targets for watchOS, but must
        // not pull UIKit sheet chrome into the Watch graph.
        let sheetUI_iOS: Target.Dependency = .target(
            name: "SheetUI",
            condition: .when(platforms: [.iOS])
        )
        let igTabBar_iOS: Target.Dependency = .target(
            name: "IGTabBar",
            condition: .when(platforms: [.iOS])
        )

        return [
            .target(name: "EvenCore", path: "Sources/Core/EvenCore"),
            // Standalone, app-agnostic UI kit — no EvenCore/Design/token
            // references, owns its own shader bundle. Destined for the shared
            // components package; keep it that way.
            .target(name: "ToastUI", path: "Sources/Shared/ToastUI"),
            // Portable auto-sizing sheet — brand-free; Features pass surface/content.
            .target(name: "SheetUI", path: "Sources/Shared/SheetUI"),
            // Portable visual effects (shimmer, …) — brand-free; no Even tokens.
            .target(name: "VisualEffects", path: "Sources/Shared/VisualEffects"),
            // Instagram-style floating segmented tab bar — brand-free; UIKit/iOS.
            .target(name: "IGTabBar", path: "Sources/Shared/IGTabBar"),
            .target(
                name: "Design",
                dependencies: ["ToastUI", "VisualEffects"],
                path: "Sources/Design",
                resources: [.process("Assets.xcassets")]
            ),
            client("AuthClient"),
            clientLive("AuthClient"),
            client("HouseholdClient"),
            clientLive("HouseholdClient"),
            client("HouseholdRealtimeClient"),
            clientLive("HouseholdRealtimeClient"),
            client("GoogleClient"),
            clientLive("GoogleClient"),
            client("DraftsClient"),
            clientLive("DraftsClient"),
            client("TasksClient"),
            clientLive("TasksClient"),
            client("SummaryClient"),
            clientLive("SummaryClient"),
            client("CalendarClient"),
            clientLive("CalendarClient"),
            client("WidgetClient"),
            clientLive("WidgetClient"),
            client("NotificationsClient"),
            clientLive("NotificationsClient"),
            .target(
                name: "ToastClient",
                dependencies: ["ToastUI", deps, depsMacros],
                path: "Sources/Core/ToastClient"
            ),
            .target(
                name: "ToastClientLive",
                dependencies: ["ToastClient", "ToastUI", deps],
                path: "Sources/Core/ToastClientLive"
            ),
            .target(
                name: "DI",
                dependencies: [
                    "AuthClientLive",
                    "HouseholdClientLive",
                    "HouseholdRealtimeClientLive",
                    "GoogleClientLive",
                    "DraftsClientLive",
                    "TasksClientLive",
                    "SummaryClientLive",
                    "CalendarClientLive",
                    "WidgetClientLive",
                    "NotificationsClientLive",
                    "ToastClientLive",
                ],
                path: "Sources/Core/DI"
            ),
            feature("SplashFeature"),
            feature("LoginFeature", extra: ["AuthClient"]),
            feature("OnboardingFeature"),
            feature("HouseholdSetupFeature", extra: ["HouseholdClient"]),
            feature("ConnectionsFeature", extra: ["GoogleClient", "NotificationsClient", "ToastClient", "ToastUI"]),
            feature(
                "InboxFeature",
                extra: [
                    "DraftsClient", "CalendarClient", "NotificationsClient", "AuthClient",
                    sheetUI_iOS, igTabBar_iOS, "ToastClient", "ToastUI", "VisualEffects",
                ]
            ),
            feature(
                "TodayFeature",
                extra: [
                    "TasksClient", "SummaryClient", "WidgetClient", "AuthClient",
                    sheetUI_iOS, igTabBar_iOS, "ToastClient", "ToastUI", "VisualEffects",
                ]
            ),
            feature(
                "ProfileFeature",
                extra: [
                    "AuthClient", "HouseholdClient", "ConnectionsFeature",
                    "GoogleClient", "NotificationsClient",
                    igTabBar_iOS, "ToastClient", "ToastUI", "VisualEffects",
                ]
            ),
            .target(
                name: "EvenApp",
                dependencies: [
                    "EvenCore", "Design", "AuthClient", "DI",
                    "HouseholdClient", "HouseholdRealtimeClient", "GoogleClient",
                    "NotificationsClient", "ToastClient",
                    "DraftsClient", "TasksClient", "SummaryClient", "CalendarClient",
                    "WidgetClient",
                    "SplashFeature", "LoginFeature", "OnboardingFeature",
                    "HouseholdSetupFeature", "ConnectionsFeature",
                    "InboxFeature", "TodayFeature", "ProfileFeature",
                    igTabBar_iOS,
                    tca,
                ],
                path: "Sources/Feature/EvenApp"
            ),
            .testTarget(name: "EvenCoreTests", dependencies: ["EvenCore"], path: "Tests/EvenCoreTests"),
            .testTarget(
                name: "EvenAppTests",
                dependencies: ["EvenApp", "AuthClient", "EvenCore", tca],
                path: "Tests/EvenAppTests"
            ),
            .testTarget(
                name: "LoginFeatureTests",
                dependencies: ["LoginFeature", "AuthClient", "EvenCore", tca],
                path: "Tests/LoginFeatureTests"
            ),
            .testTarget(
                name: "OnboardingFeatureTests",
                dependencies: ["OnboardingFeature", tca],
                path: "Tests/OnboardingFeatureTests"
            ),
            .testTarget(
                name: "HouseholdSetupFeatureTests",
                dependencies: ["HouseholdSetupFeature", "HouseholdClient", "EvenCore", tca],
                path: "Tests/HouseholdSetupFeatureTests"
            ),
            .testTarget(
                name: "ConnectionsFeatureTests",
                dependencies: ["ConnectionsFeature", "GoogleClient", "NotificationsClient", "ToastClient", "ToastUI", "EvenCore", tca],
                path: "Tests/ConnectionsFeatureTests"
            ),
            .testTarget(
                name: "InboxFeatureTests",
                dependencies: [
                    "InboxFeature", "EvenCore", "DraftsClient", "CalendarClient", "AuthClient",
                    "ToastClient", "ToastUI", tca,
                ],
                path: "Tests/InboxFeatureTests"
            ),
            .testTarget(
                name: "TodayFeatureTests",
                dependencies: [
                    "TodayFeature", "EvenApp", "EvenCore", "TasksClient", "SummaryClient", "WidgetClient",
                    "AuthClient", "ToastClient", "ToastUI", "HouseholdRealtimeClient", tca,
                ],
                path: "Tests/TodayFeatureTests"
            ),
            .testTarget(
                name: "ProfileFeatureTests",
                dependencies: [
                    "ProfileFeature", "EvenCore", "AuthClient", "HouseholdClient",
                    "GoogleClient", "ToastClient", "ToastUI", "ConnectionsFeature", tca,
                ],
                path: "Tests/ProfileFeatureTests"
            ),
        ]
    }()
)
