// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Agently",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "agently-runner", targets: ["AgentlyRunner"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.5.0")
    ],
    targets: [
        .executableTarget(
            name: "AgentlyRunner",
            dependencies: [
                "UIGraph",
                "Skills",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log")
            ]
        ),
        .target(
            name: "UIGraph", 
            dependencies: [
                .product(name: "Logging", package: "swift-log")
            ]
        ),
        .target(
            name: "Skills", 
            dependencies: [
                "UIGraph",
                .product(name: "Logging", package: "swift-log")
            ]
        ),
        .testTarget(
            name: "UIGraphTests", 
            dependencies: ["UIGraph"]
        ),
        .testTarget(
            name: "SkillsTests", 
            dependencies: ["Skills"]
        )
    ]
)