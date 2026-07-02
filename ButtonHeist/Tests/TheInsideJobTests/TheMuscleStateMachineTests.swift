import ButtonHeistTestSupport
import XCTest
import Network

@testable import TheInsideJob

final class TheMuscleStateMachineTests: XCTestCase {
    func testSessionAdmissionLocksAddressAfterConfiguredFailures() {
        var admission = SessionAdmission(
            tokenSource: .configured("good-token"),
            maxFailedAttempts: 2,
            lockoutDuration: 30
        )

        guard case .rejected(.invalidToken(let firstError, let firstAttempts)) = admission.decideToken(
            "bad-token",
            driverId: nil,
            address: "127.0.0.1"
        ) else {
            return XCTFail("Expected the first bad token to be rejected")
        }
        XCTAssertEqual(firstError.message, "Invalid token. Retry with the configured token.")
        XCTAssertEqual(firstError.recoveryHint, "Retry with the configured token.")
        XCTAssertEqual(firstAttempts, 1)

        guard case .rejected(.lockoutStarted(let secondError, let secondAttempts)) = admission.decideToken(
            "bad-token",
            driverId: nil,
            address: "127.0.0.1"
        ) else {
            return XCTFail("Expected the second bad token to be rejected")
        }
        XCTAssertEqual(secondError.recoveryHint, "Retry with the configured token.")
        XCTAssertEqual(secondAttempts, 2)

        guard case .lockedOut(let error) = admission.decideToken(
            "good-token",
            driverId: nil,
            address: "127.0.0.1"
        ) else {
            return XCTFail("Expected the locked-out address to stay locked out")
        }
        XCTAssertEqual(error.message, "Too many failed attempts. Try again later.")
    }

    func testClientAuthenticationRejectsAuthenticationBeforeHello() {
        var registry = TheMuscleClientRegistry()
        registry.registerAddress(1, address: "127.0.0.1")

        XCTAssertEqual(
            registry.completeAuthentication(1),
            .rejected(.missingHello, state: .connected(address: "127.0.0.1"))
        )
        XCTAssertEqual(registry.phase(for: 1), .connected(address: "127.0.0.1"))
    }

    func testClientAuthenticationAdvancesThroughHelloBeforeAuthenticated() {
        var registry = TheMuscleClientRegistry()
        registry.registerAddress(1, address: "127.0.0.1")

        XCTAssertEqual(
            registry.validateHello(1),
            .advanced(.helloValidated(address: "127.0.0.1"), effect: .helloValidated)
        )
        XCTAssertEqual(
            registry.completeAuthentication(1),
            .advanced(.authenticated(address: "127.0.0.1"), effect: .authenticated)
        )
        XCTAssertEqual(registry.phase(for: 1), .authenticated(address: "127.0.0.1"))
    }

    func testClientAuthenticationRejectsDuplicateHelloAfterValidation() {
        var registry = TheMuscleClientRegistry()
        registry.registerAddress(1, address: "127.0.0.1")

        _ = registry.validateHello(1)

        XCTAssertEqual(
            registry.validateHello(1),
            .rejected(.helloAlreadyValidated, state: .helloValidated(address: "127.0.0.1"))
        )
        XCTAssertEqual(registry.phase(for: 1), .helloValidated(address: "127.0.0.1"))
    }

    func testSessionLeaseDrainingRejectionUsesOneStructuredDiagnostic() {
        var lease = SessionLease(releaseTimeout: 30)
        let now = Date(timeIntervalSinceReferenceDate: 1_000)

        guard case .accepted(.claimedSession) = lease.acquire(
            driverIdentity: "driver:alpha",
            clientId: 1,
            at: now
        ) else {
            return XCTFail("Expected first driver to claim the session")
        }

        guard case .draining(let releaseDeadline) = lease.removeConnection(1, at: now) else {
            return XCTFail("Expected final connection removal to start draining")
        }
        XCTAssertEqual(releaseDeadline, now.addingTimeInterval(30))

        guard case .rejected(let diagnostic) = lease.acquire(
            driverIdentity: "driver:beta",
            clientId: 2,
            at: now.addingTimeInterval(12)
        ) else {
            return XCTFail("Expected different driver to be rejected while draining")
        }
        guard case .drainingOwner(
            owner: .exposed("alpha"),
            remainingTimeoutSeconds: let remainingTimeoutSeconds
        ) = diagnostic else {
            return XCTFail("Expected draining lock diagnostic, got \(diagnostic)")
        }
        XCTAssertEqual(remainingTimeoutSeconds, 18)

        let payload = diagnostic.payload()
        XCTAssertEqual(payload.activeConnections, 0)
        XCTAssertTrue(payload.message.contains("Session is locked by another driver"))
        XCTAssertTrue(payload.message.contains("owner driver id: alpha"))
        XCTAssertTrue(payload.message.contains("active connections: 0"))
        XCTAssertTrue(payload.message.contains("remaining timeout:"))
    }

    func testSessionLeaseActiveRejectionUsesTypedDiagnosticWithoutDrainingTimeout() {
        var lease = SessionLease(releaseTimeout: 30)
        let now = Date(timeIntervalSinceReferenceDate: 1_000)

        guard case .accepted(.claimedSession) = lease.acquire(
            driverIdentity: "driver:alpha",
            clientId: 1,
            at: now
        ) else {
            return XCTFail("Expected first driver to claim the session")
        }

        guard case .rejected(let sameDriverDiagnostic) = lease.acquire(
            driverIdentity: "driver:alpha",
            clientId: 2,
            at: now
        ) else {
            return XCTFail("Expected same driver to be rejected while already active")
        }
        guard case .sameDriverActive(owner: .exposed("alpha")) = sameDriverDiagnostic else {
            return XCTFail("Expected same-driver active diagnostic, got \(sameDriverDiagnostic)")
        }
        XCTAssertEqual(sameDriverDiagnostic.payload().activeConnections, 1)
        XCTAssertFalse(sameDriverDiagnostic.payload().message.contains("remaining timeout:"))

        guard case .rejected(let activeOwnerDiagnostic) = lease.acquire(
            driverIdentity: "driver:beta",
            clientId: 3,
            at: now
        ) else {
            return XCTFail("Expected different driver to be rejected while active")
        }
        guard case .activeOwner(owner: .exposed("alpha")) = activeOwnerDiagnostic else {
            return XCTFail("Expected active-owner diagnostic, got \(activeOwnerDiagnostic)")
        }
        XCTAssertEqual(activeOwnerDiagnostic.payload().activeConnections, 1)
        XCTAssertFalse(activeOwnerDiagnostic.payload().message.contains("remaining timeout:"))
    }

    func testSessionLeaseIgnoresNonActiveConnectionRemoval() {
        var lease = SessionLease(releaseTimeout: 30)
        let now = Date(timeIntervalSinceReferenceDate: 1_000)

        guard case .accepted = lease.acquire(driverIdentity: "driver:alpha", clientId: 1, at: now) else {
            return XCTFail("Expected first driver to claim the session")
        }

        guard case .active = lease.removeConnection(2, at: now) else {
            return XCTFail("Disconnecting a non-session client must not request a release timer")
        }
        XCTAssertEqual(lease.activeSessionConnections, [1])

        guard case .draining = lease.removeConnection(1, at: now) else {
            return XCTFail("Expected active session connection removal to start draining")
        }
    }

    func testSessionLeaseRejoinsDuringGracePeriod() {
        var lease = SessionLease(releaseTimeout: 30)
        let now = Date(timeIntervalSinceReferenceDate: 1_000)

        guard case .accepted(.claimedSession) = lease.acquire(
            driverIdentity: "driver:alpha",
            clientId: 1,
            at: now
        ) else {
            return XCTFail("Expected first driver to claim the session")
        }
        guard case .draining = lease.removeConnection(1, at: now) else {
            return XCTFail("Expected final connection removal to start draining")
        }

        guard case .accepted(.rejoinedDuringGracePeriod) = lease.acquire(
            driverIdentity: "driver:alpha",
            clientId: 2,
            at: now.addingTimeInterval(5)
        ) else {
            return XCTFail("Expected active driver to rejoin during the grace period")
        }
        XCTAssertEqual(lease.activeSessionDriverId, "driver:alpha")
        XCTAssertEqual(lease.exposedActiveDriverId, "alpha")
        XCTAssertEqual(lease.activeSessionConnections, [2])
    }

    func testSessionLeaseReleaseReportsIdleAndActiveOutcomes() {
        var lease = SessionLease(releaseTimeout: 30)
        let now = Date(timeIntervalSinceReferenceDate: 1_000)

        XCTAssertEqual(lease.release(), .noActiveSession)

        guard case .accepted(.claimedSession) = lease.acquire(
            driverIdentity: "driver:alpha",
            clientId: 1,
            at: now
        ) else {
            return XCTFail("Expected first driver to claim the session")
        }

        XCTAssertEqual(lease.release(), .releasedSession)
        XCTAssertNil(lease.activeSessionDriverId)
        XCTAssertEqual(lease.activeSessionConnections, [])
        XCTAssertEqual(lease.release(), .noActiveSession)
    }

    #if canImport(UIKit)
    func testMuscleSessionMutationsReturnTypedEffects() {
        var session = TheMuscleSession(releaseTimeout: 30)
        let now = Date(timeIntervalSinceReferenceDate: 1_000)

        guard case .accepted(let claimEffect) = session.acquire(
            driverIdentity: "driver:alpha",
            clientId: 1,
            at: now
        ) else {
            return XCTFail("Expected first driver to claim the session")
        }
        XCTAssertEqual(
            claimEffect,
            [.log(.sessionClaimed(clientId: 1))]
        )

        XCTAssertEqual(
            session.removeConnection(1, at: now),
            [
                .replaceReleaseTimer(timeout: 30),
                .log(.releaseTimerStarted(timeout: 30)),
            ]
        )

        guard case .accepted(let rejoinEffect) = session.acquire(
            driverIdentity: "driver:alpha",
            clientId: 2,
            at: now.addingTimeInterval(1)
        ) else {
            return XCTFail("Expected active driver to rejoin during the grace period")
        }
        XCTAssertEqual(
            rejoinEffect,
            [
                .cancelReleaseTimer,
                .log(.clientRejoinedDuringGracePeriod(clientId: 2)),
            ]
        )

        XCTAssertEqual(
            session.release(),
            [
                .cancelReleaseTimer,
                .log(.sessionReleased),
            ]
        )
        XCTAssertEqual(
            session.release(),
            [.cancelReleaseTimer]
        )
    }
    #endif

    func testClientDeliveryReportsUnwiredFailuresAsTypedOutcomes() async {
        let delivery = ClientDelivery.unwired

        let sendOutcome = await delivery.send(Data("hello".utf8), toClient: 1)
        guard case .failed(.transportUnavailable) = sendOutcome else {
            return XCTFail("Expected missing transport to be a typed send failure, got \(sendOutcome)")
        }

        let callbackOutcome = await delivery.disconnect(1)
        XCTAssertEqual(callbackOutcome, .failed(.callbacksNotInstalled("disconnectClient")))
    }

    func testServerTransportFailurePreservesNetworkDiagnosticReason() {
        let diagnostic = ServerTransportFailure(.posix(.ECONNRESET))
        let failure = ServerSendFailure.transportFailed(clientId: 12, diagnostic: diagnostic)

        guard case .transportFailed(let clientId, let capturedDiagnostic) = failure else {
            return XCTFail("Expected typed transport failure, got \(failure)")
        }
        XCTAssertEqual(clientId, 12)
        XCTAssertEqual(capturedDiagnostic.reason, .posix(code: Int(POSIXErrorCode.ECONNRESET.rawValue)))
        XCTAssertTrue(capturedDiagnostic.description.contains("posix"))
        XCTAssertTrue(failure.localizedDescription.contains("posix"))
    }

}
