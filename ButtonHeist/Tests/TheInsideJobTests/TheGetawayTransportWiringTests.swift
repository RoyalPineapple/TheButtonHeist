#if canImport(UIKit)
import ButtonHeistSupport
import XCTest
import TheScore
@testable import TheInsideJob

@MainActor
final class TheGetawayTransportWiringTests: XCTestCase {

    func testTearDownDuringTransportWiringPreventsStaleConsumerCommit() async {
        let muscle = TheMuscle(sessionToken: "transport-wiring-token", sessionReleaseTimeout: 1)
        let brains = TheBrains(tripwire: TheTripwire())
        let getaway = TheGetaway(
            muscle: muscle,
            brains: brains,
            identity: .init(
                launchId: "transport-wiring-launch",
                effectiveInstanceId: "transport-wiring-instance",
                tlsActive: false
            )
        )
        let transport = ServerTransport(token: "transport-wiring-token")
        let enteredInstallation = CompletionSignal()
        let releaseInstallation = CompletionSignal()
        getaway.pauseBeforeTransportCallbackInstallationForTesting = {
            enteredInstallation.finish()
            await releaseInstallation.wait()
        }

        let wiringTask = Task { @MainActor in
            await getaway.wireTransport(transport) { _ in }
        }
        await enteredInstallation.wait()

        await getaway.tearDown()
        releaseInstallation.finish()
        await wiringTask.value

        guard case .unwired = getaway.transportWiring else {
            return XCTFail("Expected teardown to reject stale transport wiring, got \(getaway.transportWiring)")
        }
        XCTAssertNil(getaway.transport)
        await muscle.tearDown()
    }
}
#endif // canImport(UIKit)
