import BumperBowlingCore
import BumperBowlingTestSupport
import Testing

@Suite("Canonical runtime ownership")
struct CanonicalRuntimeOwnerRuleTests {
    @Test
    func canonicalOwnersSatisfyRuntimeRules() throws {
        let report = try evaluateButtonHeistRules()

        #expect(report.violations.isEmpty)
    }

    @Test
    func predicateWaitLifecycleConstructionOutsideExecutorIsRejected() throws {
        let path: RelativeFilePath =
            "ButtonHeist/Sources/TheInsideJob/TheBrains/CompetingWait.swift"
        let report = try evaluateButtonHeistRules(
            path: path,
            component: .runtime,
            source: "func runWait() { _ = PredicateWaitLifecycleMachine() }"
        )

        expectOnlyViolation(
            in: report,
            id: "buttonheist.predicate_wait_lifecycle_ownership",
            path: path
        )
    }

    @Test
    func taskTrackingOutsideCanonicalOwnersIsRejected() throws {
        let path: RelativeFilePath =
            "ButtonHeist/Sources/TheInsideJob/TheSafecracker/CompetingTaskOwner.swift"
        let report = try evaluateButtonHeistRules(
            path: path,
            component: .runtime,
            source: "let tasks = TaskTracker()"
        )

        #expect(report.contains(ViolationMatcher(
            id: "buttonheist.task_tracker_ownership",
            path: path
        )))
    }

    @Test
    func interactionBacklogsOutsideTheCanonicalExecutorAreRejected() throws {
        let path: RelativeFilePath =
            "ButtonHeist/Sources/TheInsideJob/TheBrains/CompetingInteractionQueue.swift"
        let report = try evaluateButtonHeistRules(
            path: path,
            component: .runtime,
            source: "let executor = InteractionRequestExecutor()"
        )

        expectOnlyViolation(
            in: report,
            id: "buttonheist.interaction_request_executor_ownership",
            path: path
        )
    }

    @Test
    func receiptConstructionTrapsAreRejected() throws {
        let path: RelativeFilePath =
            "ButtonHeist/Sources/TheScore/Receipts/HeistExecutionStepResult+Admission.swift"
        let report = try evaluateButtonHeistRules(
            path: path,
            component: .score,
            source: "func admit() { preconditionFailure(\"mismatch\") }"
        )

        #expect(report.contains(ViolationMatcher(
            id: "buttonheist.receipt_construction_safety",
            path: path
        )))
    }

    @Test
    func receiptNodeExtensionsOutsideCodecOwnerAreRejected() throws {
        let path: RelativeFilePath =
            "ButtonHeist/Sources/TheScore/Receipts/CompetingReceiptCodec.swift"
        let report = try evaluateButtonHeistRules(
            path: path,
            component: .score,
            source: "extension HeistExecutionStepNode {}"
        )

        #expect(report.contains(ViolationMatcher(
            id: "buttonheist.receipt_node_codec_ownership",
            path: path
        )))
    }

    @Test
    func interfaceGraphCommitsOutsidePublicationOwnerAreRejected() throws {
        let path: RelativeFilePath =
            "ButtonHeist/Sources/TheInsideJob/TheStash/CompetingCommitter.swift"
        let report = try evaluateButtonHeistRules(
            path: path,
            component: .runtime,
            source: "func commit() { reduceInterfaceGraph() }"
        )

        #expect(report.contains(ViolationMatcher(
            id: "buttonheist.semantic_observation_commit_ownership",
            path: path
        )))
    }

    @Test
    func directInterfaceTreeMatchingOutsideOwnersIsRejected() throws {
        let path: RelativeFilePath =
            "ButtonHeist/Sources/TheInsideJob/TheBrains/CompetingMatcher.swift"
        let report = try evaluateButtonHeistRules(
            path: path,
            component: .runtime,
            source: """
            func match() {
                matchingTreeElements()
                matchingTreeContainers()
            }
            """
        )

        #expect(report.violations.count == 2)
        #expect(report.contains(ViolationMatcher(
            id: "buttonheist.interface_tree_element_matching_ownership",
            path: path
        )))
        #expect(report.contains(ViolationMatcher(
            id: "buttonheist.interface_tree_container_matching_ownership",
            path: path
        )))
    }

    private func expectOnlyViolation(
        in report: RuleReport,
        id: RuleID,
        path: RelativeFilePath
    ) {
        #expect(report.violations.count == 1)
        #expect(report.contains(ViolationMatcher(id: id, path: path)))
    }
}
