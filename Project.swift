import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
    name: "ButtonHeist",
    targets: [
        // MARK: - Shared Protocol Types (cross-platform)
        .target(
            name: "TheGoods",
            destinations: [.iPhone, .iPad, .mac],
            product: .framework,
            bundleId: "com.buttonheist.thegoods",
            deploymentTargets: .multiplatform(iOS: "17.0", macOS: "14.0"),
            infoPlist: .default,
            sources: ["ButtonHeist/Sources/TheGoods/**"]
        ),

        // MARK: - iOS Server Framework (embeds in iOS apps)
        // Includes InsideManLoader for automatic initialization via ObjC +load
        .target(
            name: "InsideMan",
            destinations: [.iPhone, .iPad],
            product: .framework,
            bundleId: "com.buttonheist.insideman",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .default,
            sources: [
                "ButtonHeist/Sources/InsideMan/**",
                "ButtonHeist/Sources/InsideManLoader/**",
            ],
            headers: .headers(
                public: ["ButtonHeist/Sources/InsideManLoader/include/**"]
            ),
            dependencies: [
                .target(name: "TheGoods"),
                .external(name: "AccessibilitySnapshotParser"),
            ]
        ),

        // MARK: - macOS Client Library
        .target(
            name: "Wheelman",
            destinations: .macOS,
            product: .framework,
            bundleId: "com.buttonheist.wheelman",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .default,
            sources: ["ButtonHeist/Sources/Wheelman/**"],
            dependencies: [
                .target(name: "TheGoods"),
            ]
        ),

        // MARK: - macOS Stakeout App
        .target(
            name: "Stakeout",
            destinations: .macOS,
            product: .app,
            bundleId: "com.buttonheist.stakeout",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .extendingDefault(with: [
                "NSPrincipalClass": "NSApplication",
                "CFBundleDisplayName": "Stakeout",
                "NSLocalNetworkUsageDescription": "Stakeout needs local network access to discover and connect to iOS apps running InsideMan.",
                "NSBonjourServices": ["_buttonheist._tcp"],
            ]),
            sources: ["Stakeout/Sources/**"],
            resources: [],
            entitlements: .file(path: "Stakeout/Stakeout.entitlements"),
            dependencies: [
                .target(name: "TheGoods"),
                .target(name: "Wheelman"),
            ]
        ),

        // MARK: - TheGoods Tests
        .target(
            name: "TheGoodsTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.buttonheist.thegoods.tests",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .default,
            sources: ["ButtonHeist/Tests/TheGoodsTests/**"],
            dependencies: [
                .target(name: "TheGoods"),
            ]
        ),

        // MARK: - Wheelman Tests
        .target(
            name: "WheelmanTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.buttonheist.wheelman.tests",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .default,
            sources: ["ButtonHeist/Tests/WheelmanTests/**"],
            dependencies: [
                .target(name: "Wheelman"),
                .target(name: "TheGoods"),
            ]
        ),
    ],
    schemes: [
        .scheme(
            name: "TheGoodsTests",
            buildAction: .buildAction(targets: [
                .target("TheGoodsTests"),
                .target("TheGoods"),
            ]),
            testAction: .targets([
                .testableTarget(target: .target("TheGoodsTests")),
            ])
        ),
        .scheme(
            name: "WheelmanTests",
            buildAction: .buildAction(targets: [
                .target("WheelmanTests"),
                .target("Wheelman"),
                .target("TheGoods"),
            ]),
            testAction: .targets([
                .testableTarget(target: .target("WheelmanTests")),
            ])
        ),
    ]
)
