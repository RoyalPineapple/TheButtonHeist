#if canImport(UIKit)
import XCTest

@testable import TheInsideJob

@MainActor
final class InsideJobLifecycleStateMachineTests: XCTestCase {
    private let machine = InsideJobLifecycleMachine()

    func testLifecycleNotificationsProduceOnlySchedulingEffects() {
        let fixture = Fixture()
        let state = TheInsideJob.ServerPhase.running(fixture.resources)

        XCTAssertEqual(
            machine.advance(state, with: .lifecycleSuspensionNotification),
            .changed(to: state, effects: [.scheduleSuspend])
        )
        XCTAssertEqual(
            machine.advance(state, with: .terminationNotification),
            .changed(to: state, effects: [.scheduleStop])
        )
        XCTAssertEqual(
            machine.advance(
                .suspended(fixture.suspendedRuntime),
                with: .foregroundNotification(replacingExisting: false)
            ),
            .changed(
                to: .suspended(fixture.suspendedRuntime),
                effects: [.scheduleResume(afterCancelling: nil)]
            )
        )
        XCTAssertEqual(
            machine.advance(
                .resuming(fixture.resumeAttempt),
                with: .foregroundNotification(replacingExisting: true)
            ),
            .changed(
                to: .resuming(fixture.resumeAttempt),
                effects: [.scheduleResume(afterCancelling: fixture.resumeAttempt)]
            )
        )

        let noOpStates: [TheInsideJob.ServerPhase] = [
            .stopped,
            .starting(fixture.startAttempt),
            .running(fixture.resources),
            .suspending(fixture.suspension),
            .resuming(fixture.resumeAttempt),
            .stopping(fixture.stopAttempt),
        ]
        for noOpState in noOpStates {
            XCTAssertEqual(
                machine.advance(
                    noOpState,
                    with: .foregroundNotification(replacingExisting: false)
                ),
                .changed(to: noOpState)
            )
        }
    }

    func testStartTransitionsAndRejections() {
        let fixture = Fixture()
        let startRequest = TheInsideJob.InsideJobTransportStartRequest(
            id: fixture.id,
            phase: .startup,
            transport: fixture.transport,
            idleTimerBaseline: false
        )

        XCTAssertEqual(
            machine.advance(
                .stopped,
                with: .startRequested(fixture.startAttempt, idleTimerBaseline: false)
            ),
            .changed(
                to: .starting(fixture.startAttempt),
                effects: [.startTransport(startRequest)]
            )
        )
        XCTAssertEqual(
            machine.advance(
                .starting(fixture.startAttempt),
                with: .startSucceeded(fixture.id, fixture.resources)
            ),
            .changed(
                to: .running(fixture.resources),
                effects: [.activateRuntime(fixture.resources)]
            )
        )
        XCTAssertEqual(
            machine.advance(
                .starting(fixture.startAttempt),
                with: .startFailed(fixture.id)
            ),
            .changed(to: .stopped, effects: [.cleanupTransport(fixture.transport)])
        )
        XCTAssertEqual(
            machine.advance(
                .running(fixture.resources),
                with: .startRequested(fixture.startAttempt, idleTimerBaseline: false)
            ),
            .rejected(.alreadyActive, stayingIn: .running(fixture.resources))
        )
        XCTAssertEqual(
            machine.advance(
                .starting(fixture.startAttempt),
                with: .startSucceeded(fixture.otherID, fixture.resources)
            ),
            .rejected(.staleStartAttempt, stayingIn: .starting(fixture.startAttempt))
        )
        XCTAssertEqual(
            machine.advance(
                .starting(fixture.startAttempt),
                with: .startFailed(fixture.otherID)
            ),
            .rejected(.staleStartAttempt, stayingIn: .starting(fixture.startAttempt))
        )
    }

    func testStopTransitionsUseOneAttemptThroughResumeCancellation() {
        let fixture = Fixture()
        let stopping = TheInsideJob.ServerPhase.stopping(fixture.stopAttempt)

        XCTAssertEqual(
            machine.advance(
                .starting(fixture.startAttempt),
                with: .stopRequested(fixture.stopAttempt)
            ),
            .changed(
                to: stopping,
                effects: [.cleanupTransport(fixture.transport), .tearDownRuntimeServices]
            )
        )
        XCTAssertEqual(
            machine.advance(
                .running(fixture.resources),
                with: .stopRequested(fixture.stopAttempt)
            ),
            .changed(
                to: stopping,
                effects: [
                    .releaseResources(policy: .stop, idleTimerBaseline: false),
                    .stopTransport(fixture.transport),
                    .tearDownRuntimeServices,
                ]
            )
        )
        XCTAssertEqual(
            machine.advance(
                .suspending(fixture.suspension),
                with: .stopRequested(fixture.stopAttempt)
            ),
            .changed(
                to: stopping,
                effects: [
                    .releaseResources(policy: .stop, idleTimerBaseline: false),
                    .stopTransport(fixture.transport),
                    .tearDownRuntimeServices,
                ]
            )
        )
        XCTAssertEqual(
            machine.advance(
                .suspended(fixture.suspendedRuntime),
                with: .stopRequested(fixture.stopAttempt)
            ),
            .changed(
                to: stopping,
                effects: [
                    .releaseResources(policy: .stop, idleTimerBaseline: false),
                    .tearDownRuntimeServices,
                ]
            )
        )
        XCTAssertEqual(
            machine.advance(
                .resuming(fixture.resumeAttempt),
                with: .stopRequested(fixture.stopAttempt)
            ),
            .changed(
                to: stopping,
                effects: [
                    .cancelResume(fixture.resumeAttempt),
                    .releaseResources(policy: .stop, idleTimerBaseline: false),
                    .tearDownRuntimeServices,
                ]
            )
        )
        XCTAssertEqual(
            machine.advance(stopping, with: .stopFinished(fixture.stopAttempt.id)),
            .changed(to: .stopped)
        )
    }

    func testStopRejectionsKeepTheCurrentPhase() {
        let fixture = Fixture()
        let stopping = TheInsideJob.ServerPhase.stopping(fixture.stopAttempt)

        XCTAssertEqual(
            machine.advance(.stopped, with: .stopRequested(fixture.stopAttempt)),
            .rejected(.alreadyStopped, stayingIn: .stopped)
        )
        XCTAssertEqual(
            machine.advance(stopping, with: .stopRequested(fixture.stopAttempt)),
            .rejected(.alreadyStopping, stayingIn: stopping)
        )
        XCTAssertEqual(
            machine.advance(stopping, with: .stopFinished(fixture.otherID)),
            .rejected(.staleStopAttempt, stayingIn: stopping)
        )
        XCTAssertEqual(
            machine.advance(
                .running(fixture.resources),
                with: .stopFinished(fixture.stopAttempt.id)
            ),
            .rejected(.staleStopAttempt, stayingIn: .running(fixture.resources))
        )
    }

    func testSuspendTransitionsAndRejections() {
        let fixture = Fixture()

        XCTAssertEqual(
            machine.advance(
                .running(fixture.resources),
                with: .suspendRequested(fixture.suspension)
            ),
            .changed(
                to: .suspending(fixture.suspension),
                effects: [
                    .releaseResources(policy: .suspend, idleTimerBaseline: false),
                    .stopTransport(fixture.transport),
                    .tearDownRuntimeServices,
                ]
            )
        )
        XCTAssertEqual(
            machine.advance(
                .resuming(fixture.resumeAttempt),
                with: .suspendRequested(nil)
            ),
            .changed(
                to: .resuming(fixture.resumeAttempt),
                effects: [.cancelResume(fixture.resumeAttempt)]
            )
        )
        XCTAssertEqual(
            machine.advance(
                .suspending(fixture.suspension),
                with: .suspendFinished(fixture.suspension.id)
            ),
            .changed(to: .suspended(fixture.suspendedRuntime))
        )
        XCTAssertEqual(
            machine.advance(
                .running(fixture.resources),
                with: .suspendRequested(nil)
            ),
            .rejected(.notRunning, stayingIn: .running(fixture.resources))
        )
        XCTAssertEqual(
            machine.advance(.stopped, with: .suspendRequested(fixture.suspension)),
            .rejected(.notRunning, stayingIn: .stopped)
        )
        XCTAssertEqual(
            machine.advance(
                .suspending(fixture.suspension),
                with: .suspendFinished(fixture.otherID)
            ),
            .rejected(.staleSuspendAttempt, stayingIn: .suspending(fixture.suspension))
        )
    }

    func testResumeTransitionsAndRejections() {
        let fixture = Fixture()

        XCTAssertEqual(
            machine.advance(
                .suspended(fixture.suspendedRuntime),
                with: .resumeRequested(fixture.resumeAttempt)
            ),
            .changed(to: .resuming(fixture.resumeAttempt))
        )
        XCTAssertEqual(
            machine.advance(
                .resuming(fixture.resumeAttempt),
                with: .resumeTransportRequested(fixture.resumeRequest)
            ),
            .changed(
                to: .resuming(fixture.resumeAttempt),
                effects: [.startTransport(fixture.resumeRequest)]
            )
        )
        XCTAssertEqual(
            machine.advance(
                .resuming(fixture.resumeAttempt),
                with: .resumeSucceeded(fixture.id, fixture.resources)
            ),
            .changed(
                to: .running(fixture.resources),
                effects: [.activateRuntime(fixture.resources)]
            )
        )
        XCTAssertEqual(
            machine.advance(
                .resuming(fixture.resumeAttempt),
                with: .resumeFailed(fixture.id)
            ),
            .changed(to: .suspended(fixture.suspendedRuntime))
        )
        XCTAssertEqual(
            machine.advance(
                .resuming(fixture.resumeAttempt),
                with: .resumeRequested(fixture.resumeAttempt)
            ),
            .rejected(.alreadyActive, stayingIn: .resuming(fixture.resumeAttempt))
        )
        XCTAssertEqual(
            machine.advance(.stopped, with: .resumeRequested(fixture.resumeAttempt)),
            .rejected(.notSuspended, stayingIn: .stopped)
        )

        let staleRequest = TheInsideJob.InsideJobTransportStartRequest(
            id: fixture.otherID,
            phase: .resume,
            transport: fixture.transport,
            idleTimerBaseline: false
        )
        XCTAssertEqual(
            machine.advance(
                .resuming(fixture.resumeAttempt),
                with: .resumeTransportRequested(staleRequest)
            ),
            .rejected(.staleResumeAttempt, stayingIn: .resuming(fixture.resumeAttempt))
        )
        XCTAssertEqual(
            machine.advance(
                .resuming(fixture.resumeAttempt),
                with: .resumeSucceeded(fixture.otherID, fixture.resources)
            ),
            .rejected(.staleResumeAttempt, stayingIn: .resuming(fixture.resumeAttempt))
        )
        XCTAssertEqual(
            machine.advance(
                .resuming(fixture.resumeAttempt),
                with: .resumeFailed(fixture.otherID)
            ),
            .rejected(.staleResumeAttempt, stayingIn: .resuming(fixture.resumeAttempt))
        )
    }

}

private struct Fixture {
    let id: UUID
    let otherID: UUID
    let transport: ServerTransport
    let resources: TheInsideJob.InsideJobRuntimeResources
    let startAttempt: TheInsideJob.InsideJobStartAttempt
    let suspension: TheInsideJob.InsideJobSuspension
    let suspendedRuntime: TheInsideJob.InsideJobSuspendedRuntime
    let resumeAttempt: TheInsideJob.InsideJobResumeAttempt
    let stopAttempt: TheInsideJob.InsideJobStopAttempt
    let resumeRequest: TheInsideJob.InsideJobTransportStartRequest

    @MainActor
    init() {
        let id = UUID()
        let transport = ServerTransport()
        let resources = TheInsideJob.InsideJobRuntimeResources(
            transport: transport,
            actualPort: 2468,
            bonjourServiceName: "Fixture",
            idleTimerBaseline: false
        )
        let suspendedRuntime = TheInsideJob.InsideJobSuspendedRuntime(idleTimerBaseline: false)

        self.id = id
        self.otherID = UUID()
        self.transport = transport
        self.resources = resources
        self.startAttempt = TheInsideJob.InsideJobStartAttempt(id: id, transport: transport)
        self.suspension = TheInsideJob.InsideJobSuspension(id: id, resources: resources)
        self.suspendedRuntime = suspendedRuntime
        self.resumeAttempt = TheInsideJob.InsideJobResumeAttempt(
            id: id,
            suspendedRuntime: suspendedRuntime,
            task: Task { @MainActor in }
        )
        self.stopAttempt = TheInsideJob.InsideJobStopAttempt(id: id)
        self.resumeRequest = TheInsideJob.InsideJobTransportStartRequest(
            id: id,
            phase: .resume,
            transport: transport,
            idleTimerBaseline: false
        )
    }
}
#endif
