import ButtonHeistTestSupport
import XCTest
import ThePlans
import AccessibilitySnapshotModel
@_spi(ButtonHeistInternals) @testable import TheScore

// MARK: - Wire Type Codable Round-Trip Tests

final class WireTypeRoundTripTests: XCTestCase {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - ButtonHeistVersion

    func testButtonHeistVersionRoundTripsAsWireString() throws {
        let version: ButtonHeistVersion = "1.2.3"

        let data = try encoder.encode(version)

        XCTAssertEqual(String(bytes: data, encoding: .utf8), #""1.2.3""#)
        XCTAssertEqual(try decoder.decode(ButtonHeistVersion.self, from: data), version)
    }

    func testRequestEnvelopeRejectsInvalidButtonHeistVersion() throws {
        let data = Data("""
        {"buttonHeistVersion":"1.0","type":"ping"}
        """.utf8)

        XCTAssertThrowsError(try decoder.decode(RequestEnvelope.self, from: data)) { error in
            assertDecodingError(error, contains: ["Button Heist version must be a MAJOR.MINOR.PATCH semantic version"])
        }
    }

    // MARK: - RequestID

    func testRequestIDRoundTripsAsWireString() throws {
        let requestID: RequestID = "request-1"

        let data = try encoder.encode(requestID)

        XCTAssertEqual(String(bytes: data, encoding: .utf8), #""request-1""#)
        XCTAssertEqual(try decoder.decode(RequestID.self, from: data), requestID)
    }

    func testRequestEnvelopeRejectsBlankRequestID() throws {
        for requestID in ["", " \n\t"] {
            let data = try JSONSerialization.data(withJSONObject: [
                "buttonHeistVersion": buttonHeistVersion.description,
                "requestId": requestID,
                "type": "ping",
            ])

            XCTAssertThrowsError(try decoder.decode(RequestEnvelope.self, from: data)) { error in
                assertDecodingError(error, contains: ["value must not be blank"])
            }
        }
    }

    // MARK: - AccessibilityPredicate

    func testAccessibilityPredicateWireContractValuesStayStable() {
        XCTAssertEqual(
            AccessibilityPredicate.wireTypeValues,
            ["exists", "missing", "announcement", "changed", "no_change"]
        )
    }

    // MARK: - ScrollEdge

    func testScrollEdgeRawValues() {
        XCTAssertEqual(ScrollEdge.top.rawValue, "top")
        XCTAssertEqual(ScrollEdge.bottom.rawValue, "bottom")
        XCTAssertEqual(ScrollEdge.left.rawValue, "left")
        XCTAssertEqual(ScrollEdge.right.rawValue, "right")
    }

    // MARK: - ScrollDirection

    func testScrollDirectionRawValues() {
        XCTAssertEqual(ScrollDirection.up.rawValue, "up")
        XCTAssertEqual(ScrollDirection.down.rawValue, "down")
        XCTAssertEqual(ScrollDirection.left.rawValue, "left")
        XCTAssertEqual(ScrollDirection.right.rawValue, "right")
    }

    // MARK: - EditActionTarget

    func testEditActionTargetRoundTrip() throws {
        for action in EditAction.allCases {
            let target = EditActionTarget(action: action)
            let data = try encoder.encode(target)
            let decoded = try decoder.decode(EditActionTarget.self, from: data)
            XCTAssertEqual(decoded.action, action)
        }
    }

    func testEditActionTargetRejectsUnknownPayloadKey() throws {
        let data = Data(#"{"action":"paste","foo":"bar"}"#.utf8)
        XCTAssertThrowsError(try decoder.decode(EditActionTarget.self, from: data)) { error in
            assertDecodingError(error, contains: [#"Unknown edit action target field "foo""#])
        }
    }

    // MARK: - Simple Command Payloads

    func testTypeTextTargetRejectsUnknownPayloadKey() throws {
        let data = Data(#"{"text":"hello","mode":"append","foo":"bar"}"#.utf8)
        XCTAssertThrowsError(try decoder.decode(TypeTextTarget.self, from: data)) { error in
            assertDecodingError(error, contains: [#"Unknown type text target field "foo""#])
        }
    }

    func testTypeTextStringRefLoweringRejectsEmptyResolvedText() throws {
        let command = HeistActionCommand.typeText(
            reference: "item",
            target: .predicate(ElementPredicateTemplate(label: "Add item"))
        )

        XCTAssertThrowsError(try command.resolve(in: HeistExecutionEnvironment(strings: ["item": ""]))) { error in
            XCTAssertEqual(error as? TextInputTextError, .emptyAppend)
        }
    }

    func testTypeTextStringRefLoweringAllowsEmptyResolvedTextWhenReplacingExisting() throws {
        let command = HeistActionCommand.typeText(
            reference: "item",
            target: .predicate(ElementPredicateTemplate(label: "Add item")),
            mode: .replace
        )

        let message = try command.resolve(in: HeistExecutionEnvironment(strings: ["item": ""]))

        guard case .typeText(let payload) = message else {
            return XCTFail("Expected typeText runtime message, got \(message)")
        }
        XCTAssertEqual(payload.text, .replacing(""))
    }

    func testSetPasteboardTargetRejectsUnknownPayloadKey() throws {
        let data = Data(#"{"text":"hello","foo":"bar"}"#.utf8)
        XCTAssertThrowsError(try decoder.decode(SetPasteboardTarget.self, from: data)) { error in
            assertDecodingError(error, contains: [#"Unknown pasteboard target field "foo""#])
        }
    }

    func testSetPasteboardTargetRejectsEmptyText() throws {
        let data = Data(#"{"text":""}"#.utf8)
        XCTAssertThrowsError(try decoder.decode(SetPasteboardTarget.self, from: data)) { error in
            assertDecodingError(error, contains: ["pasteboard text must be non-empty"])
        }
    }

    func testAuthenticatePayloadRejectsUnknownPayloadKey() throws {
        let data = Data(#"{"token":"secret","foo":"bar"}"#.utf8)
        XCTAssertThrowsError(try decoder.decode(AuthenticatePayload.self, from: data)) { error in
            assertDecodingError(error, contains: [#"Unknown authenticate payload field "foo""#])
        }
    }

    // MARK: - ActionResult Timing

    func testActionPerformanceTimingRoundTrip() throws {
        let timing = ActionPerformanceTiming(
            beforeObservationMs: 5,
            targetResolutionMs: 0,
            actionDispatchMs: 2,
            interactionMs: 12,
            finalSemanticEvidenceMs: 23,
            receiptGenerationMs: 0,
            totalMs: 116
        )

        _ = try assertRoundTrip(timing, encoder: encoder, decoder: decoder)
    }

    func testActionPerformanceTimingRejectsFormerSettlementField() {
        let json = #"{"settleMs":74}"#

        XCTAssertThrowsError(try decoder.decode(ActionPerformanceTiming.self, from: Data(json.utf8)))
    }

    func testActivationTraceRejectsMismatchedTapFields() throws {
        let missingTapResult = """
        {
          "axActivateReturned": false,
          "tapActivationDispatched": true,
          "tapActivationPoint": { "x": 10, "y": 20 }
        }
        """
        XCTAssertThrowsError(try decoder.decode(ActivationTrace.self, from: Data(missingTapResult.utf8))) { error in
            assertDecodingError(error, contains: ["requires tapActivationPoint and tapActivationSucceeded"])
        }

        let strayTapPoint = """
        {
          "axActivateReturned": true,
          "tapActivationDispatched": false,
          "tapActivationPoint": { "x": 10, "y": 20 },
          "tapActivationSucceeded": true
        }
        """
        XCTAssertThrowsError(try decoder.decode(ActivationTrace.self, from: Data(strayTapPoint.utf8))) { error in
            assertDecodingError(error, contains: ["require tapActivationDispatched"])
        }

        let declinedWithoutFallback = """
        {
          "axActivateReturned": false,
          "tapActivationDispatched": false
        }
        """
        XCTAssertThrowsError(
            try decoder.decode(ActivationTrace.self, from: Data(declinedWithoutFallback.utf8))
        ) { error in
            assertDecodingError(error, contains: ["axActivateReturned=false requires activation-point fallback fields"])
        }
    }

    func testActionPerformanceTimingMergingPreservesExistingFieldsAndAppliesOverlay() {
        let original = ActionPerformanceTiming(
            beforeObservationMs: 1,
            targetResolutionMs: 2,
            actionDispatchMs: 3,
            interactionMs: 4,
            finalSemanticEvidenceMs: 6,
            receiptGenerationMs: 7,
            totalMs: 8
        )
        let overlay = ActionPerformanceTiming(
            targetResolutionMs: 20,
            interactionMs: 40,
            receiptGenerationMs: 70,
            totalMs: 80
        )

        XCTAssertEqual(original.merging(nil), original)
        XCTAssertEqual(original.merging(overlay), ActionPerformanceTiming(
            beforeObservationMs: 1,
            targetResolutionMs: 20,
            actionDispatchMs: 3,
            interactionMs: 40,
            finalSemanticEvidenceMs: 6,
            receiptGenerationMs: 70,
            totalMs: 80
        ))
    }

    func testActionResultRoundTripPreservesTiming() throws {
        let timing = ActionPerformanceTiming(
            beforeObservationMs: 5,
            targetResolutionMs: 0,
            actionDispatchMs: 2,
            interactionMs: 12,
            finalSemanticEvidenceMs: 23,
            receiptGenerationMs: 0,
            totalMs: 116
        )
        let result = ActionResult.success(
            method: .activate,
            message: "activated",
            observation: .settledTrace(
                makeTestTraceEvidence(
                    .noChangeForTests(elementCount: 0),
                    completeness: .incomplete
                ),
                .settled(duration: 74)
            )
        ).withTiming(timing)

        let decoded = try assertRoundTrip(result, encoder: encoder, decoder: decoder)
        XCTAssertEqual(decoded.timing, timing)
    }

    func testActionResultWithTimingMergesWithoutErasingExistingFields() {
        let initialTiming = ActionPerformanceTiming(
            beforeObservationMs: 1,
            targetResolutionMs: 2,
            actionDispatchMs: 3,
            interactionMs: 4,
            finalSemanticEvidenceMs: 6,
            receiptGenerationMs: 7,
            totalMs: 8
        )
        let result = ActionResult.success(
            method: .activate,
            observation: .settledTrace(
                makeTestTraceEvidence(
                    .noChangeForTests(elementCount: 0),
                    completeness: .incomplete
                ),
                .settled(duration: 5)
            )
        ).withTiming(initialTiming)
        let overlay = ActionPerformanceTiming(
            beforeObservationMs: 10,
            actionDispatchMs: 30,
            finalSemanticEvidenceMs: 60
        )

        XCTAssertEqual(result.withTiming(nil), result)
        XCTAssertEqual(result.withTiming(overlay).timing, ActionPerformanceTiming(
            beforeObservationMs: 10,
            targetResolutionMs: 2,
            actionDispatchMs: 30,
            interactionMs: 4,
            finalSemanticEvidenceMs: 60,
            receiptGenerationMs: 7,
            totalMs: 8
        ))
        XCTAssertEqual(result.withTiming(overlay).settleTimeMs, 5)
    }

    // MARK: - CustomActionTarget

    func testCustomActionTargetRoundTrip() throws {
        let target = CustomActionTarget(
            target: .predicate(ElementPredicateTemplate(label: "btn_save")),
            actionName: "Delete Item"
        )
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(CustomActionTarget.self, from: data)
        XCTAssertEqual(
            decoded,
            CustomActionTarget(
                target: .predicate(ElementPredicateTemplate(label: "btn_save")),
                actionName: "Delete Item"
            )
        )
        XCTAssertEqual(decoded.actionName, "Delete Item")
    }

    func testCustomActionTargetWithMatcher() throws {
        let target = CustomActionTarget(
            target: .predicate(ElementPredicateTemplate(label: "Menu")),
            actionName: "Open Submenu"
        )
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(CustomActionTarget.self, from: data)
        XCTAssertEqual(decoded, CustomActionTarget(
            target: .predicate(ElementPredicateTemplate(label: "Menu")),
            actionName: "Open Submenu"
        ))
        XCTAssertEqual(decoded.actionName, "Open Submenu")
    }

    func testCustomActionTargetRejectsContainerField() throws {
        let data = Data("""
        {
          "container": {"containerName": "toolbar"},
          "actionName": "Dismiss"
        }
        """.utf8)

        XCTAssertThrowsError(try decoder.decode(CustomActionTarget.self, from: data)) { error in
            assertDecodingError(error, contains: ["Unknown custom action target field", "container"])
        }
    }

    // MARK: - LongPressTarget

    func testLongPressTargetRoundTrip() throws {
        let target = LongPressTarget(
            selection: .element(.predicate(ElementPredicateTemplate(label: "cell_1"))),
            duration: 1.5
        )
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(LongPressTarget.self, from: data)
        XCTAssertEqual(decoded.selection, .element(.predicate(ElementPredicateTemplate(label: "cell_1"))))
        XCTAssertEqual(decoded.duration.seconds, 1.5)
    }

    func testLongPressTargetWithPointRoundTrip() throws {
        let target = LongPressTarget(
            selection: .coordinate(ScreenPoint(x: 100, y: 200)),
            duration: 0.8
        )
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(LongPressTarget.self, from: data)
        XCTAssertEqual(decoded.selection, .coordinate(ScreenPoint(x: 100, y: 200)))
        XCTAssertEqual(decoded.duration.seconds, 0.8)
    }

    func testLongPressTargetDefaultDuration() {
        let target = LongPressTarget(selection: .coordinate(ScreenPoint(x: 10, y: 20)))
        XCTAssertEqual(target.duration.seconds, 0.5)
    }

    func testLongPressTargetRejectsInvalidDurationAtDecode() {
        let json = #"{"point":{"x":10,"y":20},"duration":61}"#
        XCTAssertThrowsError(try decoder.decode(LongPressTarget.self, from: Data(json.utf8))) { error in
            assertDecodingError(
                error,
                contains: ["duration must be finite number greater than 0 and no more than 60 (observed 61)"]
            )
        }
    }

    func testTapAndLongPressRejectMixedPointAndElementIntents() {
        let tapJSON =
            #"{"element":{"checks":[{"kind":"label","match":{"mode":"exact","value":"Save"}}]},"# +
            #""point":{"x":10,"y":20}}"#
        XCTAssertThrowsError(try decoder.decode(TapTarget.self, from: Data(tapJSON.utf8))) { error in
            assertErrorDescription(error, contains: ["accepts element, element with unitPoint, or ScreenPoint"])
        }

        let longPressJSON =
            #"{"element":{"checks":[{"kind":"label","match":{"mode":"exact","value":"Save"}}]},"# +
            #""point":{"x":10,"y":20},"duration":1}"#
        XCTAssertThrowsError(try decoder.decode(LongPressTarget.self, from: Data(longPressJSON.utf8))) { error in
            assertErrorDescription(error, contains: ["accepts element, element with unitPoint, or ScreenPoint"])
        }
    }

    func testSwipeAndDragRejectInvalidDurationAtDecode() {
        let swipeJSON = #"{"pointDirection":{"start":{"x":10,"y":20},"direction":"down"},"duration":0}"#
        XCTAssertThrowsError(try decoder.decode(SwipeTarget.self, from: Data(swipeJSON.utf8))) { error in
            assertDecodingError(
                error,
                contains: ["duration must be finite number greater than 0 and no more than 60 (observed 0)"]
            )
        }

        let dragJSON = #"{"pointToPoint":{"start":{"x":10,"y":20},"end":{"x":30,"y":40}},"duration":61}"#
        XCTAssertThrowsError(try decoder.decode(DragTarget.self, from: Data(dragJSON.utf8))) { error in
            assertDecodingError(
                error,
                contains: ["duration must be finite number greater than 0 and no more than 60 (observed 61)"]
            )
        }
    }

    // MARK: - DragTarget

    func testDragTargetRoundTrip() throws {
        let target = DragTarget(
            start: .element(.predicate(ElementPredicateTemplate(label: "handle"))),
            end: ScreenPoint(x: 200, y: 300),
            duration: 0.8
        )
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(DragTarget.self, from: data)
        XCTAssertEqual(decoded.start, .element(.predicate(ElementPredicateTemplate(label: "handle"))))
        XCTAssertEqual(decoded.end, ScreenPoint(x: 200, y: 300))
        XCTAssertEqual(decoded.duration?.seconds, 0.8)
    }

    func testDragTargetCoordinateStartRoundTrip() throws {
        let target = DragTarget(
            start: .coordinate(ScreenPoint(x: 10, y: 20)),
            end: ScreenPoint(x: 30, y: 40)
        )
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(DragTarget.self, from: data)
        XCTAssertEqual(decoded.start, .coordinate(ScreenPoint(x: 10, y: 20)))
        XCTAssertEqual(decoded.end, ScreenPoint(x: 30, y: 40))
    }

    func testDragTargetRejectsUnknownField() {
        let json = #"{"pointToPoint":{"start":{"x":10,"y":20},"end":{"x":30,"y":40}},"unexpected":true}"#
        XCTAssertThrowsError(try decoder.decode(DragTarget.self, from: Data(json.utf8))) { error in
            assertDecodingError(error, contains: ["Unknown drag target field", "unexpected"])
        }
    }

    func testSwipeTargetRejectsUnknownField() {
        let json = #"{"pointDirection":{"start":{"x":10,"y":20},"direction":"down"},"unexpected":true}"#
        XCTAssertThrowsError(try decoder.decode(SwipeTarget.self, from: Data(json.utf8))) { error in
            assertDecodingError(error, contains: ["Unknown swipe target field", "unexpected"])
        }
    }

    func testSwipeTargetRejectsMixedIntentFields() {
        let json = #"""
        {
          "pointDirection": {"start": {"x": 10, "y": 20}, "direction": "down"},
          "pointToPoint": {"start": {"x": 10, "y": 20}, "end": {"x": 30, "y": 40}}
        }
        """#

        XCTAssertThrowsError(try decoder.decode(SwipeTarget.self, from: Data(json.utf8))) { error in
            assertErrorDescription(error, contains: ["swipe accepts exactly one gesture intent"])
        }
    }

    func testSwipeTargetRejectsUnknownNestedIntentField() {
        let json = #"{"pointDirection":{"start":{"x":10,"y":20},"direction":"down","target":{"label":"Row"}}}"#
        XCTAssertThrowsError(try decoder.decode(SwipeTarget.self, from: Data(json.utf8))) { error in
            assertDecodingError(error, contains: ["Unknown point direction swipe field", "target"])
        }
    }

    func testDragTargetRejectsMixedIntentFields() {
        let json = #"""
        {
          "elementToPoint": {
            "element": {"checks": [{"kind": "label", "match": {"mode": "exact", "value": "Card"}}]},
            "end": {"x": 30, "y": 40}
          },
          "pointToPoint": {"start": {"x": 10, "y": 20}, "end": {"x": 30, "y": 40}}
        }
        """#

        XCTAssertThrowsError(try decoder.decode(DragTarget.self, from: Data(json.utf8))) { error in
            assertErrorDescription(error, contains: ["drag accepts exactly one gesture intent"])
        }
    }

    func testDragTargetRejectsUnknownNestedIntentField() {
        let json = #"{"elementToPoint":{"element":{"checks":["# +
            #"{"kind":"label","match":{"mode":"exact","value":"Handle"}}]},"# +
            #""end":{"x":30,"y":40},"offset":{"x":10,"y":20}}}"#
        XCTAssertThrowsError(try decoder.decode(DragTarget.self, from: Data(json.utf8))) { error in
            assertDecodingError(error, contains: ["Unknown element-to-point drag field", "offset"])
        }
    }

    func testGestureResolvedDefaultsAreContractOwned() {
        XCTAssertEqual(
            SwipeTarget(selection: .point(
                start: .element(.predicate(ElementPredicateTemplate(label: "list"))),
                destination: .direction(.down)
            )).resolvedDuration,
            .swipeDefault
        )
        XCTAssertEqual(
            DragTarget(start: .coordinate(ScreenPoint(x: 10, y: 20)), end: ScreenPoint(x: 30, y: 40)).resolvedDuration,
            .dragDefault
        )
    }

    // MARK: - ScrollTarget

    func testScrollTargetRoundTrip() throws {
        let target = ScrollTarget(
            selection: .element(.predicate(ElementPredicateTemplate(label: "list"))),
            direction: .down
        )
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(ScrollTarget.self, from: data)
        XCTAssertEqual(decoded.selection, .element(.predicate(ElementPredicateTemplate(label: "list"))))
        XCTAssertEqual(decoded.direction, .down)
    }

    func testScrollTargetRoundTripsScopedAccessibilityTarget() throws {
        let accessibilityTarget = AccessibilityTarget.within(container: .scrollable(true), .label("Pay"))
        let request = ScrollTarget(selection: .element(accessibilityTarget), direction: .down)
        let data = try encoder.encode(request)
        let decoded = try decoder.decode(ScrollTarget.self, from: data)

        XCTAssertEqual(decoded.selection, .element(accessibilityTarget))
        XCTAssertEqual(decoded.direction, .down)
    }

    func testScrollTargetAllDirections() throws {
        for direction in ScrollDirection.allCases {
            let target = ScrollTarget(direction: direction)
            let data = try encoder.encode(target)
            let decoded = try decoder.decode(ScrollTarget.self, from: data)
            XCTAssertEqual(decoded.direction, direction)
        }
    }

    func testScrollTargetAcceptsContainerNameString() throws {
        let data = Data(#"{"containerName":"main_scroll","direction":"up"}"#.utf8)
        let decoded = try decoder.decode(ScrollTarget.self, from: data)

        XCTAssertEqual(decoded.selection, .container("main_scroll"))
        XCTAssertEqual(decoded.direction, .up)
    }

    func testScrollTargetRejectsLegacyContainerNameStringKey() throws {
        let data = Data(#"{"container":"main_scroll","direction":"up"}"#.utf8)
        XCTAssertThrowsError(try decoder.decode(ScrollTarget.self, from: data)) { error in
            assertDecodingError(error, contains: [#"Unknown scroll target field "container""#])
        }
    }

    func testScrollTargetRejectsPartialScopedTargetContainer() throws {
        let data = Data(#"{"container":{"checks":[{"kind":"scrollable","value":true}]},"direction":"up"}"#.utf8)
        XCTAssertThrowsError(try decoder.decode(ScrollTarget.self, from: data)) { error in
            assertDecodingError(error, contains: [#"Unknown scroll target field "container""#])
        }
    }

    func testScrollTargetRejectsUnknownPayloadKey() throws {
        let data = Data(#"{"direction":"down","foo":"bar"}"#.utf8)
        XCTAssertThrowsError(try decoder.decode(ScrollTarget.self, from: data)) { error in
            assertDecodingError(error, contains: [#"Unknown scroll target field "foo""#])
        }
    }

    func testScrollPrimitiveRequestEnvelopeIsRejected() throws {
        let data = Data((
            #"{"buttonHeistVersion":"\#(buttonHeistVersion)","type":"scroll","# +
            #""payload":{"direction":"down","containerName":"main_scroll"}}"#
        ).utf8)
        XCTAssertThrowsError(try decoder.decode(RequestEnvelope.self, from: data)) { error in
            assertDecodingError(error, contains: ["Unsupported client wire message type"])
        }
    }

    // MARK: - ScrollToEdgeTarget

    func testScrollToEdgeTargetAllEdges() throws {
        for edge in ScrollEdge.allCases {
            let target = ScrollToEdgeTarget(
                selection: .element(.predicate(ElementPredicateTemplate(label: "scroll_view"))),
                edge: edge
            )
            let data = try encoder.encode(target)
            let decoded = try decoder.decode(ScrollToEdgeTarget.self, from: data)
            XCTAssertEqual(decoded.edge, edge)
            XCTAssertEqual(decoded.selection, .element(.predicate(ElementPredicateTemplate(label: "scroll_view"))))
        }
    }

    func testScrollToEdgeTargetRoundTripsScopedAccessibilityTarget() throws {
        let accessibilityTarget = AccessibilityTarget.within(container: .scrollable(true), .label("Pay"))
        let request = ScrollToEdgeTarget(selection: .element(accessibilityTarget), edge: .bottom)
        let data = try encoder.encode(request)
        let decoded = try decoder.decode(ScrollToEdgeTarget.self, from: data)

        XCTAssertEqual(decoded.selection, .element(accessibilityTarget))
        XCTAssertEqual(decoded.edge, .bottom)
    }

    func testScrollToEdgeTargetAcceptsContainerNameString() throws {
        let data = Data(#"{"containerName":"main_scroll","edge":"bottom"}"#.utf8)
        let decoded = try decoder.decode(ScrollToEdgeTarget.self, from: data)

        XCTAssertEqual(decoded.selection, .container("main_scroll"))
        XCTAssertEqual(decoded.edge, .bottom)
    }

    func testScrollToEdgeTargetRejectsLegacyContainerNameStringKey() throws {
        let data = Data(#"{"container":"main_scroll","edge":"bottom"}"#.utf8)
        XCTAssertThrowsError(try decoder.decode(ScrollToEdgeTarget.self, from: data)) { error in
            assertDecodingError(error, contains: [#"Unknown scroll_to_edge target field "container""#])
        }
    }

    func testScrollToEdgeTargetRejectsPartialScopedTargetContainer() throws {
        let data = Data(#"{"container":{"checks":[{"kind":"scrollable","value":true}]},"edge":"bottom"}"#.utf8)
        XCTAssertThrowsError(try decoder.decode(ScrollToEdgeTarget.self, from: data)) { error in
            assertDecodingError(error, contains: [#"Unknown scroll_to_edge target field "container""#])
        }
    }

    func testScrollToEdgeTargetRejectsUnknownPayloadKey() throws {
        let data = Data(#"{"edge":"bottom","foo":"bar"}"#.utf8)
        XCTAssertThrowsError(try decoder.decode(ScrollToEdgeTarget.self, from: data)) { error in
            assertDecodingError(error, contains: [#"Unknown scroll_to_edge target field "foo""#])
        }
    }

    func testScrollToEdgePrimitiveRequestEnvelopeIsRejected() throws {
        let data = Data((
            #"{"buttonHeistVersion":"\#(buttonHeistVersion)","type":"scrollToEdge","# +
            #""payload":{"edge":"bottom","unexpected":"main_scroll"}}"#
        ).utf8)
        XCTAssertThrowsError(try decoder.decode(RequestEnvelope.self, from: data)) { error in
            assertDecodingError(error, contains: ["Unsupported client wire message type"])
        }
    }

    // MARK: - ProtocolMismatchPayload

    func testProtocolMismatchPayloadRoundTrip() throws {
        let payload = ProtocolMismatchPayload(
            serverButtonHeistVersion: "2026.5.9",
            clientButtonHeistVersion: "2026.5.8"
        )
        let data = try encoder.encode(payload)
        let decoded = try decoder.decode(ProtocolMismatchPayload.self, from: data)
        XCTAssertEqual(decoded.serverButtonHeistVersion, "2026.5.9")
        XCTAssertEqual(decoded.clientButtonHeistVersion, "2026.5.8")
    }

    // MARK: - AccessibilityContainer

    func testAccessibilityContainerRoundTrip() throws {
        let container = makeTestAccessibilityContainer(
            type: .none, scrollableContentSize: AccessibilitySize(width: 390, height: 1000),
            frameY: 100,
            frameWidth: 390,
            frameHeight: 700
        )
        let data = try encoder.encode(container)
        let decoded = try decoder.decode(AccessibilityContainer.self, from: data)
        XCTAssertEqual(decoded, container)
    }

    func testAccessibilityContainerSemanticGroupRoundTrip() throws {
        let container = makeTestAccessibilityContainer(
            type: .semanticGroup(label: "Settings", value: nil), identifier: "settings",
            frameWidth: 390,
            frameHeight: 100
        )
        let data = try encoder.encode(container)
        let decoded = try decoder.decode(AccessibilityContainer.self, from: data)
        XCTAssertEqual(decoded, container)
    }

    func testAccessibilityContainerModalBoundaryRoundTrip() throws {
        let container = makeTestAccessibilityContainer(
            type: .semanticGroup(label: "Alert", value: nil), identifier: nil,
            frameWidth: 390,
            frameHeight: 300,
            isModalBoundary: true
        )
        let data = try encoder.encode(container)
        let decoded = try decoder.decode(AccessibilityContainer.self, from: data)
        XCTAssertEqual(decoded, container)
    }

    // MARK: - InterfaceQuery

    func testInterfaceQueryDiscoveryLimitsRoundTrip() throws {
        let query = InterfaceQuery(maxScrollsPerContainer: 1, maxScrollsPerDiscovery: 2_000)
        let data = try encoder.encode(query)
        let decoded = try decoder.decode(InterfaceQuery.self, from: data)

        XCTAssertEqual(decoded, query)
    }

    func testInterfaceQueryRejectsNegativeDiscoveryLimit() {
        let json = #"{"maxScrollsPerContainer":-1}"#

        XCTAssertThrowsError(try decoder.decode(InterfaceQuery.self, from: Data(json.utf8))) { error in
            assertDecodingError(error, contains: ["maxScrollsPerContainer must be between 1 and 2000"])
        }
    }

    func testInterfaceQueryRejectsOversizedDiscoveryLimit() {
        let json = #"{"maxScrollsPerDiscovery":2001}"#

        XCTAssertThrowsError(try decoder.decode(InterfaceQuery.self, from: Data(json.utf8))) { error in
            assertDecodingError(error, contains: ["maxScrollsPerDiscovery must be between 1 and 2000"])
        }
    }

    func testInterfaceQueryRejectsRemovedMatcherField() {
        let json = #"""
        {
          "matcher": {
            "checks": [
              { "kind": "identifier", "match": { "mode": "exact", "value": "save" } }
            ]
          }
        }
        """#

        XCTAssertThrowsError(try decoder.decode(InterfaceQuery.self, from: Data(json.utf8))) { error in
            assertDecodingError(error, contains: ["matcher"])
        }
    }

    // MARK: - InterfaceQuery Subtree Targets

    func testInterfaceQueryElementSubtreeUsesCanonicalTargetShape() throws {
        let query = InterfaceQuery(
            subtree: .predicate(ElementPredicateTemplate(label: "Save", traits: [.button]), ordinal: 2)
        )

        let data = try encoder.encode(query)
        let payload = try JSONProbe(data: data)
        let subtree = try payload.object("subtree")
        XCTAssertEqual(try subtree.int("ordinal"), 2)
        try subtree.assertMissing("element")
        try subtree.assertMissing("container")
        try subtree.assertMissing("heistId")
        let checks = try subtree.array("checks")
        XCTAssertEqual(checks.count, 2)
        XCTAssertEqual(try checks[0].string("kind"), "label")
        let labelMatch = try checks[0].object("match")
        XCTAssertEqual(try labelMatch.string("mode"), "exact")
        XCTAssertEqual(try labelMatch.string("value"), "Save")
        XCTAssertEqual(try checks[1].string("kind"), "traits")
        XCTAssertEqual(try checks[1].strings("values"), ["button"])
        XCTAssertEqual(try decoder.decode(InterfaceQuery.self, from: data), query)
    }

    func testInterfaceQueryElementSubtreeOmitsAbsentOrdinal() throws {
        let query = InterfaceQuery(subtree: .label("Save"))

        let data = try encoder.encode(query)
        let payload = try JSONProbe(data: data)
        let subtree = try payload.object("subtree")
        try subtree.assertMissing("ordinal")
        try subtree.assertMissing("element")
        try subtree.assertMissing("heistId")
        let checks = try subtree.array("checks")
        XCTAssertEqual(checks.count, 1)
        XCTAssertEqual(try checks[0].string("kind"), "label")
        let labelMatch = try checks[0].object("match")
        XCTAssertEqual(try labelMatch.string("mode"), "exact")
        XCTAssertEqual(try labelMatch.string("value"), "Save")
        XCTAssertEqual(try decoder.decode(InterfaceQuery.self, from: data), query)
    }

    func testInterfaceQueryContainerSubtreeUsesCanonicalTargetShape() throws {
        let query = InterfaceQuery(
            subtree: .container(
                .matching(.type(.semanticGroup), .semantic(.label("Actions"))),
                ordinal: 1
            )
        )

        let data = try encoder.encode(query)
        let payload = try JSONProbe(data: data)
        let subtree = try payload.object("subtree")
        XCTAssertEqual(try subtree.int("ordinal"), 1)
        let container = try subtree.object("container")
        try subtree.assertMissing("element")
        let checks = try container.array("checks")
        XCTAssertEqual(checks.count, 2)
        XCTAssertEqual(try checks[0].string("kind"), "type")
        XCTAssertEqual(try checks[0].string("type"), "semanticGroup")
        XCTAssertEqual(try checks[1].string("kind"), "semantic")
        let semantic = try checks[1].object("semantic")
        XCTAssertEqual(try semantic.string("kind"), "label")
        let label = try semantic.object("match")
        XCTAssertEqual(try label.string("mode"), "exact")
        XCTAssertEqual(try label.string("value"), "Actions")
        XCTAssertEqual(try decoder.decode(InterfaceQuery.self, from: data), query)
    }

    func testInterfaceQueryContainerSubtreeRequiresPredicateObject() throws {
        let data = Data(#"{"subtree":{"container":"semantic_actions"}}"#.utf8)
        XCTAssertThrowsError(try decoder.decode(InterfaceQuery.self, from: data))
    }

    func testInterfaceQueryContainerSubtreeAcceptsPredicateObject() throws {
        let data = Data(#"{"subtree":{"container":{"checks":[{"kind":"scrollable","value":true}]}}}"#.utf8)
        let decoded = try decoder.decode(InterfaceQuery.self, from: data)

        XCTAssertEqual(decoded.subtree, .container(.scrollable(true)))
    }

    func testInterfaceQueryElementSubtreeRejectsHeistIdField() {
        let json = #"{"subtree":{"heistId":"button_save","checks":["# +
            #"{"kind":"label","match":{"mode":"exact","value":"Save"}}]}}"#
        XCTAssertThrowsError(try decoder.decode(InterfaceQuery.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("heistId"), "\(error)")
        }
    }

    func testInterfaceQueryElementSubtreeRejectsHeistIdOnlyField() {
        let json = #"{"subtree":{"heistId":"button_save","ordinal":1}}"#
        XCTAssertThrowsError(try decoder.decode(InterfaceQuery.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("heistId"), "\(error)")
        }
    }

    func testInterfaceQueryElementSubtreeRejectsUnknownTargetField() {
        let json = #"{"subtree":{"checks":["# +
            #"{"kind":"label","match":{"mode":"exact","value":"Save"}}],"# +
            #""unexpectedTargetField":"button_save"}}"#
        XCTAssertThrowsError(try decoder.decode(InterfaceQuery.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("unexpectedTargetField"), "\(error)")
        }
    }

    func testInterfaceQuerySubtreeRejectsRemovedElementWrapperShape() {
        let json = #"{"subtree":{"element":{"checks":[{"kind":"label","match":{"mode":"exact","value":"Save"}}]}}}"#
        XCTAssertThrowsError(try decoder.decode(InterfaceQuery.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("element"), "\(error)")
        }
    }

    func testInterfaceQueryContainerSubtreeRejectsNegativeOrdinal() {
        let json = #"{"subtree":{"container":{"checks":[{"kind":"scrollable","value":true}]},"ordinal":-1}}"#
        XCTAssertThrowsError(try decoder.decode(InterfaceQuery.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("non-negative"), "\(error)")
        }
    }

    func testInterfaceQueryScopedSubtreeRejectsOuterOrdinal() {
        let json = #"{"subtree":{"container":{"checks":[{"kind":"scrollable","value":true}]},"# +
            #""target":{"checks":["# +
            #"{"kind":"label","match":{"mode":"exact","value":"Save"}}]},"ordinal":1}}"#
        XCTAssertThrowsError(try decoder.decode(InterfaceQuery.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("ordinal"), "\(error)")
        }
    }

    // MARK: - AccessibilityHierarchy

    func testAccessibilityHierarchyLeafRoundTrip() throws {
        let element = HeistElement(
            description: "Button", label: "OK", value: nil, identifier: nil,
            frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44, actions: [.activate]
        )
        let node = AccessibilityHierarchy.element(makeTestAccessibilityElement(element), traversalIndex: 0)
        let data = try encoder.encode(node)
        let decoded = try decoder.decode(AccessibilityHierarchy.self, from: data)
        XCTAssertEqual(decoded, node)
    }

    func testAccessibilityHierarchyContainerRoundTrip() throws {
        let elementA = HeistElement(
            description: "A", label: "A", value: nil, identifier: nil,
            frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44, actions: []
        )
        let elementB = HeistElement(
            description: "B", label: "B", value: nil, identifier: nil,
            frameX: 0, frameY: 50, frameWidth: 100, frameHeight: 44, actions: []
        )
        let outer = makeTestAccessibilityContainer(
            type: .list,
            frameWidth: 390,
            frameHeight: 600
        )
        let inner = makeTestAccessibilityContainer(
            type: .semanticGroup(label: nil, value: nil), identifier: nil,
            frameWidth: 390,
            frameHeight: 44
        )
        let node = AccessibilityHierarchy.container(outer, children: [
            .element(makeTestAccessibilityElement(elementA), traversalIndex: 0),
            .container(inner, children: [.element(makeTestAccessibilityElement(elementB), traversalIndex: 1)]),
        ])
        let data = try encoder.encode(node)
        let decoded = try decoder.decode(AccessibilityHierarchy.self, from: data)
        XCTAssertEqual(decoded, node)
    }

    // MARK: - SwipeDirection

    func testSwipeDirectionDefaultStartEnd() {
        XCTAssertEqual(SwipeDirection.left.defaultStart, UnitPoint(x: 0.8, y: 0.5))
        XCTAssertEqual(SwipeDirection.left.defaultEnd, UnitPoint(x: 0.2, y: 0.5))
        XCTAssertEqual(SwipeDirection.right.defaultStart, UnitPoint(x: 0.2, y: 0.5))
        XCTAssertEqual(SwipeDirection.right.defaultEnd, UnitPoint(x: 0.8, y: 0.5))
        XCTAssertEqual(SwipeDirection.up.defaultStart, UnitPoint(x: 0.5, y: 0.8))
        XCTAssertEqual(SwipeDirection.up.defaultEnd, UnitPoint(x: 0.5, y: 0.2))
        XCTAssertEqual(SwipeDirection.down.defaultStart, UnitPoint(x: 0.5, y: 0.2))
        XCTAssertEqual(SwipeDirection.down.defaultEnd, UnitPoint(x: 0.5, y: 0.8))
    }

    func testUnitPointRejectsUnknownField() {
        let json = #"{"x":0.2,"y":0.8,"unexpected":true}"#
        XCTAssertThrowsError(try decoder.decode(UnitPoint.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("Unknown unit point field"), "\(error)")
            XCTAssertTrue("\(error)".contains("unexpected"), "\(error)")
        }
    }

    // MARK: - HeistPlan

    func testHeistPlanRoundTripPreservesCommandStepWireShape() throws {
        let plan = try HeistPlan(body: [
                .action(try ActionStep(
                    command: .activate(.predicate(
                        ElementPredicateTemplate(label: "Settings", traits: [.button]),
                        ordinal: 1
                    )),
                    expectationPolicy: .expect(ActionExpectation(predicate: .changed(.screen()), timeout: 2.5)))),
                .action(try ActionStep(
                    command: .setPasteboard(SetPasteboardTarget(text: "ready"))
                )),
                .warn(WarnStep(message: "optional step skipped")),
                .fail(FailStep(message: "unexpected state"))
            ]
        )

        let data = try encoder.encode(plan)
        let payload = try JSONProbe(data: data)

        XCTAssertEqual(try payload.int("version"), HeistPlan.currentVersion)
        let body = try payload.array("body")
        XCTAssertEqual(body.count, 4)
        XCTAssertEqual(try body[0].string("type"), "action")
        let action = try body[0].object("action")
        let command = try action.object("command")
        XCTAssertEqual(try command.string("type"), "activate")
        let target = try command.object("payload").object("target")
        XCTAssertEqual(try target.int("ordinal"), 1)
        let checks = try target.array("checks")
        XCTAssertEqual(checks.count, 2)
        XCTAssertEqual(try checks[0].string("kind"), "label")
        let labelMatch = try checks[0].object("match")
        XCTAssertEqual(try labelMatch.string("mode"), "exact")
        XCTAssertEqual(try labelMatch.string("value"), "Settings")
        XCTAssertEqual(try checks[1].string("kind"), "traits")
        XCTAssertEqual(try checks[1].strings("values"), ["button"])
        let expectation = try action.object("expectation")
        let predicate = try expectation.object("predicate")
        XCTAssertEqual(try predicate.string("type"), "changed")
        XCTAssertEqual(try predicate.string("scope"), "screen")
        XCTAssertTrue(try predicate.array("assertions").isEmpty)
        XCTAssertEqual(try expectation.double("timeout"), 2.5)
        XCTAssertEqual(try body[2].object("warn").string("message"), "optional step skipped")
        XCTAssertEqual(try body[3].object("fail").string("message"), "unexpected state")

        let decoded = try decoder.decode(HeistPlan.self, from: data)
        XCTAssertEqual(decoded, plan)
    }

    func testHeistExecutionResultRoundTripKeepsActivationTraceOnlyInActionEvidence() throws {
        let command = HeistActionCommand.activate(.predicate(ElementPredicateTemplate(label: "Save")))
        let activationTrace = ActivationTrace(.activationPointFallback(
            axActivateReturned: false,
            tapActivationPoint: ScreenPoint(x: 195, y: 139),
            tapActivationSucceeded: true
        ))
        let failure = HeistFailureDetail(
            category: .targetResolution,
            contract: "action dispatch succeeds",
            observed: "No element matching label \"Save\"",
            expected: "predicate(label=\"Save\")"
        )
        let step = HeistReceiptFixture.action(
            command: command,
            result: .activationFailure(
                errorKind: .elementNotFound,
                message: "No element matching label \"Save\"",
                observation: .none,
                activationTrace: activationTrace
            ),
            durationMs: 0,
            failure: failure
        )
        let result = HeistReceiptFixture.result(steps: [step])

        let data = try encoder.encode(result)
        let decoded = try decoder.decode(HeistExecutionResult.self, from: data)

        XCTAssertEqual(decoded, result)
        XCTAssertEqual(decoded.abortedAtPath?.description, "$.body[0]")
        XCTAssertEqual(decoded.steps[0].actionEvidence?.dispatchResult?.activationTrace, activationTrace)

        let payload = try JSONProbe(data: data)
        let encodedStep = try payload.array("steps")[0]
        let node = try encodedStep.object("node")
        let encodedFailure = try node.object("failure")
        XCTAssertEqual(try node.string("type"), "action")
        XCTAssertEqual(try node.string("outcome"), "failed")
        XCTAssertEqual(try node.object("command").string("type"), "activate")
        try encodedStep.assertMissing("kind")
        try encodedStep.assertMissing("intent")
        try encodedStep.assertMissing("outcome")
        try encodedFailure.assertMissing("activationTrace")
    }

    func testInvocationExpectationDerivesSummaryFromWaitEvidence() throws {
        let predicate = AccessibilityPredicate.exists(.label("Done"))
        let actionResult = ActionResult.success(method: .wait)
        let expectation = ExpectationResult.Met(predicate: predicate)
        let check = try XCTUnwrap(HeistWaitEvidence.MatchedCheck(
            actionResult: actionResult,
            expectation: expectation
        ))
        let waitEvidence = HeistWaitEvidence.matched(check)
        let evidence = HeistInvocationEvidence.InvocationExpectationEvidence.wait(waitEvidence)

        XCTAssertEqual(evidence.actionResult, waitEvidence.actionResult)
        XCTAssertEqual(evidence.expectation, waitEvidence.expectation)
        XCTAssertEqual(evidence.waitEvidence, waitEvidence)
    }

    func testHeistCaseSelectionRejectsLegacyAndLooseOutcomeShapes() throws {
        let legacy = """
        {
          "cases": [],
          "selectedCaseIndex": 0,
          "elapsedMs": 1,
          "timedOut": false,
          "elseRan": false
        }
        """
        XCTAssertThrowsError(try decoder.decode(HeistCaseSelectionResult.self, from: Data(legacy.utf8))) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected DecodingError.dataCorrupted, got \(error)")
            }
            XCTAssertTrue(
                ["selectedCaseIndex", "timedOut", "elseRan"].contains { context.debugDescription.contains($0) },
                context.debugDescription
            )
        }

        let looseOutcome = """
        {
          "cases": [],
          "outcome": {
            "kind": "no_match",
            "index": 0
          },
          "elapsedMs": 1
        }
        """
        XCTAssertThrowsError(
            try decoder.decode(HeistCaseSelectionResult.self, from: Data(looseOutcome.utf8))
        ) { error in
            assertDecodingError(error, contains: ["no_match", "index"])
        }

        let missingMatchedIndex = """
        {
          "cases": [],
          "outcome": {
            "kind": "matched_case"
          },
          "elapsedMs": 1
        }
        """
        XCTAssertThrowsError(
            try decoder.decode(HeistCaseSelectionResult.self, from: Data(missingMatchedIndex.utf8))
        ) { error in
            assertDecodingError(error, contains: ["matched_case", "requires index"])
        }

        let outOfRangeMatchedIndex = """
        {
          "cases": [],
          "outcome": {
            "kind": "matched_case",
            "index": 0
          },
          "elapsedMs": 1
        }
        """
        XCTAssertThrowsError(
            try decoder.decode(HeistCaseSelectionResult.self, from: Data(outOfRangeMatchedIndex.utf8))
        ) { error in
            assertDecodingError(error, contains: ["matched_case index 0", "out of range"])
        }
    }

    func testForEachStringEvidenceRejectsPartialIterationShape() throws {
        let missingValue = """
        {
          "iterationCount": 1,
          "iterationOrdinal": 0
        }
        """

        XCTAssertThrowsError(
            try decoder.decode(HeistForEachStringEvidence.self, from: Data(missingValue.utf8))
        ) { error in
            assertDecodingError(error, contains: ["requires iterationOrdinal and value together"])
        }
    }

    func testForEachElementEvidenceRejectsPartialIterationShape() throws {
        let missingTargetSummary = """
        {
          "matchedCount": 2,
          "iterationCount": 1,
          "iterationOrdinal": 0,
          "targetOrdinal": 0
        }
        """

        XCTAssertThrowsError(
            try decoder.decode(HeistForEachElementEvidence.self, from: Data(missingTargetSummary.utf8))
        ) { error in
            assertDecodingError(
                error,
                contains: ["requires iterationOrdinal, targetOrdinal, and targetSummary together"]
            )
        }
    }

    func testRotorTextRangeRejectsPartialIndexedShape() throws {
        let missingEndOffset = """
        {
          "rangeDescription": "[0..<4]",
          "text": "Menu",
          "startOffset": 0
        }
        """

        XCTAssertThrowsError(try decoder.decode(RotorTextRange.self, from: Data(missingEndOffset.utf8))) { error in
            assertDecodingError(error, contains: ["requires startOffset and endOffset together"])
        }
    }

    // MARK: - HeistCustomContent

    func testHeistCustomContentRoundTrip() throws {
        let content = HeistCustomContent(label: "Price", value: "$9.99", isImportant: true)
        let data = try encoder.encode(content)
        let decoded = try decoder.decode(HeistCustomContent.self, from: data)
        XCTAssertEqual(decoded.label, "Price")
        XCTAssertEqual(decoded.value, "$9.99")
        XCTAssertTrue(decoded.isImportant)
    }

    // MARK: - AccessibilityTrace.ChangeFact
    //
    // Coverage lives in AccessibilityTraceChangeFactRoundTripTests.swift; this file's
    // generic round-trip suite is for shapes without per-case Codable.

    // MARK: - PropertyChange / ElementUpdate

    func testPropertyChangeRoundTrip() throws {
        let change = PropertyChange.value(old: "OK", new: "Cancel")
        let data = try encoder.encode(change)
        let decoded = try decoder.decode(PropertyChange.self, from: data)
        XCTAssertEqual(decoded, change)
    }

    func testElementPropertyIsGeometry() {
        XCTAssertTrue(ElementProperty.frame.isGeometry)
        XCTAssertTrue(ElementProperty.activationPoint.isGeometry)
        XCTAssertFalse(ElementProperty.value.isGeometry)
        XCTAssertFalse(ElementProperty.traits.isGeometry)
        XCTAssertFalse(ElementProperty.hint.isGeometry)
        XCTAssertFalse(ElementProperty.actions.isGeometry)
        XCTAssertFalse(ElementProperty.rotors.isGeometry)
    }

    func testElementPropertyAllCasesRoundTrip() throws {
        for property in ElementProperty.allCases {
            let data = try encoder.encode(property)
            let decoded = try decoder.decode(ElementProperty.self, from: data)
            XCTAssertEqual(decoded, property)
        }
    }

    func testElementUpdateRoundTrip() throws {
        let before = HeistElement(
            description: "Button",
            label: "Button",
            value: "A",
            identifier: nil,
            frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44,
            actions: []
        )
        let after = HeistElement(
            description: "Button",
            label: "Button",
            value: "B",
            identifier: nil,
            frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44,
            actions: []
        )
        let update = ElementUpdate(
            before: before,
            after: after,
            changes: [
                .value(old: "A", new: "B"),
                .value(old: nil, new: "active"),
            ]
        )
        let data = try encoder.encode(update)
        let decoded = try decoder.decode(ElementUpdate.self, from: data)
        XCTAssertEqual(decoded, update)
    }

    // MARK: - Wire Message Types

    func testClientWireMessageTypeAllCasesRoundTrip() throws {
        for messageType in ClientWireMessageType.allCases {
            let data = try encoder.encode(messageType)
            let decoded = try decoder.decode(ClientWireMessageType.self, from: data)
            XCTAssertEqual(decoded, messageType)
        }
    }

    func testServerWireMessageTypeAllCasesRoundTrip() throws {
        for messageType in ServerWireMessageType.allCases {
            let data = try encoder.encode(messageType)
            let decoded = try decoder.decode(ServerWireMessageType.self, from: data)
            XCTAssertEqual(decoded, messageType)
        }
    }

    // MARK: - TXTRecordKey

    func testTXTRecordKeyRawValues() {
        XCTAssertEqual(TXTRecordKey.simUDID.rawValue, "simudid")
        XCTAssertEqual(TXTRecordKey.installationId.rawValue, "installationid")
        XCTAssertEqual(TXTRecordKey.deviceName.rawValue, "devicename")
        XCTAssertEqual(TXTRecordKey.instanceId.rawValue, "instanceid")
        XCTAssertEqual(TXTRecordKey.transport.rawValue, "transport")
    }

    // MARK: - ErrorKind

    func testErrorKindAllCasesRoundTrip() throws {
        for kind in ErrorKind.allCases {
            let data = try encoder.encode(kind)
            let decoded = try decoder.decode(ErrorKind.self, from: data)
            XCTAssertEqual(decoded, kind)
        }
    }

    // MARK: - WaitTarget

    func testWaitTargetRoundTrip() throws {
        let target = WaitTarget(
            predicate: .missing(.label("loading")),
            timeout: 15
        )
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(WaitTarget.self, from: data)
        XCTAssertEqual(decoded.predicate, .missing(.label("loading")))
        XCTAssertEqual(decoded.timeout, 15)
    }

    func testWaitTargetResolvedDefaults() {
        let target = WaitTarget(predicate: .exists(.label("x")))
        XCTAssertEqual(target.resolvedTimeout, defaultWaitTimeout)
    }

    func testWaitTargetRejectsTimeoutAboveMaximum() {
        let json = #"{"predicate":{"type":"exists","target":{"checks":[{"kind":"label","match":{"mode":"exact","value":"x"}}]}},"timeout":61}"#

        XCTAssertThrowsError(try decoder.decode(WaitTarget.self, from: Data(json.utf8))) { error in
            assertDecodingError(error, contains: ["wait timeout must be"])
        }
    }

    func testWaitTargetChangedResolvedDefaults() {
        let target = WaitTarget(predicate: .changed(.elements()))
        XCTAssertEqual(target.resolvedTimeout, defaultWaitTimeout)
    }

    private func assertDecodingError(
        _ error: Error,
        contains fragments: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case DecodingError.dataCorrupted(let context) = error else {
            XCTFail("Expected DecodingError.dataCorrupted, got \(error)", file: file, line: line)
            return
        }
        for fragment in fragments {
            XCTAssertTrue(
                context.debugDescription.contains(fragment),
                context.debugDescription,
                file: file,
                line: line
            )
        }
    }

    private func assertErrorDescription(
        _ error: Error,
        contains fragments: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let description = "\(error)"
        for fragment in fragments {
            XCTAssertTrue(
                description.contains(fragment),
                description,
                file: file,
                line: line
            )
        }
    }

    private struct HeistCaseMatchResultPayload: Encodable {
        let predicate: AccessibilityPredicate
        let result: ExpectationResult
    }
}
