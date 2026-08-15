// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "QTranslateMac",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/tisfeng/SelectedTextKit", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "QTranslateMac",
            dependencies: [
                "SelectedTextKit"
            ],
            path: "Sources/QTranslateMac"
        )
    ]
)
