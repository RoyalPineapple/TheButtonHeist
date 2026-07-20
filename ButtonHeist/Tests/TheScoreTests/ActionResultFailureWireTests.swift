import XCTest
import TheScore

final class ActionResultFailureWireTests: XCTestCase {
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
}
