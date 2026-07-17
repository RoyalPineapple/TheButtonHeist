import XCTest
import ThePlans
@_spi(ButtonHeistTooling) @testable import ButtonHeist
@_spi(ButtonHeistInternals) import TheScore

final class GesturePayloadDecodingTests: XCTestCase {

    func testGestureDescriptorScalarsUseFenceParameterDeclarations() throws {
        let tapUnitPoint = try XCTUnwrap(
            TheFence.Command.oneFingerTap.descriptor.parameters.first { $0.key == FenceParameterKey.unitPoint.rawValue }
        )
        XCTAssertEqual(tapUnitPoint.objectProperties, [
            FenceParameters.unitPointX.spec,
            FenceParameters.unitPointY.spec,
        ])

        let longPressDuration = try XCTUnwrap(
            TheFence.Command.longPress.descriptor.parameters.first { $0.key == FenceParameterKey.duration.rawValue }
        )
        XCTAssertEqual(longPressDuration, FenceParameters.gestureDuration.spec)
    }

    @ButtonHeistActor
    func testSwipeElementDirectionIntentDecodesPayload() async throws {
        let message = try await sentRuntimeMessage(
            command: .swipe,
            arguments: [
                "elementDirection": .object([
                    "element": targetValue(identifier: "row_5"),
                    "direction": .string("left"),
                ]),
            ]
        )

        guard case .mechanicalSwipe(let target) = message,
              case .elementDirection(let target, let direction) = target.selection else {
            return XCTFail("Expected elementDirection swipe payload, got \(message)")
        }
        XCTAssertEqual(target, .predicate(.identifier("row_5")))
        XCTAssertEqual(direction, .left)
    }

    @ButtonHeistActor
    func testSwipeElementUnitPointsIntentDecodesPayload() async throws {
        let message = try await sentRuntimeMessage(
            command: .swipe,
            arguments: [
                "elementUnitPoints": .object([
                    "element": targetValue(identifier: "row_5"),
                    "start": unitPointValue(x: 0.8, y: 0.5),
                    "end": unitPointValue(x: 0.2, y: 0.5),
                ]),
            ]
        )

        guard case .mechanicalSwipe(let target) = message,
              case .unitElement(let target, let start, let end) = target.selection else {
            return XCTFail("Expected elementUnitPoints swipe payload, got \(message)")
        }
        XCTAssertEqual(target, .predicate(.identifier("row_5")))
        XCTAssertEqual(start, UnitPoint(x: 0.8, y: 0.5))
        XCTAssertEqual(end, UnitPoint(x: 0.2, y: 0.5))
    }

    @ButtonHeistActor
    func testSwipePointToPointIntentDecodesPayload() async throws {
        let message = try await sentRuntimeMessage(
            command: .swipe,
            arguments: [
                "pointToPoint": .object([
                    "start": screenPointValue(x: 10, y: 20),
                    "end": screenPointValue(x: 30, y: 40),
                ]),
            ]
        )

        guard case .mechanicalSwipe(let target) = message,
              case .point(let start, let destination) = target.selection else {
            return XCTFail("Expected pointToPoint swipe payload, got \(message)")
        }
        XCTAssertEqual(start, ScreenPoint(x: 10, y: 20))
        XCTAssertEqual(destination, .coordinate(ScreenPoint(x: 30, y: 40)))
    }

    @ButtonHeistActor
    func testSwipePointDirectionIntentDecodesPayload() async throws {
        let message = try await sentRuntimeMessage(
            command: .swipe,
            arguments: [
                "pointDirection": .object([
                    "start": screenPointValue(x: 10, y: 20),
                    "direction": .string("down"),
                ]),
            ]
        )

        guard case .mechanicalSwipe(let target) = message,
              case .point(let start, let destination) = target.selection else {
            return XCTFail("Expected pointDirection swipe payload, got \(message)")
        }
        XCTAssertEqual(start, ScreenPoint(x: 10, y: 20))
        XCTAssertEqual(destination, .direction(.down))
    }

    @ButtonHeistActor
    func testSwipeRejectsMixedIntentPayloads() async {
        await assertValidationError(
            command: .swipe,
            arguments: [
                "pointDirection": .object([
                    "start": screenPointValue(x: 10, y: 20),
                    "direction": .string("down"),
                ]),
                "pointToPoint": .object([
                    "start": screenPointValue(x: 10, y: 20),
                    "end": screenPointValue(x: 30, y: 40),
                ]),
            ],
            equals: "swipe accepts exactly one gesture intent"
        )
    }

    @ButtonHeistActor
    func testSwipeRejectsMissingIntentPayload() async {
        await assertValidationError(
            command: .swipe,
            equals: "swipe requires a start target or point and an end point or direction"
        )
    }

    @ButtonHeistActor
    func testDragElementToPointIntentDecodesPayload() async throws {
        let message = try await sentRuntimeMessage(
            command: .drag,
            arguments: [
                "elementToPoint": .object([
                    "element": targetValue(identifier: "source"),
                    "start": unitPointValue(x: 0.5, y: 0.5),
                    "end": screenPointValue(x: 100, y: 200),
                ]),
            ]
        )

        guard case .mechanicalDrag(let target) = message,
              case .elementToPoint(let target, let start, let end) = target.selection else {
            return XCTFail("Expected elementToPoint drag payload, got \(message)")
        }
        XCTAssertEqual(target, .predicate(.identifier("source")))
        XCTAssertEqual(start, UnitPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(end, ScreenPoint(x: 100, y: 200))
    }

    @ButtonHeistActor
    func testDragPointToPointIntentDecodesPayload() async throws {
        let message = try await sentRuntimeMessage(
            command: .drag,
            arguments: [
                "pointToPoint": .object([
                    "start": screenPointValue(x: 100, y: 300),
                    "end": screenPointValue(x: 300, y: 600),
                ]),
            ]
        )

        guard case .mechanicalDrag(let target) = message,
              case .pointToPoint(let start, let end) = target.selection else {
            return XCTFail("Expected pointToPoint drag payload, got \(message)")
        }
        XCTAssertEqual(start, ScreenPoint(x: 100, y: 300))
        XCTAssertEqual(end, ScreenPoint(x: 300, y: 600))
    }

    @ButtonHeistActor
    func testDragRejectsMixedIntentPayloads() async {
        await assertValidationError(
            command: .drag,
            arguments: [
                "elementToPoint": .object([
                    "element": targetValue(identifier: "source"),
                    "end": screenPointValue(x: 100, y: 200),
                ]),
                "pointToPoint": .object([
                    "start": screenPointValue(x: 10, y: 20),
                    "end": screenPointValue(x: 100, y: 200),
                ]),
            ],
            equals: "drag accepts exactly one gesture intent"
        )
    }

    @ButtonHeistActor
    func testDragRejectsMissingIntentPayload() async {
        await assertValidationError(
            command: .drag,
            equals: "drag intent requires element, element with unitPoint, or ScreenPoint"
        )
    }

    @ButtonHeistActor
    private func sentRuntimeMessage(
        command: TheFence.Command,
        arguments: [String: HeistValue],
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> ResolvedHeistActionCommand {
        let (fence, mockConn) = makeConnectedFence()
        let response = try await fence.execute(command: command, values: arguments)
        if case .error(let failure) = response {
            XCTFail("Got validation error: \(failure.message)", file: file, line: line)
            throw GesturePayloadDecodingTestError.validationError(failure.message)
        }
        return try XCTUnwrap(mockConn.sent.sentPlanMessages.last, file: file, line: line)
    }

    @ButtonHeistActor
    private func assertValidationError(
        command: TheFence.Command,
        arguments: [String: HeistValue] = [:],
        equals expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let (fence, _) = makeConnectedFence()
        do {
            let response = try await fence.execute(command: command, values: arguments)
            if case .error(let failure) = response {
                XCTAssertEqual(failure.message, expected, file: file, line: line)
            } else {
                XCTFail("Expected .error response, got: \(response)", file: file, line: line)
            }
        } catch {
            XCTFail("Unexpected throw: \(error)", file: file, line: line)
        }
    }
}

private enum GesturePayloadDecodingTestError: Error {
    case validationError(String)
}

private func targetValue(identifier: String) -> HeistValue {
    .object([
        "checks": .array([
            .object([
                "kind": .string("identifier"),
                "match": stringMatchValue(identifier),
            ]),
        ]),
    ])
}

private func stringMatchValue(_ value: String) -> HeistValue {
    .object([
        "mode": .string("exact"),
        "value": .string(value),
    ])
}

private func unitPointValue(x: Double, y: Double) -> HeistValue {
    .object(["x": .double(x), "y": .double(y)])
}

private func screenPointValue(x: Double, y: Double) -> HeistValue {
    .object(["x": .double(x), "y": .double(y)])
}
