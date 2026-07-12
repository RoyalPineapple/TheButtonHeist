import XCTest
@_spi(ButtonHeistTooling) @testable import ButtonHeist
@_spi(ButtonHeistInternals) import TheScore

final class GetInterfaceQueryInvariantTests: XCTestCase {

    @ButtonHeistActor
    func testGetInterfaceRejectsTopLevelChecks() async throws {
        let (fence, _) = makeConnectedFence()

        let response = try await fence.execute(command: .getInterface, values: [
            "checks": .array([Self.exactStringCheck(kind: "label", value: "Pay")]),
        ])

        guard case .error(let failure) = response else {
            return XCTFail("Expected .error response, got: \(response)")
        }
        XCTAssertTrue(
            failure.message.contains("expected valid get_interface parameter"),
            failure.message
        )
    }

    private static func exactStringCheck(kind: String, value: String) -> HeistValue {
        .object([
            "kind": .string(kind),
            "match": .object([
                "mode": .string("exact"),
                "value": .string(value),
            ]),
        ])
    }
}
