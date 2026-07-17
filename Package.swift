// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "HouseholdCommandCenter",
    platforms: [
        .macOS(.v14), .iOS(.v17)
    ],
    products: [
        .library(name: "HouseholdCore", targets: ["HouseholdCore"]),
        .library(name: "EvenMobile", targets: ["EvenMobile"]),
        .executable(name: "HouseholdCommandCenter", targets: ["HouseholdCommandCenter"])
    ],
    targets: [
        .target(
            name: "HouseholdCore",
            path: "Sources/HouseholdCore"
        ),
        .target(
            name: "EvenMobile",
            dependencies: ["HouseholdCore"],
            path: "Sources/EvenMobile"
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
