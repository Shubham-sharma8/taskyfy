// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Taskyfy",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "TaskyfyCore", targets: ["TaskyfyCore"]),
        .executable(name: "Taskyfy", targets: ["Taskyfy"]),
        .executable(name: "TaskyfyHelper", targets: ["TaskyfyHelper"])
    ],
    targets: [
        .target(
            name: "TaskyfyCore",
            resources: [
                .copy("Resources/processes.json")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("IOKit"),
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("UserNotifications")
            ]
        ),
        .executableTarget(
            name: "Taskyfy",
            dependencies: ["TaskyfyCore"],
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("AppKit"),
                .linkedFramework("Charts"),
                .linkedFramework("Symbols"),
                .linkedFramework("Carbon")
            ]
        ),
        .executableTarget(
            name: "TaskyfyHelper",
            dependencies: ["TaskyfyCore"]
        ),
        .executableTarget(
            name: "TaskyfyTests",
            dependencies: ["TaskyfyCore"],
            path: "Tests/TaskyfyTests"
        )
    ]
)
