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
    settings: .settings(base: [
        "SWIFT_VERSION": "5.0",
        "LastSwiftMigration": "2620",
    ]),
    targets: [
        // MARK: - Shared Protocol Types (cross-platform)
        .target(
            name: "TheScore",
            destinations: [.iPhone, .iPad, .mac],
            product: .framework,
            bundleId: "com.buttonheist.thescore",
            deploymentTargets: .multiplatform(iOS: "17.0", macOS: "14.0"),
            infoPlist: .default,
            sources: ["ButtonHeist/Sources/TheScore/**"],
            scripts: [swiftlintScript],
            settings: .settings(base: [
                "SWIFT_VERSION": "5.0",
                "LastSwiftMigration": "2620",
            ])
        ),

        // MARK: - iOS Server Framework (embeds in iOS apps)
        // Includes ThePlant for automatic initialization via ObjC +load
        .target(
            name: "TheInsideJob",
            destinations: [.iPhone, .iPad],
            product: .framework,
            bundleId: "com.buttonheist.theinsidejob",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .default,
            sources: [
                "ButtonHeist/Sources/TheInsideJob/**",
                "ButtonHeist/Sources/ThePlant/**",
            ],
            headers: .headers(
                public: ["ButtonHeist/Sources/ThePlant/include/**"]
            ),
            scripts: [swiftlintScript],
            dependencies: [
                .target(name: "TheScore"),
                .target(name: "TheWheelman"),
                .external(name: "AccessibilitySnapshotParser"),
            ]
        ),

        // MARK: - Cross-Platform Networking Library
        .target(
            name: "TheWheelman",
            destinations: [.iPhone, .iPad, .mac],
            product: .framework,
            bundleId: "com.buttonheist.wheelman",
            deploymentTargets: .multiplatform(iOS: "17.0", macOS: "14.0"),
            infoPlist: .default,
            sources: ["ButtonHeist/Sources/TheWheelman/**"],
            scripts: [swiftlintScript],
            dependencies: [
                .target(name: "TheScore"),
            ],
            settings: .settings(base: [
                "SWIFT_VERSION": "5.0",
                "LastSwiftMigration": "2620",
            ])
        ),

        // MARK: - macOS Client Framework (single import for Mac consumers)
        .target(
            name: "ButtonHeist",
            destinations: .macOS,
            product: .framework,
            bundleId: "com.buttonheist.buttonheist",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .default,
            sources: ["ButtonHeist/Sources/TheButtonHeist/**"],
            scripts: [swiftlintScript],
            dependencies: [
                .target(name: "TheScore"),
                .target(name: "TheWheelman"),
            ]
        ),

        // MARK: - TheScore Tests
        .target(
            name: "TheScoreTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.buttonheist.thescore.tests",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .default,
            sources: ["ButtonHeist/Tests/TheScoreTests/**"],
            dependencies: [
                .target(name: "TheScore"),
            ]
        ),

        // MARK: - TheWheelman Tests
        .target(
            name: "TheWheelmanTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.buttonheist.thewheelman.tests",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .default,
            sources: ["ButtonHeist/Tests/TheWheelmanTests/**"],
            dependencies: [
                .target(name: "TheWheelman"),
                .target(name: "TheScore"),
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

        // MARK: - TheInsideJob Tests (iOS Simulator)
        .target(
            name: "TheInsideJobTests",
            destinations: [.iPhone, .iPad],
            product: .unitTests,
            bundleId: "com.buttonheist.theinsidejob.tests",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .default,
            sources: ["ButtonHeist/Tests/TheInsideJobTests/**"],
            dependencies: [
                .target(name: "TheInsideJob"),
                .target(name: "TheScore"),
            ]
        ),
    ],
    schemes: [
        .scheme(
            name: "TheScoreTests",
            buildAction: .buildAction(targets: [
                .target("TheScoreTests"),
                .target("TheScore"),
            ]),
            testAction: .targets([
                .testableTarget(target: .target("TheScoreTests")),
            ])
        ),
        .scheme(
            name: "TheWheelmanTests",
            buildAction: .buildAction(targets: [
                .target("TheWheelmanTests"),
                .target("TheWheelman"),
                .target("TheScore"),
            ]),
            testAction: .targets([
                .testableTarget(target: .target("TheWheelmanTests")),
            ])
        ),
        .scheme(
            name: "ButtonHeistTests",
            buildAction: .buildAction(targets: [
                .target("ButtonHeistTests"),
                .target("ButtonHeist"),
                .target("TheWheelman"),
                .target("TheScore"),
            ]),
            testAction: .targets([
                .testableTarget(target: .target("ButtonHeistTests")),
            ])
        ),
        .scheme(
            name: "TheInsideJobTests",
            buildAction: .buildAction(targets: [
                .target("TheInsideJobTests"),
                .target("TheInsideJob"),
                .target("TheWheelman"),
                .target("TheScore"),
            ]),
            testAction: .targets([
                .testableTarget(target: .target("TheInsideJobTests")),
            ])
        ),
    ]
)
