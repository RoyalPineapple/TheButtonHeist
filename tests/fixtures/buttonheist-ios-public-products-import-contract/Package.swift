// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ButtonHeistIOSPublicProductsImportContract",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .executable(name: "buttonheist-ios-public-products-import-contract", targets: ["ButtonHeistIOSPublicProductsImportContract"])
    ],
    dependencies: [
        .package(name: "ButtonHeist", path: "../../..")
    ],
    targets: [
        .executableTarget(
            name: "ButtonHeistIOSPublicProductsImportContract",
            dependencies: [
                .product(name: "ButtonHeistTesting", package: "ButtonHeist"),
                .product(name: "TheInsideJob", package: "ButtonHeist"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
