import XCTest
import TheScore

final class ActionResultFailureWireTests: XCTestCase {
    func testActionResultRejectsSuccessWithFailureKind() throws {
        let json = """
        {"outcome":{"kind":"success","failureKind":"actionFailed"},"method":"activate"}
        """

        XCTAssertThrowsError(try JSONDecoder().decode(ActionResult.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("successful ActionResult outcome must not include failureKind"), "\(error)")
        }
    }

    func testActionResultWithFailureKind() throws {
        let result = ActionResult.failure(
            payload: .oneFingerTap,
            failureKind: .elementNotFound,
            message: "Element not found",
        )
        let message = ServerMessage.actionResult(result)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)

        if case .actionResult(let decodedResult) = decoded {
            XCTAssertFalse(decodedResult.outcome.isSuccess)
            XCTAssertEqual(decodedResult.outcome.failureKind, .elementNotFound)
            XCTAssertEqual(decodedResult.message, "Element not found")
        } else {
            XCTFail("Expected actionResult, got \(decoded)")
        }
    }

    func testActionFailureKindAllCasesRoundTrip() throws {
        for kind in ActionFailure.Kind.allCases {
            let result = ActionResult.failure(payload: .oneFingerTap, failureKind: kind)
            let data = try JSONEncoder().encode(result)
            let decoded = try JSONDecoder().decode(ActionResult.self, from: data)
            XCTAssertEqual(decoded.outcome.failureKind, kind, "Round-trip failed for \(kind)")
        }
    }

    func testActionResultRejectsFailureWithoutFailureKind() throws {
        let json = """
        {"type":"actionResult","payload":{"outcome":{"kind":"failure"},"method":"oneFingerTap","message":"fail"}}
        """

        XCTAssertThrowsError(try JSONDecoder().decode(ServerMessage.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("failed ActionResult outcome requires failureKind"), "\(error)")
        }
    }
}
