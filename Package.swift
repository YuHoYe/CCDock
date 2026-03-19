// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CCDock",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "CCDock",
            path: "CCDock",
            resources: [
                .copy("Resources/AppIcon.icns"),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
            ]
        )
    ]
)
