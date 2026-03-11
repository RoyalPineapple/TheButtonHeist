// swift-tools-version: 5.9
import PackageDescription

#if TUIST
import ProjectDescription
import ProjectDescriptionHelpers

let packageSettings = PackageSettings(
    productTypes: [
        "ArgumentParser": .framework,
        "AccessibilitySnapshotParser": .framework,
        "AccessibilitySnapshotParser-ObjC": .framework,
        "X509": .framework,
        "Crypto": .framework,
        "SwiftASN1": .framework,
    ]
)
#endif

let package = Package(
    name: "Dependencies",
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-certificates", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-crypto", from: "3.0.0"),
        .package(path: "../AccessibilitySnapshot"),
    ]
)
