// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "HouseholdCommandCenter",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "HouseholdCore", targets: ["HouseholdCore"]),
        .executable(name: "HouseholdCommandCenter", targets: ["HouseholdCommandCenter"])
    ],
    targets: [
        .target(
            name: "HouseholdCore",
            path: "Sources/HouseholdCore"
        ),
        .executableTarget(
            name: "HouseholdCommandCenter",
            dependencies: ["HouseholdCore"],
            path: "Sources/HouseholdCommandCenter"
        ),
        .testTarget(
            name: "HouseholdCoreTests",
            dependencies: ["HouseholdCore"],
            path: "Tests/HouseholdCoreTests"
        )
    ]
)
