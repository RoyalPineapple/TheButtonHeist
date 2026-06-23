// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ButtonHeistPublicProductsImportContract",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "buttonheist-public-products-import-contract", targets: ["ButtonHeistPublicProductsImportContract"])
    ],
    dependencies: [
        .package(name: "ButtonHeist", path: "../../..")
    ],
    targets: [
        .executableTarget(
            name: "ButtonHeistPublicProductsImportContract",
            dependencies: [
                .product(name: "ThePlans", package: "ButtonHeist"),
                .product(name: "TheScore", package: "ButtonHeist"),
                .product(name: "ButtonHeistDSL", package: "ButtonHeist"),
                .product(name: "ButtonHeist", package: "ButtonHeist"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
