// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ButtonHeistMCP",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.10.0")
    ],
    targets: [
        .executableTarget(
            name: "buttonheist-mcp",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk")
            ],
            path: "Sources"
        )
    ]
)
