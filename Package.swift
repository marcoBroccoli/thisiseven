// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "HouseholdCommandCenter",
    platforms: [
        .macOS(.v14), .iOS(.v17)
    ],
    products: [
        .library(name: "HouseholdCore", targets: ["HouseholdCore"]),
        .library(name: "EvenCore", targets: ["EvenCore"]),
        .library(name: "EvenMobile", targets: ["EvenMobile"]),
        .executable(name: "HouseholdCommandCenter", targets: ["HouseholdCommandCenter"])
    ],
    targets: [
        .target(
            name: "HouseholdCore",
            path: "Sources/HouseholdCore"
        ),
        .target(
            name: "EvenCore",
            path: "Sources/EvenCore"
        ),
        .target(
            name: "EvenMobile",
            dependencies: ["EvenCore"],
            path: "Sources/EvenMobile",
            resources: [.process("Resources")]
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
        ),
        .testTarget(
            name: "EvenCoreTests",
            dependencies: ["EvenCore"],
            path: "Tests/EvenCoreTests"
        )
    ]
)
