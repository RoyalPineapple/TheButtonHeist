#if canImport(UIKit)
import XCTest

@testable import TheInsideJob

@MainActor
final class HeistReceiptTests: XCTestCase {

    func testPublicHeistWarnRunsInAppProcess() async throws {
        let heist = try await Heist {
            Warn("ok")
        }

        XCTAssertEqual(heist.result.steps.map(\.kind), [.warn])
        XCTAssertEqual(heist.result.steps.first?.reportMessage, "ok")
        XCTAssertEqual(heist.result.warnings, [
            HeistExecutionWarning(path: "$.body[0]", message: "ok"),
        ])
    }

    func testPrebuiltPlanRunsThroughInAppRuntimeWithoutTransport() async throws {
        let job = TheInsideJob(token: "in-app-heist-plan-test")
        let plan = try HeistPlan("login") {
            Warn("prebuilt")
        }

        XCTAssertFalse(job.isRunning)
        XCTAssertFalse(job.brains.semanticObservationIsActive)
        XCTAssertFalse(job.tripwire.isPulseRunning)

        let heist = try await Heist(plan, argument: .none, runtime: .insideJob(job))

        XCTAssertEqual(heist.result.steps.map(\.kind), [.warn])
        XCTAssertEqual(heist.result.steps.first?.reportMessage, "prebuilt")
        XCTAssertFalse(job.isRunning)
        XCTAssertFalse(job.brains.semanticObservationIsActive)
        XCTAssertFalse(job.tripwire.isPulseRunning)
    }

    func testSingleStringRootHeistBindsOneRootArgument() async throws {
        let job = TheInsideJob(token: "in-app-heist-string-test")
        let capture = RuntimeCapture(job: job)

        let heist = try await Heist("milk", runtime: capture.runtime) { _ in
            Warn("string root")
        }

        XCTAssertEqual(heist.result.steps.map(\.kind), [.warn])
        XCTAssertEqual(capture.argument, .string(.literal("milk")))
        XCTAssertEqual(capture.plan?.parameter, .string(name: "input"))
    }

    func testRunHeistSwiftBoundaryBindsOneStringArgument() async throws {
        let job = TheInsideJob(token: "in-app-runheist-string-test")
        let capture = RuntimeCapture(job: job)

        let heist = try await RunHeist("addToCart", argument: "Milk", runtime: capture.runtime) { _ in
            Warn("adding")
        }

        XCTAssertEqual(heist.result.steps.map(\.kind), [.warn])
        XCTAssertEqual(capture.argument, .string(.literal("Milk")))
        XCTAssertEqual(capture.plan?.name, "addToCart")
        XCTAssertEqual(capture.plan?.parameter, .string(name: "input"))
    }

    func testSingleElementTargetRootHeistBindsOneRootArgument() async throws {
        let job = TheInsideJob(token: "in-app-heist-target-test")
        let capture = RuntimeCapture(job: job)

        let heist = try await Heist(ElementTarget.label("Delete"), runtime: capture.runtime) { _ in
            Warn("target root")
        }

        XCTAssertEqual(heist.result.steps.map(\.kind), [.warn])
        XCTAssertEqual(capture.argument, .elementTarget(.target(.label("Delete"))))
        XCTAssertEqual(capture.plan?.parameter, .elementTarget(name: "input"))
    }

    func testArrayInitializerLowersToForEachString() async throws {
        let job = TheInsideJob(token: "in-app-heist-array-test")
        let capture = RuntimeCapture(job: job)

        let heist = try await Heist(["milk", "eggs"], runtime: capture.runtime) { _ in
            Warn("item")
        }

        let step = try XCTUnwrap(heist.result.steps.first)
        XCTAssertEqual(step.kind, .forEachString)
        XCTAssertEqual(step.forEachStringEvidence?.count, 2)
        XCTAssertEqual(step.forEachStringEvidence?.iterationCount, 2)
        XCTAssertEqual(capture.plan?.parameter, HeistParameter.none)
        guard case .forEachString(let forEach)? = capture.plan?.body.first else {
            return XCTFail("Expected array initializer to build a ForEachString root step")
        }
        XCTAssertEqual(forEach.values, ["milk", "eggs"])
    }

    func testWarningsRollUpWithRuntimePath() async throws {
        let job = TheInsideJob(token: "in-app-heist-warning-test")
        enum Library {
            static let marker = HeistDef<Void>("Library.marker") {
                Warn("nested")
            }
        }

        let heist = try await Heist(runtime: .insideJob(job)) {
            Warn("root")
            try Library.marker()
        }

        XCTAssertEqual(heist.result.warnings, [
            HeistExecutionWarning(path: "$.body[0]", message: "root"),
            HeistExecutionWarning(path: "$.body[1].invoke.body[0]", message: "nested"),
        ])
    }

    func testFailedHeistThrowsFailureWithInspectableResult() async throws {
        let job = TheInsideJob(token: "in-app-heist-failure-test")

        do {
            _ = try await Heist(runtime: .insideJob(job)) {
                Fail("stop")
            }
            XCTFail("Expected failed heist to throw")
        } catch let failure as Heist.Failure {
            XCTAssertEqual(failure.failedStepPath, "$.body[0]")
            XCTAssertEqual(failure.failedStepKind, .fail)
            XCTAssertEqual(failure.message, "stop")
            XCTAssertEqual(failure.result.steps.map(\.kind), [.fail])
        }
    }

    func testFailureAbortsAtFirstFailedStepAndRestoresRuntime() async throws {
        let job = TheInsideJob(token: "in-app-heist-abort-test")

        do {
            _ = try await Heist(runtime: .insideJob(job)) {
                Warn("before")
                Fail("abort")
                Warn("after")
            }
            XCTFail("Expected failed heist to throw")
        } catch let failure as Heist.Failure {
            XCTAssertEqual(failure.failedStepPath, "$.body[1]")
            XCTAssertEqual(failure.result.abortedAtPath, "$.body[1]")
            XCTAssertEqual(failure.result.steps.map(\.kind), [.warn, .fail, .warn])
            XCTAssertEqual(failure.result.steps.map(\.status), [.passed, .failed, .skipped])
            let skipped = try XCTUnwrap(failure.result.steps.last)
            XCTAssertEqual(skipped.path, "$.body[2]")
            XCTAssertEqual(skipped.kind, .warn)
            XCTAssertNil(skipped.intent)
            XCTAssertNil(skipped.evidence)
            XCTAssertNil(skipped.failure)
            XCTAssertFalse(job.isRunning)
            XCTAssertFalse(job.brains.semanticObservationIsActive)
            XCTAssertFalse(job.tripwire.isPulseRunning)
        }
    }

    func testReceiptMatchesDirectBrainsExecutionShape() async throws {
        let job = TheInsideJob(token: "in-app-heist-machinery-test")
        let plan = try HeistPlan {
            Warn("same executor")
        }

        job.brains.startSemanticObservation()
        let directAction = await job.brains.executeHeistPlan(plan)
        job.brains.stopSemanticObservation()
        let direct = try XCTUnwrap(directAction.heistExecutionPayload)

        let heist = try await Heist(plan, runtime: .insideJob(job))

        XCTAssertEqual(heist.result.steps.map(\.path), direct.steps.map(\.path))
        XCTAssertEqual(heist.result.steps.map(\.kind), direct.steps.map(\.kind))
        XCTAssertEqual(heist.result.steps.map(\.reportMessage), direct.steps.map(\.reportMessage))
    }
}

@MainActor
private final class RuntimeCapture {
    private let job: TheInsideJob
    private(set) var plan: HeistPlan?
    private(set) var argument: HeistArgument?

    init(job: TheInsideJob) {
        self.job = job
    }

    var runtime: InAppHeistRuntime {
        InAppHeistRuntime { plan, argument in
            self.plan = plan
            self.argument = argument
            return await self.job.executeInAppHeist(plan, argument: argument)
        }
    }
}

private extension ActionResult {
    var heistExecutionPayload: HeistExecutionResult? {
        guard case .heistExecution(let result) = payload else { return nil }
        return result
    }
}

#endif // canImport(UIKit)
