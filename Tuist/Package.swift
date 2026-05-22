// swift-tools-version: 5.9
import PackageDescription

#if TUIST
import ProjectDescription
import ProjectDescriptionHelpers

let packageSettings = PackageSettings(
    productTypes: [
        "ArgumentParser": .framework,
        "AccessibilitySnapshotModel": .framework,
        "AccessibilitySnapshotParser": .framework,
        "AccessibilitySnapshotParser-ObjC": .framework,
        "X509": .staticFramework,
        "Crypto": .staticFramework,
        "SwiftASN1": .staticFramework,
        "CCryptoBoringSSL": .staticFramework,
        "CCryptoBoringSSLShims": .staticFramework,
        "CryptoBoringWrapper": .staticFramework,
        "_CertificateInternals": .staticFramework,
        "_CryptoExtras": .staticFramework,
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
