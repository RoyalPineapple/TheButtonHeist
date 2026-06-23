// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ButtonHeistExternalImportContract",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "buttonheist-import-contract", targets: ["ButtonHeistImportContract"])
    ],
    dependencies: [
        .package(name: "ButtonHeist", path: "../../..")
    ],
    targets: [
        .executableTarget(
            name: "ButtonHeistImportContract",
            dependencies: [
                .product(name: "ButtonHeist", package: "ButtonHeist")
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
