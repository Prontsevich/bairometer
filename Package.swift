// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Bairometer",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Bairometer", targets: ["Bairometer"]),
        .executable(name: "BairometerClaudeStatusLine", targets: ["BairometerClaudeStatusLine"]),
        .library(name: "BairometerCore", targets: ["BairometerCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.10.0")
    ],
    targets: [
        .executableTarget(
            name: "Bairometer",
            dependencies: ["BairometerCore"],
            path: "Sources/Bairometer",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "BairometerClaudeStatusLine",
            dependencies: ["BairometerCore"],
            path: "Sources/BairometerClaudeStatusLine"
        ),
        .target(
            name: "BairometerCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/BairometerCore"
        ),
        .testTarget(
            name: "BairometerCoreTests",
            dependencies: ["BairometerCore"],
            path: "Tests/BairometerCoreTests",
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "BairometerTests",
            dependencies: ["Bairometer"],
            path: "Tests/BairometerTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
