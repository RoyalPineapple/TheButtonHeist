// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ThePlansAuthoringImportContract",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "theplans-authoring-import-contract", targets: ["ThePlansAuthoringImportContract"]),
    ],
    dependencies: [
        .package(name: "ButtonHeist", path: "../../.."),
    ],
    targets: [
        .executableTarget(
            name: "ThePlansAuthoringImportContract",
            dependencies: [
                .product(name: "ThePlans", package: "ButtonHeist"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
