import ProjectDescription
import ProjectDescriptionHelpers

let swiftlintScript: TargetScript = .post(
    script: """
    if command -v swiftlint >/dev/null 2>&1; then
        swiftlint --fix --quiet
        swiftlint lint --quiet
    else
        echo "warning: SwiftLint not installed"
    fi
    """,
    name: "SwiftLint",
    basedOnDependencyAnalysis: false
)

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
            sources: ["ButtonHeist/Sources/TheGoods/**"],
            scripts: [swiftlintScript],
            settings: .settings(base: ["SWIFT_VERSION": "5.0"])
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
            scripts: [swiftlintScript],
            dependencies: [
                .target(name: "TheGoods"),
                .target(name: "Wheelman"),
                .external(name: "AccessibilitySnapshotParser"),
            ]
        ),

        // MARK: - Cross-Platform Networking Library
        .target(
            name: "Wheelman",
            destinations: [.iPhone, .iPad, .mac],
            product: .framework,
            bundleId: "com.buttonheist.wheelman",
            deploymentTargets: .multiplatform(iOS: "17.0", macOS: "14.0"),
            infoPlist: .default,
            sources: ["ButtonHeist/Sources/Wheelman/**"],
            scripts: [swiftlintScript],
            dependencies: [
                .target(name: "TheGoods"),
            ],
            settings: .settings(base: ["SWIFT_VERSION": "5.0"])
        ),

        // MARK: - macOS Client Framework (single import for Mac consumers)
        .target(
            name: "ButtonHeist",
            destinations: .macOS,
            product: .framework,
            bundleId: "com.buttonheist.buttonheist",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .default,
            sources: ["ButtonHeist/Sources/ButtonHeist/**"],
            scripts: [swiftlintScript],
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

        // MARK: - ButtonHeist Tests
        .target(
            name: "ButtonHeistTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.buttonheist.tests",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .default,
            sources: ["ButtonHeist/Tests/ButtonHeistTests/**"],
            dependencies: [
                .target(name: "ButtonHeist"),
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
        .scheme(
            name: "ButtonHeistTests",
            buildAction: .buildAction(targets: [
                .target("ButtonHeistTests"),
                .target("ButtonHeist"),
                .target("Wheelman"),
                .target("TheGoods"),
            ]),
            testAction: .targets([
                .testableTarget(target: .target("ButtonHeistTests")),
            ])
        ),
    ]
)
