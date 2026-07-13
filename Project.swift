import ProjectDescription

func frameworkScheme(name: String) -> Scheme {
    .scheme(
        name: name,
        buildAction: .buildAction(targets: [
            .target(name),
        ]),
        runAction: .runAction(executable: .target(name))
    )
}

func hostedTestTarget(
    name: String,
    bundleId: String,
    sources: SourceFilesList
) -> Target {
    .target(
        name: name,
        destinations: [.iPhone, .iPad],
        product: .unitTests,
        bundleId: bundleId,
        deploymentTargets: .iOS("17.0"),
        infoPlist: .default,
        sources: sources,
        dependencies: [
            .target(name: "ButtonHeistHostedTestSupport"),
            .target(name: "ButtonHeistSupport"),
            .target(name: "ButtonHeistTestSupport"),
            .target(name: "ButtonHeistTesting"),
            .target(name: "TheInsideJob"),
            .target(name: "ThePlans"),
            .target(name: "TheScore"),
            .external(name: "AccessibilitySnapshotModel"),
            .project(target: "BH Demo", path: "TestApp"),
        ],
        settings: .settings(base: [
            "BUNDLE_LOADER": "$(TEST_HOST)",
            "SWIFT_STRICT_CONCURRENCY": "complete",
            "SWIFT_TREAT_WARNINGS_AS_ERRORS": "YES",
            "SWIFT_VERSION": "6",
            "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/BHDemo.app/BHDemo",
        ])
    )
}

func hostedTestScheme(name: String) -> Scheme {
    .scheme(
        name: name,
        buildAction: .buildAction(targets: [
            .target(name),
        ]),
        testAction: .targets([
            .testableTarget(target: .target(name)),
        ])
    )
}

let project = Project(
    name: "ButtonHeist",
    options: .options(
        automaticSchemesOptions: .disabled
    ),
    settings: .settings(base: [
        "SWIFT_VERSION": "6",
        "LastSwiftMigration": "2620",
        "OTHER_SWIFT_FLAGS": "$(inherited) -package-name ButtonHeist",
        "SWIFT_TREAT_WARNINGS_AS_ERRORS": "YES",
    ]),
    targets: [
        // MARK: - Package-Internal Shared Support
        .target(
            name: "ButtonHeistSupport",
            destinations: [.iPhone, .iPad, .mac],
            product: .framework,
            bundleId: "com.buttonheist.support",
            deploymentTargets: .multiplatform(iOS: "17.0", macOS: "14.0"),
            infoPlist: .default,
            sources: ["ButtonHeist/Sources/ButtonHeistSupport/**"],
            dependencies: []
        ),

        // MARK: - Pure Heist Language
        .target(
            name: "ThePlans",
            destinations: [.iPhone, .iPad, .mac],
            product: .framework,
            bundleId: "com.buttonheist.theplans",
            deploymentTargets: .multiplatform(iOS: "17.0", macOS: "14.0"),
            infoPlist: .default,
            sources: ["ButtonHeist/Sources/ThePlans/**"],
            dependencies: [],
            settings: .settings(base: [
                "SWIFT_VERSION": "6",
                "LastSwiftMigration": "2620",
            ])
        ),

        // MARK: - Shared Protocol Types (cross-platform)
        .target(
            name: "TheScore",
            destinations: [.iPhone, .iPad, .mac],
            product: .framework,
            bundleId: "com.buttonheist.thescore",
            deploymentTargets: .multiplatform(iOS: "17.0", macOS: "14.0"),
            infoPlist: .default,
            sources: ["ButtonHeist/Sources/TheScore/**"],

            dependencies: [
                .target(name: "ThePlans"),
                .external(name: "AccessibilitySnapshotModel"),
            ],

            settings: .settings(base: [
                "SWIFT_VERSION": "6",
                "LastSwiftMigration": "2620",
            ])
        ),

        // MARK: - Swift Heist Authoring DSL (client-side)
        .target(
            name: "ButtonHeistDSL",
            destinations: [.iPhone, .iPad, .mac],
            product: .framework,
            bundleId: "com.buttonheist.dsl",
            deploymentTargets: .multiplatform(iOS: "17.0", macOS: "14.0"),
            infoPlist: .default,
            sources: ["ButtonHeist/Sources/ButtonHeistDSL/**"],
            dependencies: [
                .target(name: "ThePlans"),
            ],
            settings: .settings(base: [
                "SWIFT_VERSION": "6",
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

            dependencies: [
                .target(name: "ButtonHeistSupport"),
                .target(name: "ThePlans"),
                .target(name: "TheScore"),
                .external(name: "AccessibilitySnapshotCore"),
                .external(name: "AccessibilitySnapshotModel"),
                .external(name: "AccessibilitySnapshotParser"),
                .external(name: "AccessibilitySnapshotPreviews"),
            ]
        ),

        // MARK: - Public iOS Test Facade
        .target(
            name: "ButtonHeistTesting",
            destinations: [.iPhone, .iPad],
            product: .framework,
            bundleId: "com.buttonheist.testing",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .default,
            sources: ["ButtonHeist/Sources/ButtonHeistTesting/**"],

            dependencies: [
                .target(name: "ButtonHeistDSL"),
                .target(name: "TheInsideJob"),
            ],
            settings: .settings(base: [
                "ENABLE_TESTING_SEARCH_PATHS": "YES",
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

            dependencies: [
                .target(name: "ButtonHeistSupport"),
                .target(name: "ThePlans"),
                .target(name: "TheScore"),
                .external(name: "AccessibilitySnapshotModel"),
            ]
        ),

        // MARK: - Shared Test Support
        .target(
            name: "ButtonHeistTestSupport",
            destinations: [.iPhone, .iPad, .mac],
            product: .framework,
            bundleId: "com.buttonheist.testsupport",
            deploymentTargets: .multiplatform(iOS: "17.0", macOS: "14.0"),
            infoPlist: .default,
            sources: ["ButtonHeist/Tests/TestSupport/**"],
            dependencies: [
                .target(name: "ThePlans"),
                .target(name: "TheScore"),
                .external(name: "AccessibilitySnapshotModel"),
            ]
        ),

        // MARK: - iOS Hosted Test Support
        .target(
            name: "ButtonHeistHostedTestSupport",
            destinations: [.iPhone, .iPad],
            product: .framework,
            bundleId: "com.buttonheist.hostedtestsupport",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .default,
            sources: ["ButtonHeist/Tests/HostedTestSupport/**"],
            dependencies: [
                .target(name: "ButtonHeistTesting"),
                .target(name: "ThePlans"),
                .target(name: "TheScore"),
            ],
            settings: .settings(base: [
                "ENABLE_TESTING_SEARCH_PATHS": "YES",
                "SWIFT_STRICT_CONCURRENCY": "complete",
            ])
        ),

        // MARK: - ButtonHeistSupport Tests
        .target(
            name: "ButtonHeistSupportTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.buttonheist.support.tests",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .default,
            sources: ["ButtonHeist/Tests/ButtonHeistSupportTests/**"],
            dependencies: [
                .target(name: "ButtonHeistSupport"),
            ]
        ),

        // MARK: - ThePlans Tests
        .target(
            name: "ThePlansTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.buttonheist.theplans.tests",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .default,
            sources: ["ButtonHeist/Tests/ThePlansTests/**"],
            dependencies: [
                .target(name: "ThePlans"),
                .target(name: "ButtonHeistTestSupport"),
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
                .target(name: "ButtonHeistTestSupport"),
                .target(name: "ThePlans"),
                .target(name: "TheScore"),
                .external(name: "AccessibilitySnapshotModel"),
            ]
        ),

        // MARK: - ButtonHeistDSL Tests
        .target(
            name: "ButtonHeistDSLTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.buttonheist.dsl.tests",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .default,
            sources: ["ButtonHeist/Tests/ButtonHeistDSLTests/**"],
            dependencies: [
                .target(name: "ButtonHeistDSL"),
                .target(name: "ThePlans"),
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
                .target(name: "ButtonHeistSupport"),
                .target(name: "ButtonHeistTestSupport"),
                .target(name: "ButtonHeist"),
                .target(name: "ThePlans"),
                .target(name: "TheScore"),
                .external(name: "AccessibilitySnapshotModel"),
            ]
        ),

        // MARK: - iOS Simulator Tests (hosted in BH Demo)
        hostedTestTarget(
            name: "TheInsideJobTests",
            bundleId: "com.buttonheist.theinsidejob.tests",
            sources: ["ButtonHeist/Tests/TheInsideJobTests/**"]
        ),
        hostedTestTarget(
            name: "DogfoodFeatureFlowTests",
            bundleId: "com.buttonheist.dogfood.feature.tests",
            sources: ["ButtonHeist/Tests/DogfoodFeatureFlowTests/**"]
        ),
        hostedTestTarget(
            name: "DogfoodRuntimeContractTests",
            bundleId: "com.buttonheist.dogfood.runtime.tests",
            sources: ["ButtonHeist/Tests/DogfoodRuntimeContractTests/**"]
        ),
        hostedTestTarget(
            name: "AdversarialMutationTests",
            bundleId: "com.buttonheist.adversarial.mutation.tests",
            sources: ["ButtonHeist/Tests/AdversarialMutationTests/**"]
        ),
        hostedTestTarget(
            name: "AdversarialNavigationTests",
            bundleId: "com.buttonheist.adversarial.navigation.tests",
            sources: ["ButtonHeist/Tests/AdversarialNavigationTests/**"]
        ),
    ],
    schemes: [
        frameworkScheme(name: "ThePlans"),
        frameworkScheme(name: "TheScore"),
        frameworkScheme(name: "ButtonHeistDSL"),
        frameworkScheme(name: "ButtonHeist"),
        frameworkScheme(name: "ButtonHeistSupport"),
        frameworkScheme(name: "ButtonHeistTesting"),
        frameworkScheme(name: "ButtonHeistTestSupport"),
        frameworkScheme(name: "TheInsideJob"),
        .scheme(
            name: "ButtonHeistSupportTests",
            buildAction: .buildAction(targets: [
                .target("ButtonHeistSupportTests"),
                .target("ButtonHeistSupport"),
            ]),
            testAction: .targets([
                .testableTarget(target: .target("ButtonHeistSupportTests")),
            ])
        ),
        .scheme(
            name: "ThePlansTests",
            buildAction: .buildAction(targets: [
                .target("ThePlansTests"),
                .target("ThePlans"),
                .target("ButtonHeistTestSupport"),
            ]),
            testAction: .targets([
                .testableTarget(target: .target("ThePlansTests")),
            ], arguments: .arguments(environmentVariables: [
                "HEIST_THEPLANS_BUILD_DIR": "$(BUILT_PRODUCTS_DIR)",
            ]), expandVariableFromTarget: .target("ThePlansTests"))
        ),
        .scheme(
            name: "TheScoreTests",
            buildAction: .buildAction(targets: [
                .target("TheScoreTests"),
                .target("ButtonHeistTestSupport"),
                .target("ThePlans"),
                .target("TheScore"),
            ]),
            testAction: .targets([
                .testableTarget(target: .target("TheScoreTests")),
            ])
        ),
        .scheme(
            name: "ButtonHeistDSLTests",
            buildAction: .buildAction(targets: [
                .target("ButtonHeistDSLTests"),
                .target("ButtonHeistDSL"),
                .target("ThePlans"),
                .target("TheScore"),
            ]),
            testAction: .targets([
                .testableTarget(target: .target("ButtonHeistDSLTests")),
            ])
        ),
        .scheme(
            name: "ButtonHeistTests",
            buildAction: .buildAction(targets: [
                .target("ButtonHeistTests"),
                .target("ButtonHeistTestSupport"),
                .target("ButtonHeist"),
                .target("ThePlans"),
                .target("TheScore"),
            ]),
            testAction: .targets([
                .testableTarget(target: .target("ButtonHeistTests")),
            ])
        ),
        hostedTestScheme(name: "TheInsideJobTests"),
        hostedTestScheme(name: "DogfoodFeatureFlowTests"),
        hostedTestScheme(name: "DogfoodRuntimeContractTests"),
        hostedTestScheme(name: "AdversarialMutationTests"),
        hostedTestScheme(name: "AdversarialNavigationTests"),
    ]
)
