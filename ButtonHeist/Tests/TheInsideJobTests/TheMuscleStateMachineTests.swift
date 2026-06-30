import ButtonHeistTestSupport
import XCTest
import Network

@testable import TheInsideJob

final class TheMuscleStateMachineTests: XCTestCase {
    private let sourceRepository = SourceShapeRepository(filePath: #filePath)

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

    func testSessionLeaseDrainingRejectionUsesOneStructuredDiagnostic() {
        var lease = SessionLease(releaseTimeout: 30)

        guard case .accepted(.claimedSession) = lease.acquire(driverIdentity: "driver:alpha", clientId: 1) else {
            return XCTFail("Expected first driver to claim the session")
        }

        guard case .draining = lease.removeConnection(1) else {
            return XCTFail("Expected final connection removal to start draining")
        }

        guard case .rejected(let diagnostic) = lease.acquire(driverIdentity: "driver:beta", clientId: 2) else {
            return XCTFail("Expected different driver to be rejected while draining")
        }

        let payload = diagnostic.payload()
        XCTAssertEqual(payload.activeConnections, 0)
        XCTAssertTrue(payload.message.contains("Session is locked by another driver"))
        XCTAssertTrue(payload.message.contains("owner driver id: alpha"))
        XCTAssertTrue(payload.message.contains("active connections: 0"))
        XCTAssertTrue(payload.message.contains("remaining timeout:"))
    }

    func testSessionLeaseIgnoresNonActiveConnectionRemoval() {
        var lease = SessionLease(releaseTimeout: 30)

        guard case .accepted = lease.acquire(driverIdentity: "driver:alpha", clientId: 1) else {
            return XCTFail("Expected first driver to claim the session")
        }

        guard case .active = lease.removeConnection(2) else {
            return XCTFail("Disconnecting a non-session client must not request a release timer")
        }
        XCTAssertEqual(lease.activeSessionConnections, [1])

        guard case .draining = lease.removeConnection(1) else {
            return XCTFail("Expected active session connection removal to start draining")
        }
    }

    #if canImport(UIKit)
    func testMuscleSessionMutationsReturnTypedEffects() {
        var session = TheMuscleSession(releaseTimeout: 30)

        guard case .accepted(let claimEffect) = session.acquire(
            driverIdentity: "driver:alpha",
            clientId: 1
        ) else {
            return XCTFail("Expected first driver to claim the session")
        }
        XCTAssertEqual(
            claimEffect,
            TheMuscleSession.Effect(logEvents: [.sessionClaimed(clientId: 1)])
        )

        XCTAssertEqual(
            session.removeConnection(1),
            TheMuscleSession.Effect(
                releaseTimerAction: .replace(timeout: 30),
                logEvents: [.releaseTimerStarted(timeout: 30)]
            )
        )

        guard case .accepted(let rejoinEffect) = session.acquire(
            driverIdentity: "driver:alpha",
            clientId: 2
        ) else {
            return XCTFail("Expected active driver to rejoin during the grace period")
        }
        XCTAssertEqual(
            rejoinEffect,
            TheMuscleSession.Effect(
                releaseTimerAction: .cancel,
                logEvents: [.clientRejoinedDuringGracePeriod(clientId: 2)]
            )
        )

        XCTAssertEqual(
            session.release(),
            TheMuscleSession.Effect(releaseTimerAction: .cancel, logEvents: [.sessionReleased])
        )
        XCTAssertEqual(
            session.release(),
            TheMuscleSession.Effect(releaseTimerAction: .cancel)
        )
    }
    #endif

    func testMuscleSessionReducerSourceReturnsEffectsInsteadOfLogging() throws {
        let sessionSource = try sourceRepository.requiredFile(
            relativePath: "ButtonHeist/Sources/TheInsideJob/Server/TheMuscleSession.swift"
        )
        let muscleSource = try sourceRepository.requiredFile(
            relativePath: "ButtonHeist/Sources/TheInsideJob/Server/TheMuscle.swift"
        )

        let reducerLogLines = try sessionSource.lines(
            matching: #"\b(ButtonHeistLog|Logger|sessionLogger|logger)\b|[.]info\s*\("#
        )
        XCTAssertTrue(
            reducerLogLines.isEmpty,
            """
            TheMuscleSession mutations should return typed effects instead of logging:
            \(reducerLogLines.joined(separator: "\n"))
            """
        )

        XCTAssertTrue(try sessionSource.containsMatch(#"\benum\s+LogEvent\b"#))
        XCTAssertTrue(sessionSource.contents.contains("case sessionClaimed(clientId: Int)"))
        XCTAssertTrue(sessionSource.contents.contains("case clientRejoinedDuringGracePeriod(clientId: Int)"))
        XCTAssertTrue(sessionSource.contents.contains("case sessionReleased"))
        XCTAssertTrue(sessionSource.contents.contains("case releaseTimerStarted(timeout: TimeInterval)"))
        XCTAssertTrue(try sessionSource.containsMatch(#"\bstruct\s+Effect\b"#))
        XCTAssertTrue(try sessionSource.containsMatch(#"\breleaseTimerAction\s*:\s*ReleaseTimerAction\b"#))
        XCTAssertTrue(try sessionSource.containsMatch(#"\blogEvents\s*:\s*\[LogEvent\]"#))

        XCTAssertTrue(try muscleSource.containsMatch(#"\bfunc\s+applySessionEffect\s*\("#))
        XCTAssertTrue(try muscleSource.containsMatch(#"\bfunc\s+logSessionEvent\s*\("#))
        XCTAssertTrue(muscleSource.contents.contains("muscleLogger.info(\"Session claimed by client"))
        XCTAssertTrue(muscleSource.contents.contains("muscleLogger.info(\"Session released"))
        XCTAssertTrue(muscleSource.contents.contains("muscleLogger.info(\"All session connections gone"))
    }

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
