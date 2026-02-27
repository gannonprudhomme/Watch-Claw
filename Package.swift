// swift-tools-version: 6.2
// This file exists solely for rules_swift_package_manager to resolve external SPM dependencies.
// The actual build graph is defined in BUILD.bazel files throughout the project.

import PackageDescription

let package = Package(
    name: "WatchClaw",
    platforms: [
        .watchOS(.v26),
        .iOS(.v26),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-identified-collections.git", from: "1.1.0"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", exact: "1.23.0"),
        .package(url: "https://github.com/pointfreeco/swift-navigation.git", exact: "2.3.2"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.6.3"),
        .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.7.0"),
        .package(url: "https://github.com/pointfreeco/swift-concurrency-extras", from: "1.3.1"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.4"),
        .package(url: "https://github.com/apple/swift-log", from: "1.6.4"),
    ]
)
