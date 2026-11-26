// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIToolSwitcher",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AIToolSwitcher", targets: ["AIToolSwitcher"])
    ],
    targets: [
        .executableTarget(
            name: "AIToolSwitcher",
            path: "Sources/AIToolSwitcher"
        ),
        .testTarget(
            name: "AIToolSwitcherTests",
            dependencies: ["AIToolSwitcher"],
            path: "Tests/AIToolSwitcherTests"
        )
    ]
)
