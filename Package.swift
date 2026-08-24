// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Transi",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/tisfeng/SelectedTextKit", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "Transi",
            dependencies: [
                "SelectedTextKit"
            ],
            path: "Sources/Transi"
        )
    ]
)
