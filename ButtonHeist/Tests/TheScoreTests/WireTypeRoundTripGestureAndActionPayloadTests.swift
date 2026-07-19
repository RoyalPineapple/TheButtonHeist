import ButtonHeistTestSupport
import XCTest
import ThePlans
import AccessibilitySnapshotModel
@_spi(ButtonHeistInternals) @testable import TheScore

extension WireTypeRoundTripTests {
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
            SwipeTarget(selection: .pointDirection(
                start: ScreenPoint(x: 10, y: 20),
                direction: .down
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
}
