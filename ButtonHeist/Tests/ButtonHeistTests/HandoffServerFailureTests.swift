import XCTest
@_spi(ButtonHeistTooling) @testable import ButtonHeist
import TheScore

final class HandoffServerFailureTests: XCTestCase {
    @ButtonHeistActor
    func testUnsolicitedServerFailuresPreservePayloadAndClassification() async {
        let cases: [(ServerError, KnownFailureCode, FailurePhase, Bool)] = [
            (
                ServerError(
                    kind: .validationError,
                    message: "Invalid selector",
                    recoveryHint: "Refresh the interface and retry with a valid selector."
                ),
                .requestValidationError,
                .request,
                false
            ),
            (
                ServerError(kind: .general, message: "Rate limited: max 30 messages per second"),
                .serverGeneral,
                .server,
                false
            ),
            (
                ServerError(
                    kind: .general,
                    message: "Connection rejected by server",
                    recoveryHint: "Reconnect to the advertised endpoint."
                ),
                .serverGeneral,
                .server,
                false
            ),
        ]

        for (serverError, failureCode, phase, retryable) in cases {
            let handoff = TheHandoff()
            let connection = connectPendingMockHandoff(handoff)

            handoff.handleServerMessage(.error(serverError), requestId: nil)

            let expected = HandoffConnectionError.serverFailure(serverError)
            assertFailed(handoff.connectionPhase, failure: expected)
            XCTAssertEqual(handoff.connectionDiagnosticFailure, expected)
            XCTAssertEqual(expected.failureCode, failureCode.rawValue)
            XCTAssertEqual(expected.phase, phase)
            XCTAssertEqual(expected.retryable, retryable)
            XCTAssertEqual(expected.hint, serverError.recoveryHint?.description ?? failureCode.defaultHint)
            let publicError = FenceError(expected)
            XCTAssertEqual(publicError.errorCode, failureCode.rawValue)
            XCTAssertEqual(publicError.phase, phase)
            XCTAssertEqual(publicError.retryable, retryable)
            XCTAssertEqual(publicError.hint, serverError.recoveryHint?.description ?? failureCode.defaultHint)
            XCTAssertEqual(connection.disconnectCount, 1)
        }
    }

    @ButtonHeistActor
    func testAdmissionFailuresKeepAuthAndSessionClassification() async {
        let authError = ServerError(
            kind: .authFailure,
            message: "Too many failed attempts. Try again later.",
            recoveryHint: "Wait before authenticating again."
        )
        let authHandoff = TheHandoff()
        let authConnection = connectPendingMockHandoff(authHandoff)

        authHandoff.handleServerMessage(.error(authError), requestId: nil)

        let expectedAuth = HandoffConnectionError.disconnected(.authFailed(
            authError.message.description,
            hint: authError.recoveryHint?.description
        ))
        assertFailed(authHandoff.connectionPhase, failure: expectedAuth)
        XCTAssertEqual(expectedAuth.failureCode, KnownFailureCode.authFailed.rawValue)
        XCTAssertEqual(expectedAuth.phase, .authentication)
        XCTAssertFalse(expectedAuth.retryable)
        XCTAssertEqual(expectedAuth.hint, authError.recoveryHint?.description)
        XCTAssertEqual(authConnection.disconnectCount, 1)

        let session = SessionLockedPayload(message: "Session owned by another driver", activeConnections: 1)
        let sessionHandoff = TheHandoff()
        let sessionConnection = connectPendingMockHandoff(sessionHandoff)

        sessionHandoff.handleServerMessage(.sessionLocked(session), requestId: nil)

        let expectedSession = HandoffConnectionError.disconnected(.sessionLocked(session.message))
        assertFailed(sessionHandoff.connectionPhase, failure: expectedSession)
        XCTAssertEqual(expectedSession.failureCode, KnownFailureCode.sessionLocked.rawValue)
        XCTAssertEqual(expectedSession.phase, .session)
        XCTAssertTrue(expectedSession.retryable)
        XCTAssertEqual(sessionConnection.disconnectCount, 1)
    }
}
