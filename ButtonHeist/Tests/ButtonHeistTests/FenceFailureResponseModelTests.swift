import XCTest
@testable import ButtonHeist
import TheScore

final class FenceFailureResponseModelTests: XCTestCase {

    // MARK: - Diagnostic Failure

    func testDiagnosticFailureIsPublicFailureBoundaryValue() {
        let details = FailureDetails(
            errorCode: "request.validation_error",
            phase: .request,
            retryable: false,
            hint: "Fix the request."
        )

        let diagnostic = DiagnosticFailure(message: "Invalid request", details: details)
        let publicFailure: PublicFailure = diagnostic

        XCTAssertEqual(publicFailure.code, "request.validation_error")
        XCTAssertEqual(publicFailure.kind, .request)
        XCTAssertEqual(publicFailure.message, "Invalid request")
        XCTAssertEqual(publicFailure.displayMessage, "Invalid request")
        XCTAssertEqual(publicFailure.details, details)
        XCTAssertEqual(publicFailure.phase, .request)
        XCTAssertEqual(publicFailure.retryable, false)
        XCTAssertEqual(publicFailure.hint, "Fix the request.")
    }

    func testTypedErrorConstructorPreservesLegacyJSONShape() throws {
        let details = FailureDetails(
            errorCode: "request.invalid",
            phase: .request,
            retryable: false,
            hint: "Fix the request shape or arguments before retrying."
        )
        let failure = PublicFailure(message: "schema validation failed", details: details)

        let typed = FenceResponse.error(failure)
        let legacy = FenceResponse.error(failure.message, details: details)

        XCTAssertEqual(try typed.jsonData(), try legacy.jsonData())

        let json = publicJSONObject(typed)
        XCTAssertEqual(json["status"] as? String, "error")
        XCTAssertEqual(json["message"] as? String, failure.displayMessage)
        XCTAssertEqual(json["code"] as? String, failure.code)
        XCTAssertEqual(json["kind"] as? String, failure.kind.rawValue)
        XCTAssertEqual(json["errorCode"] as? String, failure.code)
        XCTAssertEqual(json["phase"] as? String, failure.phase.rawValue)
        XCTAssertEqual(json["retryable"] as? Bool, failure.retryable)
        XCTAssertEqual(json["hint"] as? String, failure.hint)

        let detailsJSON = try XCTUnwrap(json["details"] as? [String: Any])
        XCTAssertEqual(detailsJSON["code"] as? String, failure.code)
        XCTAssertEqual(detailsJSON["kind"] as? String, failure.kind.rawValue)
        XCTAssertEqual(detailsJSON["phase"] as? String, failure.phase.rawValue)
        XCTAssertEqual(detailsJSON["retryable"] as? Bool, failure.retryable)
        XCTAssertEqual(detailsJSON["hint"] as? String, failure.hint)
    }

    func testKnownFailuresExposeCompleteDiagnosticFields() throws {
        let validationError = SchemaValidationError(
            field: "target",
            observed: "string",
            expected: "object"
        )
        let cases: [ExpectedDiagnosticFailure] = [
            ExpectedDiagnosticFailure(
                name: "server",
                response: FenceResponse.failure(FenceError.serverError(ServerError(
                    kind: .general,
                    message: "server crashed"
                ))),
                code: "server.general",
                kind: .server,
                phase: .server,
                message: "Action failed: server crashed",
                retryable: false
            ),
            ExpectedDiagnosticFailure(
                name: "routing",
                response: FenceResponse.failure(FenceOperationRoutingError(message: "Unknown tool: warp")),
                code: "request.invalid",
                kind: .request,
                phase: .request,
                message: "Unknown tool: warp",
                retryable: false
            ),
            ExpectedDiagnosticFailure(
                name: "validation",
                response: FenceResponse.failure(validationError),
                code: "request.invalid",
                kind: .request,
                phase: .request,
                message: validationError.message,
                retryable: false
            ),
            ExpectedDiagnosticFailure(
                name: "action",
                response: FenceResponse.failure(FenceError.actionFailed("could not activate target")),
                code: "request.action_failed",
                kind: .request,
                phase: .request,
                message: "Action failed: could not activate target",
                retryable: false
            ),
        ]

        for expected in cases {
            let failure = try XCTUnwrap(expected.response.publicFailure, expected.name)
            XCTAssertEqual(failure.code, expected.code, expected.name)
            XCTAssertEqual(failure.kind, expected.kind, expected.name)
            XCTAssertEqual(failure.phase, expected.phase, expected.name)
            XCTAssertEqual(failure.message, expected.message, expected.name)
            XCTAssertEqual(failure.displayMessage, expected.message, expected.name)
            XCTAssertEqual(failure.retryable, expected.retryable, expected.name)
            XCTAssertEqual(failure.details.errorCode, expected.code, expected.name)
            XCTAssertEqual(failure.details.phase, expected.phase, expected.name)
            XCTAssertEqual(failure.details.retryable, expected.retryable, expected.name)
            XCTAssertFalse(failure.code.isEmpty, expected.name)
            XCTAssertFalse(failure.kind.rawValue.isEmpty, expected.name)
            XCTAssertFalse(failure.message.isEmpty, expected.name)
        }
    }

}

private struct ExpectedDiagnosticFailure {
    let name: String
    let response: FenceResponse
    let code: String
    let kind: PublicFailureKind
    let phase: FailurePhase
    let message: String
    let retryable: Bool
}
