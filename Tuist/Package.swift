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
        .package(url: "https://github.com/apple/swift-argument-parser", .upToNextMinor(from: "1.7.0")),
        .package(url: "https://github.com/apple/swift-certificates", .upToNextMinor(from: "1.18.0")),
        .package(url: "https://github.com/apple/swift-crypto", .upToNextMinor(from: "3.15.0")),
        .package(path: "../submodules/AccessibilitySnapshotBH"),
    ]
)
