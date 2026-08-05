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
        .library(name: "Design", targets: ["Design"]),
        .library(name: "AuthClient", targets: ["AuthClient"]),
        .library(name: "HouseholdClient", targets: ["HouseholdClient"]),
        .library(name: "GoogleClient", targets: ["GoogleClient"]),
        .library(name: "DraftsClient", targets: ["DraftsClient"]),
        .library(name: "TasksClient", targets: ["TasksClient"]),
        .library(name: "SummaryClient", targets: ["SummaryClient"]),
        .library(name: "CalendarClient", targets: ["CalendarClient"]),
        .library(name: "WidgetClient", targets: ["WidgetClient"]),
        .library(name: "NotificationsClient", targets: ["NotificationsClient"]),
        .library(name: "DI", targets: ["DI"]),
        .library(name: "OnboardingFeature", targets: ["OnboardingFeature"]),
        .library(name: "HouseholdSetupFeature", targets: ["HouseholdSetupFeature"]),
        .library(name: "ConnectionsFeature", targets: ["ConnectionsFeature"]),
        .library(name: "InboxFeature", targets: ["InboxFeature"]),
        .library(name: "TodayFeature", targets: ["TodayFeature"]),
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

        return [
            .target(name: "EvenCore", path: "Sources/Core/EvenCore"),
            .target(name: "Design", path: "Sources/Design"),
            client("AuthClient"),
            clientLive("AuthClient"),
            client("HouseholdClient"),
            clientLive("HouseholdClient"),
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
                name: "DI",
                dependencies: [
                    "AuthClientLive",
                    "HouseholdClientLive",
                    "GoogleClientLive",
                    "DraftsClientLive",
                    "TasksClientLive",
                    "SummaryClientLive",
                    "CalendarClientLive",
                    "WidgetClientLive",
                    "NotificationsClientLive",
                ],
                path: "Sources/Core/DI"
            ),
            feature("OnboardingFeature", extra: ["AuthClient"]),
            feature("HouseholdSetupFeature", extra: ["HouseholdClient"]),
            feature("ConnectionsFeature", extra: ["GoogleClient", "NotificationsClient"]),
            feature("InboxFeature", extra: ["DraftsClient", "CalendarClient", "NotificationsClient", "AuthClient"]),
            feature("TodayFeature", extra: ["TasksClient", "SummaryClient", "WidgetClient", "AuthClient"]),
            .target(
                name: "EvenApp",
                dependencies: [
                    "EvenCore", "Design", "AuthClient", "DI",
                    "OnboardingFeature", "HouseholdSetupFeature", "ConnectionsFeature",
                    "InboxFeature", "TodayFeature",
                    tca,
                ],
                path: "Sources/Feature/EvenApp"
            ),
            .testTarget(name: "EvenCoreTests", dependencies: ["EvenCore"], path: "Tests/EvenCoreTests"),
            .testTarget(
                name: "EvenAppTests",
                dependencies: ["EvenApp", "AuthClient", tca],
                path: "Tests/EvenAppTests"
            ),
            .testTarget(
                name: "OnboardingFeatureTests",
                dependencies: ["OnboardingFeature", "AuthClient", "EvenCore", tca],
                path: "Tests/OnboardingFeatureTests"
            ),
            .testTarget(
                name: "HouseholdSetupFeatureTests",
                dependencies: ["HouseholdSetupFeature", "HouseholdClient", "EvenCore", tca],
                path: "Tests/HouseholdSetupFeatureTests"
            ),
            .testTarget(
                name: "ConnectionsFeatureTests",
                dependencies: ["ConnectionsFeature", "GoogleClient", "NotificationsClient", "EvenCore", tca],
                path: "Tests/ConnectionsFeatureTests"
            ),
            .testTarget(
                name: "InboxFeatureTests",
                dependencies: ["InboxFeature", "EvenCore", "DraftsClient", "CalendarClient", "AuthClient", tca],
                path: "Tests/InboxFeatureTests"
            ),
            .testTarget(
                name: "TodayFeatureTests",
                dependencies: ["TodayFeature", "EvenCore", "TasksClient", "SummaryClient", "WidgetClient", "AuthClient", tca],
                path: "Tests/TodayFeatureTests"
            ),
        ]
    }()
)
