import XCTest
@_spi(ButtonHeistTooling) @testable import ButtonHeist
@_spi(ButtonHeistInternals) import TheScore

final class GetInterfaceQueryInvariantTests: XCTestCase {

    @ButtonHeistActor
    func testGetInterfaceRejectsSubtreeAndMatcherFields() async throws {
        let (fence, _) = makeConnectedFence()

        let response = try await fence.execute(command: .getInterface, values: [
            "subtree": .object([
                "element": .object([
                    "label": .object([
                        "mode": .string("exact"),
                        "value": .string("Save"),
                    ]),
                ]),
            ]),
            "label": .object([
                "mode": .string("exact"),
                "value": .string("Pay"),
            ]),
        ])

        guard case .error(let failure) = response else {
            return XCTFail("Expected .error response, got: \(response)")
        }
        XCTAssertTrue(
            failure.message.contains("use subtree or element matcher fields, not both"),
            failure.message
        )
    }
}
