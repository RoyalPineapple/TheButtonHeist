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

func frameworkScheme(name: String) -> Scheme {
    .scheme(
        name: name,
        buildAction: .buildAction(targets: [
            .target(name),
        ]),
        runAction: .runAction(executable: .target(name))
    )
}

let project = Project(
    name: "ButtonHeist",
    options: .options(
        automaticSchemesOptions: .disabled
    ),
    settings: .settings(base: [
        "SWIFT_VERSION": "5.0",
        "LastSwiftMigration": "2620",
        "SWIFT_TREAT_WARNINGS_AS_ERRORS": "YES",
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
                .external(name: "AccessibilitySnapshotParser"),
                .external(name: "X509"),
                .external(name: "Crypto"),
            ]
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
                .external(name: "Crypto"),
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
                .external(name: "Crypto"),
            ]
        ),

        // MARK: - TheInsideJob Tests (iOS Simulator, hosted in AccessibilityTestApp)
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
                .external(name: "Crypto"),
                .project(target: "AccessibilityTestApp", path: "TestApp"),
            ],
            settings: .settings(base: [
                "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/AccessibilityTestApp.app/AccessibilityTestApp",
                "BUNDLE_LOADER": "$(TEST_HOST)",
                "CODE_SIGN_STYLE": "Automatic",
                "DEVELOPMENT_TEAM": "Y4XC6NM5DD",
            ])
        ),
    ],
    schemes: [
        frameworkScheme(name: "TheScore"),
        frameworkScheme(name: "ButtonHeist"),
        frameworkScheme(name: "TheInsideJob"),
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
            name: "ButtonHeistTests",
            buildAction: .buildAction(targets: [
                .target("ButtonHeistTests"),
                .target("ButtonHeist"),
                .target("TheScore"),
            ]),
            testAction: .targets([
                .testableTarget(target: .target("ButtonHeistTests")),
            ])
        ),
    ]
)
