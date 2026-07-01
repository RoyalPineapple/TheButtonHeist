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
        XCTAssertTrue(try sessionSource.containsMatch(#"\benum\s+Effect\b"#))
        XCTAssertTrue(sessionSource.contents.contains("case log(LogEvent)"))
        XCTAssertTrue(sessionSource.contents.contains("case cancelReleaseTimer"))
        XCTAssertTrue(sessionSource.contents.contains("case replaceReleaseTimer(timeout: TimeInterval)"))
        XCTAssertFalse(try sessionSource.containsMatch(#"\breleaseTimerAction\s*:"#))
        XCTAssertFalse(try sessionSource.containsMatch(#"\blogEvents\s*:\s*\[LogEvent\]"#))
        XCTAssertFalse(try sessionSource.containsMatch(#"\bDate\s*\(\s*\)"#))

        XCTAssertTrue(try muscleSource.containsMatch(#"\bfunc\s+applySessionEffects\s*\("#))
        XCTAssertTrue(try muscleSource.containsMatch(#"\bfunc\s+logSessionEvent\s*\("#))
        XCTAssertTrue(muscleSource.contents.contains("muscleLogger.info(\"Session claimed by client"))
        XCTAssertTrue(muscleSource.contents.contains("muscleLogger.info(\"Session released"))
        XCTAssertTrue(muscleSource.contents.contains("muscleLogger.info(\"All session connections gone"))
    }

    func testMuscleAdmissionAndSessionEffectsDoNotRegressToOptionalBags() throws {
        let admissionSource = try sourceRepository.requiredFile(
            relativePath: "ButtonHeist/Sources/TheInsideJob/Server/TheMuscleAdmission.swift"
        )
        let sessionSource = try sourceRepository.requiredFile(
            relativePath: "ButtonHeist/Sources/TheInsideJob/Server/TheMuscleSession.swift"
        )

        XCTAssertFalse(try admissionSource.containsMatch(#"\bdelayedDisconnectClientId\b"#))
        XCTAssertFalse(try admissionSource.containsMatch(#"\boutputs\s*:\s*\[MuscleAdmissionOutput\]"#))
        XCTAssertFalse(try admissionSource.containsMatch(#"\bstruct\s+MuscleAdmissionEffect\b"#))
        XCTAssertTrue(try admissionSource.containsMatch(#"\benum\s+MuscleAdmissionEffect\b"#))
        XCTAssertTrue(admissionSource.contents.contains("case delayedDisconnect(clientId: Int)"))
        XCTAssertFalse(try admissionSource.containsMatch(#"\bstatic\s+func\s+response\s*\("#))
        XCTAssertFalse(try admissionSource.containsMatch(#"\bstatic\s+func\s+client\s*\("#))
        XCTAssertFalse(try admissionSource.containsMatch(#"\bdisconnect\s+clientId\s*:\s*Int\?"#))
        XCTAssertFalse(try admissionSource.containsMatch(#"\bdisconnect\s*:\s*Bool\b"#))

        XCTAssertFalse(try sessionSource.containsMatch(#"\breleaseTimerAction\b"#))
        XCTAssertFalse(try sessionSource.containsMatch(#"\blogEvents\s*:\s*\[LogEvent\]"#))
        XCTAssertTrue(try sessionSource.containsMatch(#"\benum\s+Effect\b"#))
        XCTAssertFalse(try sessionSource.containsMatch(#"\bresetInactivityTimer\b"#))
    }

    func testSessionLeaseDiagnosticsDoNotRegressToOptionalBags() throws {
        let leaseSource = try sourceRepository.requiredFile(
            relativePath: "ButtonHeist/Sources/TheInsideJob/Server/SessionLease.swift"
        )

        XCTAssertTrue(try leaseSource.containsMatch(#"\benum\s+SessionLockDiagnostic\b"#))
        XCTAssertFalse(try leaseSource.containsMatch(#"\bstruct\s+SessionLockDiagnostic\b"#))
        XCTAssertTrue(leaseSource.contents.contains("case sameDriverActive(owner: OwnerDriverIdentity)"))
        XCTAssertTrue(leaseSource.contents.contains("case activeOwner(owner: OwnerDriverIdentity)"))
        XCTAssertTrue(leaseSource.contents.contains(
            "case drainingOwner(owner: OwnerDriverIdentity, remainingTimeoutSeconds: TimeInterval)"
        ))
        XCTAssertFalse(try leaseSource.containsMatch(#"\bownerDriverId\s*:\s*String\?"#))
        XCTAssertFalse(try leaseSource.containsMatch(#"\bremainingTimeoutSeconds\s*:\s*TimeInterval\?"#))
        XCTAssertFalse(try leaseSource.containsMatch(#"\bresetInactivityTimer\b"#))
        XCTAssertFalse(try leaseSource.containsMatch(#"->\s*Date\?"#))
        XCTAssertFalse(try leaseSource.containsMatch(#"\bDate\s*\(\s*\)"#))
        XCTAssertTrue(try leaseSource.containsMatch(#"\bfunc\s+acquire\s*\([^)]*\bat\s+now:\s*Date"#))
        XCTAssertTrue(try leaseSource.containsMatch(#"\bfunc\s+removeConnection\s*\([^)]*\bat\s+now:\s*Date"#))
        XCTAssertTrue(try leaseSource.containsMatch(#"\bstruct\s+Machine\s*:\s*SimpleStateMachine\b"#))
        XCTAssertTrue(try leaseSource.containsMatch(#"\benum\s+Event\b"#))
        XCTAssertTrue(try leaseSource.containsMatch(#"\benum\s+Effect\b"#))
        XCTAssertTrue(try leaseSource.containsMatch(#"\benum\s+Rejection\b"#))
        XCTAssertTrue(leaseSource.contents.contains("case acquire(driverIdentity: String, clientId: Int, at: Date)"))
        XCTAssertTrue(leaseSource.contents.contains("case removeConnection(clientId: Int, at: Date)"))
        XCTAssertTrue(leaseSource.contents.contains("case acquisition(AcquisitionEffect)"))
        XCTAssertTrue(leaseSource.contents.contains("case release(ReleaseEffect)"))
        XCTAssertTrue(leaseSource.contents.contains("case connectionRemoval(ConnectionRemoval)"))
        XCTAssertTrue(leaseSource.contents.contains("case acquisition(SessionLockDiagnostic)"))
        XCTAssertTrue(leaseSource.contents.contains("StateDriver<Machine>"))
        XCTAssertTrue(leaseSource.contents.contains("switch (state, event)"))
        XCTAssertTrue(leaseSource.contents.contains("releaseDeadline.timeIntervalSince(now)"))
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

    func testClientAuthenticationPhaseSourceShapeUsesStateMachine() throws {
        let stateSource = try sourceRepository.requiredFile(
            relativePath: "ButtonHeist/Sources/TheInsideJob/Server/ClientAuthenticationState.swift"
        )
        let registrySource = try sourceRepository.requiredFile(
            relativePath: "ButtonHeist/Sources/TheInsideJob/Server/ClientRegistry.swift"
        )
        let admissionSource = try sourceRepository.requiredFile(
            relativePath: "ButtonHeist/Sources/TheInsideJob/Server/SessionAdmission.swift"
        )

        XCTAssertTrue(try stateSource.containsMatch(#"\bstruct\s+ClientAuthenticationMachine\s*:\s*SimpleStateMachine\b"#))
        XCTAssertTrue(stateSource.contents.contains("case (.connected(let address), .validateHello)"))
        XCTAssertTrue(stateSource.contents.contains("case (.helloValidated(let address), .completeAuthentication)"))
        XCTAssertTrue(registrySource.contents.contains("StateDriver<ClientAuthenticationMachine>"))
        XCTAssertTrue(registrySource.contents.contains("validateHello(_ clientId: Int)"))
        XCTAssertTrue(registrySource.contents.contains("completeAuthentication(_ clientId: Int)"))
        XCTAssertFalse(registrySource.contents.contains("markHelloValidated"))

        let directLatePhaseWrites = try registrySource.lines(
            matching: #"clients\[[^]]+\]\s*=\s*[.](helloValidated|authenticated)\("#
        )
        XCTAssertTrue(
            directLatePhaseWrites.isEmpty,
            """
            Client authentication must not assign hello/authenticated phases outside the machine:
            \(directLatePhaseWrites.joined(separator: "\n"))
            """
        )

        XCTAssertTrue(try admissionSource.containsMatch(#"\bstruct\s+AddressAuthenticationFailureMachine\s*:\s*SimpleStateMachine\b"#))
        XCTAssertTrue(admissionSource.contents.contains("case clean"))
        XCTAssertTrue(admissionSource.contents.contains("case failing(attempts: Int)"))
        XCTAssertTrue(admissionSource.contents.contains("case lockedOut(until: Date, attempts: Int)"))
        XCTAssertFalse(try admissionSource.containsMatch(#"\bcase\s+nil\s*:\s*0\b"#))
    }
}
