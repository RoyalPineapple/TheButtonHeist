// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "ButtonHeistMCP",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "buttonheist-mcp", targets: ["ButtonHeistMCP"])
    ],
    dependencies: [
        .package(path: "../ButtonHeist"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.11.0")
    ],
    targets: [
        .executableTarget(
            name: "ButtonHeistMCP",
            dependencies: [
                .product(name: "ButtonHeist", package: "ButtonHeist"),
                .product(name: "MCP", package: "swift-sdk")
            ],
            path: "Sources",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-parse-as-library", "-warnings-as-errors"])
            ]
        )
    ]
)
