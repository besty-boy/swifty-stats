// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwiftyStats",
    defaultLocalization: "fr",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "SwiftyStatsCore", targets: ["SwiftyStatsCore"]),
        .executable(name: "SwiftyStats", targets: ["SwiftyStats"]),
    ],
    targets: [
        .target(
            name: "SwiftyStatsCore",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .executableTarget(
            name: "SwiftyStats",
            dependencies: ["SwiftyStatsCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
            ]
        ),
        .testTarget(
            name: "SwiftyStatsCoreTests",
            dependencies: ["SwiftyStatsCore"]
        ),
    ]
)
