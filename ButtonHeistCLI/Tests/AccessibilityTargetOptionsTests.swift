import XCTest
@_spi(ButtonHeistTooling) import ButtonHeist
import ThePlans
@testable import ButtonHeistCLIExe

final class AccessibilityTargetOptionsTests: XCTestCase {

    func testHeistIdOptionIsNotSupported() throws {
        XCTAssertThrowsError(try OneFingerTapCommand.parse(["--heist-id", "button_save"]))
    }

    func testPositionalTargetIsRejected() {
        XCTAssertThrowsError(try OneFingerTapCommand.parse(["button_save"]))
    }

    func testMatcherOptionsParseToTypedPredicateTarget() throws {
        let command = try OneFingerTapCommand.parse([
            "--identifier", "saveButton",
            "--label", "Save",
            "--traits", "button",
            "--exclude-traits", "notEnabled",
            "--ordinal", "1",
        ])

        XCTAssertEqual(
            try command.element.parsedTarget(),
            .predicate(
                ElementPredicate(
                    [
                        .label("Save"),
                        .identifier("saveButton"),
                        .traits([.button]),
                        .exclude(.traits([.notEnabled])),
                    ]
                ),
                ordinal: 1
            )
        )
    }

    func testTapOptionsEncodeCanonicalTapTarget() throws {
        let command = try OneFingerTapCommand.parse(["--label", "Save"])

        try assertCanonicalArguments(
            try command.requestArguments(),
            equalTo: TapTarget(selection: .element(.label("Save")))
        )
    }

    func testLongPressOptionsEncodeCanonicalLongPressTarget() throws {
        let command = try LongPressCommand.parse(["--x", "12", "--y", "34", "--duration", "1.25"])

        try assertCanonicalArguments(
            try command.requestArguments(),
            equalTo: LongPressTarget(
                selection: .coordinate(ScreenPoint(x: 12, y: 34)),
                duration: try GestureDuration(validatingSeconds: 1.25)
            )
        )
    }

    func testSwipeOptionsEncodeCanonicalSwipeTarget() throws {
        let command = try SwipeCommand.parse([
            "--label", "Map",
            "--start-x", "0.8",
            "--start-y", "0.5",
            "--end-x", "0.2",
            "--end-y", "0.5",
        ])

        try assertCanonicalArguments(
            try command.requestArguments(),
            equalTo: SwipeTarget(selection: .unitElement(
                .label("Map"),
                start: UnitPoint(x: 0.8, y: 0.5),
                end: UnitPoint(x: 0.2, y: 0.5)
            ))
        )
    }

    func testDragOptionsEncodeCanonicalDragTarget() throws {
        let command = try DragCommand.parse([
            "--from-x", "10",
            "--from-y", "20",
            "--to-x", "30",
            "--to-y", "40",
        ])

        try assertCanonicalArguments(
            try command.requestArguments(),
            equalTo: DragTarget(selection: .pointToPoint(
                start: ScreenPoint(x: 10, y: 20),
                end: ScreenPoint(x: 30, y: 40)
            ))
        )
    }

    func testOrdinalOnlyIsRejectedAtTypedTargetBoundary() throws {
        let command = try OneFingerTapCommand.parse(["--ordinal", "0"])

        XCTAssertThrowsError(try command.element.parsedTarget()) { error in
            XCTAssertTrue(
                String(describing: error).contains("AccessibilityTarget requires a predicate"),
                "Unexpected error: \(error)"
            )
        }
    }

    func testTapWithoutTargetOrCoordinatesStillFailsValidation() async throws {
        var command = try OneFingerTapCommand.parse([])

        XCTAssertFalse(try command.element.hasTarget)

        do {
            try await command.run()
            XCTFail("Expected missing target validation to fail before connecting")
        } catch {
            XCTAssertTrue(
                String(describing: error).contains("Must specify --identifier, -l, or --x/--y coordinates"),
                "Unexpected error: \(error)"
            )
        }
    }
}

private func assertCanonicalArguments<Payload: Encodable>(
    _ arguments: TheFence.CommandArgumentEnvelope,
    equalTo payload: Payload,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    guard case .object(let expected) = try TheFence.HeistValuePayloadEncoder.encode(payload) else {
        return XCTFail("Expected canonical payload to encode as an object", file: file, line: line)
    }
    for (rawKey, value) in expected {
        guard let key = FenceParameterKey(rawValue: rawKey) else {
            XCTFail("Expected non-empty canonical payload key", file: file, line: line)
            continue
        }
        XCTAssertEqual(arguments.value(for: key), value, file: file, line: line)
    }
}
