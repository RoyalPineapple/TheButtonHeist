import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
    name: "Accra",
    targets: [
        // MARK: - Shared Protocol Types (cross-platform)
        .target(
            name: "AccessibilityBridgeProtocol",
            destinations: [.iPhone, .iPad, .mac],
            product: .framework,
            bundleId: "com.accra.accessibilitybridgeprotocol",
            deploymentTargets: .multiplatform(iOS: "17.0", macOS: "14.0"),
            infoPlist: .default,
            sources: ["AccessibilityBridgeProtocol/Sources/AccessibilityBridgeProtocol/**"]
        ),

        // MARK: - iOS Server Framework (embeds in iOS apps)
        .target(
            name: "AccessibilityBridgeServer",
            destinations: [.iPhone, .iPad],
            product: .framework,
            bundleId: "com.accra.accessibilitybridgeserver",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .default,
            sources: ["AccessibilityBridgeProtocol/Sources/AccessibilityBridgeServer/**"],
            dependencies: [
                .target(name: "AccessibilityBridgeProtocol"),
                .external(name: "AccessibilitySnapshotParser"),
            ]
        ),

        // MARK: - macOS Inspector App
        .target(
            name: "AccessibilityInspector",
            destinations: .macOS,
            product: .app,
            bundleId: "com.accra.accessibilityinspector",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .extendingDefault(with: [
                "NSPrincipalClass": "NSApplication",
                "CFBundleDisplayName": "Accessibility Inspector",
            ]),
            sources: .sourceFilesList(globs: [
                .glob("AccessibilityInspector/AccessibilityInspector/**", excluding: ["AccessibilityInspector/AccessibilityInspector/CLI/**"])
            ]),
            resources: [],
            dependencies: [
                .target(name: "AccessibilityBridgeProtocol"),
            ]
        ),
    ]
)
