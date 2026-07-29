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

func combinedSources(_ lists: SourceFilesList...) -> SourceFilesList {
    .sourceFilesList(globs: lists.flatMap(\.globs))
}

func unhostedInsideJobTestTarget(
    name: String,
    bundleId: String,
    sources: SourceFilesList
) -> Target {
    .target(
        name: name,
        destinations: [.iPhone, .iPad],
        product: .unitTests,
        bundleId: bundleId,
        deploymentTargets: .iOS("16.0"),
        infoPlist: .default,
        sources: sources,
        dependencies: [
            .target(name: "ButtonHeistSupport"),
            .target(name: "ButtonHeistTestSupport"),
            .target(name: "ButtonHeistTesting"),
            .target(name: "TheInsideJob"),
            .target(name: "ThePlans"),
            .target(name: "TheScore"),
            .external(name: "AccessibilitySnapshotModel"),
        ],
        settings: .settings(base: [
            "SWIFT_STRICT_CONCURRENCY": "complete",
            "SWIFT_TREAT_WARNINGS_AS_ERRORS": "YES",
            "SWIFT_VERSION": "6",
        ])
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
        deploymentTargets: .iOS("16.0"),
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

func testScheme(name: String) -> Scheme {
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

func hostedTestScheme(name: String) -> Scheme {
    .scheme(
        name: name,
        buildAction: .buildAction(targets: [
            .target(name),
        ]),
        testAction: .targets(
            [
                .testableTarget(target: .target(name)),
            ],
            arguments: .arguments(environmentVariables: [
                "BUTTONHEIST_TEST_ANIMATION_SPEED": "$(BUTTONHEIST_TEST_ANIMATION_SPEED)",
            ]),
            expandVariableFromTarget: .target(name)
        )
    )
}

struct HostedTestDescriptor {
    let name: String
    let bundleId: String
    let sources: SourceFilesList
    let runsInBehaviorSuite: Bool

    var target: Target {
        hostedTestTarget(name: name, bundleId: bundleId, sources: sources)
    }

    var scheme: Scheme {
        hostedTestScheme(name: name)
    }
}

let insideJobSharedLogicWindowTestSources: SourceFilesList = [
    "ButtonHeist/Tests/TheInsideJobTests/AccessibilityNotificationBus+Testing.swift",
    "ButtonHeist/Tests/TheInsideJobTests/ActionEvidenceProjector+Testing.swift",
    "ButtonHeist/Tests/TheInsideJobTests/Helpers/AccessibilityElement+Construction.swift",
    "ButtonHeist/Tests/TheInsideJobTests/Helpers/AccessibilityTarget+Literal.swift",
    "ButtonHeist/Tests/TheInsideJobTests/Helpers/InterfaceObservationFactory.swift",
    "ButtonHeist/Tests/TheInsideJobTests/Helpers/SemanticObservationTestSupport.swift",
]

let insideJobSharedSocketTestSources: SourceFilesList = [
    "ButtonHeist/Tests/TheInsideJobTests/SocketServerTestSupport.swift",
]

let insideJobLogicOnlyTestSources: SourceFilesList = [
    "ButtonHeist/Tests/TheInsideJobTests/AXMethodOverridesTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/AccessibilityArmingTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/AccessibilityHierarchyFilterTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/AccessibilityHierarchyReconciliationTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/AccessibilityNotificationCallbackLifecycleTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/AccessibilityNotificationIdentityTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/AccessibilityPolicyBitmaskTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/AccessibilityPrimitiveTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/ActionTimingTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/ActivationPolicyTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/AnimationIdleCounterTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/ClientRequestPipelineTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/ConnectionScopeClassifyTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/ContainerFingerprintTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/DiagnosticsTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/ElementMatcherTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/ExploreOffFoldGateTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/FirstResponderEvidenceInvariantTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/HeistResultTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/HeistSyncOperationTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/IdAssignmentTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/InsideJobLifecycleReducerTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/InteractivityTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/InterfaceExplorationProgressTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/InterfaceTreeCaptureGeometryTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/InterfaceTreeMergingTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/InterfaceTreeSemanticIdentityTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/InterfaceTreeTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/InterfaceTreeViewportUpdateTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/LiveActionTargetFreshnessTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/LiveCaptureBoundaryAdversarialTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/LiveCaptureTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/MessageRateLimiterTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/ObjCRuntimeSwizzlingTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/RawParserEvidenceAdmissionTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/ResolvedPredicateRuntimeInputsTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/RotorCursorTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/ScreenCaptureFailureTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/ScreenClassifierTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/ScreenGenerationTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/SemanticObservationActionAdmissionTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/SemanticObservationDiscoveryTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/SemanticObservationLifecycleTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/SemanticObservationPublicationTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/SemanticObservationReplayTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/SemanticObservationStoreTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/SemanticObservationStreamTestSupport.swift",
    "ButtonHeist/Tests/TheInsideJobTests/ServerExposureTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/SettleSessionCancellationUpdatesTransientTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/SettleSessionStableSettleTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/SettleSessionTestSupport.swift",
    "ButtonHeist/Tests/TheInsideJobTests/SettleSessionTimeoutChangeBaselineTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/SettleSessionTimingMachineTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/SettlementDiagnosisTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/SettlementExecutionTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/SettlementReducerTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/SettlementResultProjectionTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/SimpleSocketServerDeliveryTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/SocketClientRegistryTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/SocketListenerRuntimeLifecycleTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/SocketReceiveBufferPolicyTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/SocketSendBufferTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/StartupConfigurationTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/SynthesisDeterminismTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TargetResolutionAlgebraTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TaskTrackerTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TestSentinelTask.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheBrainsObservationStateTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheBrainsPipelineFailureResultTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheBrainsPipelineObservationReductionTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheBrainsPipelineSuccessResultTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheBrainsPipelineTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheBrainsPipelineWaitEvidenceTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheFingerprintsTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheGetawayTransportWiringTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheMuscleAuthenticationTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheMuscleSecurityAndDeliveryTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheMuscleSessionLifecycleTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheMuscleStateMachineTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheMuscleTestSupport.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheMuscleWireAndAdmissionTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheSafecrackerScrollTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheSafecrackerTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheTripwirePolicyTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheVaultIdentityContextTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheVaultResolutionInterfaceStateTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheVaultResolutionLiveTargetEvidenceTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheVaultResolutionMatcherTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheVaultResolutionSettlementTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheVaultResolutionTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheVaultResolutionWaiterTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/WireConversionCustomContentRotorTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/WireConversionElementDeltaTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/WireConversionInterfaceTreeTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/WireConversionTraitActionTests.swift",
]

let insideJobWindowOnlyTestSources: SourceFilesList = [
    "ButtonHeist/Tests/TheInsideJobTests/AccessibilityNotificationObserverTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/ElementInflationProductActionViewportTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/ElementInflationProductDeadlineGeometryTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/ElementInflationProductIdentityTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/ElementInflationProductRevealScrollingTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/ElementInflationProductTestSupport.swift",
    "ButtonHeist/Tests/TheInsideJobTests/HeistIdDisambiguationTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/InsideJobRuntimeLifecycleTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/KeyboardWindowTestHelpers.swift",
    "ButtonHeist/Tests/TheInsideJobTests/LiveTargetReuseIntegrationTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/PresentationObscuringTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/RuntimeResourceObservationTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheBrainsActionDirectActionTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheBrainsActionGestureActionTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheBrainsActionHeistControlFlowTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheBrainsActionHeistExpectationTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheBrainsActionHeistForEachTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheBrainsActionHeistInvocationTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheBrainsActionHeistStepExecutionTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheBrainsActionTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheBrainsActionTextInputActionTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheBrainsScrollContainerSelectionTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheBrainsScrollDiscoveryCommandTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheBrainsScrollElementTargetGeometryTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheBrainsScrollInflationActionabilityTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheBrainsScrollInflationProgressTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheBrainsScrollInflationRefreshTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheBrainsScrollRevealInflationTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheBrainsScrollTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheBrainsScrollVisibleTargetIdentityTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheSafecrackerIntegrationTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheTripwireWindowTraversalTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheVaultCaptureTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheVaultCustomRotorTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheVaultObservationBuildingTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TripwireIntegrationTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/UIKitIdleTrackerIntegrationTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/WaitForIntegrationTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/Helpers/HostedTestAssertions.swift",
]

let insideJobIntegrationTestSources: SourceFilesList = [
    "ButtonHeist/Tests/TheInsideJobTests/ServerTransportTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/SimpleSocketServerIntegrationTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TLSIntegrationTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/Helpers/ButtonHeistNetworkTestClient.swift",
]

let insideJobHostedBehaviorTestSources: SourceFilesList = [
    "ButtonHeist/Tests/TheInsideJobTests/MenuOrderDogfoodHeistTests.swift",
    "ButtonHeist/Tests/TheInsideJobTests/TheTripwireHostedBehaviorTests.swift",
]

let insideJobLogicTestTarget = unhostedInsideJobTestTarget(
    name: "TheInsideJobLogicTests",
    bundleId: "com.buttonheist.theinsidejob.logic.tests",
    sources: combinedSources(
        insideJobLogicOnlyTestSources,
        insideJobSharedLogicWindowTestSources,
        insideJobSharedSocketTestSources
    )
)

let hostedTestDescriptors = [
    HostedTestDescriptor(
        name: "TheInsideJobWindowTests",
        bundleId: "com.buttonheist.theinsidejob.window.tests",
        sources: combinedSources(
            insideJobWindowOnlyTestSources,
            insideJobSharedLogicWindowTestSources,
            insideJobSharedSocketTestSources
        ),
        runsInBehaviorSuite: false
    ),
    HostedTestDescriptor(
        name: "TheInsideJobIntegrationTests",
        bundleId: "com.buttonheist.theinsidejob.integration.tests",
        sources: combinedSources(
            insideJobIntegrationTestSources,
            insideJobSharedSocketTestSources
        ),
        runsInBehaviorSuite: false
    ),
    HostedTestDescriptor(
        name: "TheInsideJobHostedBehaviorTests",
        bundleId: "com.buttonheist.theinsidejob.hosted.behavior.tests",
        sources: insideJobHostedBehaviorTestSources,
        runsInBehaviorSuite: true
    ),
    HostedTestDescriptor(
        name: "DogfoodFeatureFlowTests",
        bundleId: "com.buttonheist.dogfood.feature.tests",
        sources: ["ButtonHeist/Tests/DogfoodFeatureFlowTests/**"],
        runsInBehaviorSuite: true
    ),
    HostedTestDescriptor(
        name: "DogfoodRuntimeContractTests",
        bundleId: "com.buttonheist.dogfood.runtime.tests",
        sources: ["ButtonHeist/Tests/DogfoodRuntimeContractTests/**"],
        runsInBehaviorSuite: true
    ),
    HostedTestDescriptor(
        name: "AdversarialMutationTests",
        bundleId: "com.buttonheist.adversarial.mutation.tests",
        sources: ["ButtonHeist/Tests/AdversarialMutationTests/**"],
        runsInBehaviorSuite: true
    ),
    HostedTestDescriptor(
        name: "AdversarialNavigationTests",
        bundleId: "com.buttonheist.adversarial.navigation.tests",
        sources: ["ButtonHeist/Tests/AdversarialNavigationTests/**"],
        runsInBehaviorSuite: true
    ),
]

let behaviorTestDescriptors = hostedTestDescriptors.filter(\.runsInBehaviorSuite)
let iosHostedTestDescriptors = hostedTestDescriptors.filter {
    $0.name == "TheInsideJobWindowTests" || $0.runsInBehaviorSuite
}

let macFrameworkTestTargetNames = [
    "ButtonHeistSupportTests",
    "ThePlansTests",
    "TheScoreTests",
    "HeistDoctorCoreTests",
    "ButtonHeistTests",
]

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
            deploymentTargets: .multiplatform(iOS: "16.0", macOS: "14.0"),
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
            deploymentTargets: .multiplatform(iOS: "16.0", macOS: "14.0"),
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
            deploymentTargets: .multiplatform(iOS: "16.0", macOS: "14.0"),
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

        // MARK: - Result Diagnosis (macOS tooling core)
        .target(
            name: "HeistDoctorCore",
            destinations: .macOS,
            product: .framework,
            bundleId: "com.buttonheist.heistdoctorcore",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .default,
            sources: ["ButtonHeist/Sources/HeistDoctorCore/**"],
            dependencies: [
                .target(name: "ThePlans"),
                .target(name: "TheScore"),
            ]
        ),

        // MARK: - iOS Server Framework (embeds in iOS apps)
        // Includes ThePlant for automatic initialization via ObjC +load
        .target(
            name: "TheInsideJob",
            destinations: [.iPhone, .iPad],
            product: .framework,
            bundleId: "com.buttonheist.theinsidejob",
            deploymentTargets: .iOS("16.0"),
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
            deploymentTargets: .iOS("16.0"),
            infoPlist: .default,
            sources: ["ButtonHeist/Sources/ButtonHeistTesting/**"],

            dependencies: [
                .target(name: "TheInsideJob"),
                .target(name: "ThePlans"),
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
            deploymentTargets: .multiplatform(iOS: "16.0", macOS: "14.0"),
            infoPlist: .default,
            sources: ["ButtonHeist/Tests/TestSupport/**"],
            dependencies: [
                .target(name: "ButtonHeistSupport"),
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
            deploymentTargets: .iOS("16.0"),
            infoPlist: .default,
            sources: ["ButtonHeist/Tests/HostedTestSupport/**"],
            dependencies: [
                .target(name: "ButtonHeistTesting"),
                .target(name: "TheInsideJob"),
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

        // MARK: - HeistDoctorCore Tests
        .target(
            name: "HeistDoctorCoreTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.buttonheist.heistdoctorcore.tests",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .default,
            sources: ["ButtonHeist/Tests/HeistDoctorCoreTests/**"],
            dependencies: [
                .target(name: "ButtonHeistTestSupport"),
                .target(name: "HeistDoctorCore"),
                .target(name: "TheScore"),
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

    ] + [insideJobLogicTestTarget] + hostedTestDescriptors.map(\.target),
    schemes: [
        frameworkScheme(name: "ThePlans"),
        frameworkScheme(name: "TheScore"),
        frameworkScheme(name: "ButtonHeist"),
        frameworkScheme(name: "ButtonHeistSupport"),
        frameworkScheme(name: "ButtonHeistTesting"),
        frameworkScheme(name: "ButtonHeistTestSupport"),
        frameworkScheme(name: "HeistDoctorCore"),
        frameworkScheme(name: "TheInsideJob"),
        testScheme(name: "ButtonHeistSupportTests"),
        testScheme(name: "HeistDoctorCoreTests"),
        .scheme(
            name: "ThePlansTests",
            buildAction: .buildAction(targets: [
                .target("ThePlansTests"),
            ]),
            testAction: .targets([
                .testableTarget(target: .target("ThePlansTests")),
            ], arguments: .arguments(environmentVariables: [
                "HEIST_THEPLANS_BUILD_DIR": "$(BUILT_PRODUCTS_DIR)",
            ]), expandVariableFromTarget: .target("ThePlansTests"))
        ),
        testScheme(name: "TheScoreTests"),
        testScheme(name: "ButtonHeistTests"),
        testScheme(name: "TheInsideJobLogicTests"),
        .scheme(
            name: "MacFrameworkTests",
            buildAction: .buildAction(
                targets: macFrameworkTestTargetNames.map { .target($0) }
            ),
            testAction: .targets(
                macFrameworkTestTargetNames.map {
                    .testableTarget(target: .target($0), parallelization: .enabled)
                },
                arguments: .arguments(environmentVariables: [
                    "HEIST_THEPLANS_BUILD_DIR": "$(BUILT_PRODUCTS_DIR)",
                ]),
                expandVariableFromTarget: .target("ThePlansTests")
            )
        ),
    ] + hostedTestDescriptors.map(\.scheme) + [
        .scheme(
            name: "iOSHostedTests",
            buildAction: .buildAction(targets: iosHostedTestDescriptors.map { .target($0.name) }),
            testAction: .targets(
                iosHostedTestDescriptors.map {
                    .testableTarget(target: .target($0.name), parallelization: .disabled)
                },
                arguments: .arguments(environmentVariables: [
                    "BUTTONHEIST_TEST_ANIMATION_SPEED": "$(BUTTONHEIST_TEST_ANIMATION_SPEED)",
                ]),
                expandVariableFromTarget: .target("TheInsideJobWindowTests")
            )
        ),
        .scheme(
            name: "HostedBehaviorTests",
            buildAction: .buildAction(targets: behaviorTestDescriptors.map { .target($0.name) }),
            testAction: .targets(
                behaviorTestDescriptors.map {
                    .testableTarget(target: .target($0.name), parallelization: .disabled)
                },
                arguments: .arguments(environmentVariables: [
                    "BUTTONHEIST_TEST_ANIMATION_SPEED": "$(BUTTONHEIST_TEST_ANIMATION_SPEED)",
                ]),
                expandVariableFromTarget: .target("DogfoodFeatureFlowTests")
            )
        ),
    ]
)
