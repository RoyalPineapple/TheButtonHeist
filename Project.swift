import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
    name: "Accra",
    targets: [
        // MARK: - Shared Protocol Types (cross-platform)
        .target(
            name: "AccraCore",
            destinations: [.iPhone, .iPad, .mac],
            product: .framework,
            bundleId: "com.accra.core",
            deploymentTargets: .multiplatform(iOS: "17.0", macOS: "14.0"),
            infoPlist: .default,
            sources: ["AccraCore/Sources/AccraCore/**"]
        ),

        // MARK: - iOS Server Framework (embeds in iOS apps)
        // Includes AccraHostLoader for automatic initialization via ObjC +load
        .target(
            name: "AccraHost",
            destinations: [.iPhone, .iPad],
            product: .framework,
            bundleId: "com.accra.host",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .default,
            sources: [
                "AccraCore/Sources/AccraHost/**",
                "AccraCore/Sources/AccraHostLoader/**",
            ],
            headers: .headers(
                public: ["AccraCore/Sources/AccraHostLoader/include/**"]
            ),
            dependencies: [
                .target(name: "AccraCore"),
                .external(name: "AccessibilitySnapshotParser"),
            ]
        ),

        // MARK: - macOS Client Library
        .target(
            name: "AccraClient",
            destinations: .macOS,
            product: .framework,
            bundleId: "com.accra.client",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .default,
            sources: ["AccraCore/Sources/AccraClient/**"],
            dependencies: [
                .target(name: "AccraCore"),
            ]
        ),

        // MARK: - macOS Inspector App
        .target(
            name: "AccraInspector",
            destinations: .macOS,
            product: .app,
            bundleId: "com.accra.inspector",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .extendingDefault(with: [
                "NSPrincipalClass": "NSApplication",
                "CFBundleDisplayName": "Accra Inspector",
            ]),
            sources: ["AccraInspector/Sources/**"],
            resources: [],
            dependencies: [
                .target(name: "AccraCore"),
                .target(name: "AccraClient"),
            ]
        ),

        // MARK: - AccraCore Tests
        .target(
            name: "AccraCoreTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.accra.core.tests",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .default,
            sources: ["AccraCore/Tests/AccraCoreTests/**"],
            dependencies: [
                .target(name: "AccraCore"),
            ]
        ),

        // MARK: - AccraClient Tests
        .target(
            name: "AccraClientTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.accra.client.tests",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .default,
            sources: ["AccraCore/Tests/AccraClientTests/**"],
            dependencies: [
                .target(name: "AccraClient"),
                .target(name: "AccraCore"),
            ]
        ),
    ],
    schemes: [
        .scheme(
            name: "AccraCoreTests",
            buildAction: .buildAction(targets: [
                .target("AccraCoreTests"),
                .target("AccraCore"),
            ]),
            testAction: .targets([
                .testableTarget(target: .target("AccraCoreTests")),
            ])
        ),
        .scheme(
            name: "AccraClientTests",
            buildAction: .buildAction(targets: [
                .target("AccraClientTests"),
                .target("AccraClient"),
                .target("AccraCore"),
            ]),
            testAction: .targets([
                .testableTarget(target: .target("AccraClientTests")),
            ])
        ),
    ]
)
