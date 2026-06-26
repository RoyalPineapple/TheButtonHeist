import XCTest
import ThePlans
import AccessibilitySnapshotModel
@_spi(ButtonHeistInternals) @testable import TheScore

// MARK: - Wire Type Codable Round-Trip Tests

final class WireTypeRoundTripTests: XCTestCase {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

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
        let data = Data(#"{"text":"hello","foo":"bar"}"#.utf8)
        XCTAssertThrowsError(try decoder.decode(TypeTextTarget.self, from: data)) { error in
            assertDecodingError(error, contains: [#"Unknown type text target field "foo""#])
        }
    }

    func testTypeTextStringRefLoweringRejectsEmptyResolvedText() throws {
        let command = HeistActionCommand.typeText(
            text: .ref("item"),
            target: .target(.predicate(ElementPredicate(label: "Add item")))
        )

        XCTAssertThrowsError(try command.resolve(in: HeistExecutionEnvironment(strings: ["item": ""]))) { error in
            XCTAssertEqual(error as? TypeTextTargetError, .emptyText)
        }
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
            settleMs: 74,
            finalSemanticEvidenceMs: 23,
            receiptGenerationMs: 0,
            totalMs: 116
        )

        let data = try encoder.encode(timing)
        let decoded = try decoder.decode(ActionPerformanceTiming.self, from: data)

        XCTAssertEqual(decoded, timing)
    }

    func testActionPerformanceTimingDecodesPartialPayload() throws {
        let json = #"{"settleMs":74}"#

        let decoded = try decoder.decode(ActionPerformanceTiming.self, from: Data(json.utf8))

        XCTAssertEqual(decoded, ActionPerformanceTiming(settleMs: 74))
    }

    func testActionResultRoundTripPreservesTiming() throws {
        let timing = ActionPerformanceTiming(
            beforeObservationMs: 5,
            targetResolutionMs: 0,
            actionDispatchMs: 2,
            interactionMs: 12,
            settleMs: 74,
            finalSemanticEvidenceMs: 23,
            receiptGenerationMs: 0,
            totalMs: 116
        )
        let result = ActionResult(
            success: true,
            method: .activate,
            message: "activated",
            timing: timing
        )

        let data = try encoder.encode(result)
        let decoded = try decoder.decode(ActionResult.self, from: data)

        XCTAssertEqual(decoded, result)
        XCTAssertEqual(decoded.timing, timing)
    }

    // MARK: - CustomActionTarget

    func testCustomActionTargetRoundTrip() throws {
        let target = CustomActionTarget(
            elementTarget: .predicate(ElementPredicate(label: "btn_save")),
            actionName: "Delete Item"
        )
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(CustomActionTarget.self, from: data)
        XCTAssertEqual(decoded, CustomActionTarget(elementTarget: .predicate(ElementPredicate(label: "btn_save")), actionName: "Delete Item"))
        XCTAssertEqual(decoded.actionName, "Delete Item")
    }

    func testCustomActionTargetWithMatcher() throws {
        let target = CustomActionTarget(
            elementTarget: .predicate(ElementPredicate(label: "Menu")),
            actionName: "Open Submenu"
        )
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(CustomActionTarget.self, from: data)
        XCTAssertEqual(decoded, CustomActionTarget(
            elementTarget: .predicate(ElementPredicate(label: "Menu")),
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
            selection: .element(.predicate(ElementPredicate(label: "cell_1"))),
            duration: GestureDuration(seconds: 1.5)
        )
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(LongPressTarget.self, from: data)
        XCTAssertEqual(decoded.selection, .element(.predicate(ElementPredicate(label: "cell_1"))))
        XCTAssertEqual(decoded.duration.seconds, 1.5)
    }

    func testLongPressTargetWithPointRoundTrip() throws {
        let target = LongPressTarget(
            selection: .coordinate(ScreenPoint(x: 100, y: 200)),
            duration: GestureDuration(seconds: 0.8)
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
            XCTAssertTrue("\(error)".contains("duration must be number in 0...60.0"), "\(error)")
        }
    }

    func testTapAndLongPressRejectMixedPointAndElementIntents() {
        let tapJSON = #"{"element":{"label":"Save"},"point":{"x":10,"y":20}}"#
        XCTAssertThrowsError(try decoder.decode(TapTarget.self, from: Data(tapJSON.utf8))) { error in
            assertErrorDescription(error, contains: ["accepts element, element with unitPoint, or ScreenPoint"])
        }

        let longPressJSON = #"{"element":{"label":"Save"},"point":{"x":10,"y":20},"duration":1}"#
        XCTAssertThrowsError(try decoder.decode(LongPressTarget.self, from: Data(longPressJSON.utf8))) { error in
            assertErrorDescription(error, contains: ["accepts element, element with unitPoint, or ScreenPoint"])
        }
    }

    func testSwipeAndDragRejectInvalidDurationAtDecode() {
        let swipeJSON = #"{"pointDirection":{"start":{"x":10,"y":20},"direction":"down"},"duration":0}"#
        XCTAssertThrowsError(try decoder.decode(SwipeTarget.self, from: Data(swipeJSON.utf8))) { error in
            XCTAssertTrue("\(error)".contains("duration must be number > 0"), "\(error)")
        }

        let dragJSON = #"{"pointToPoint":{"start":{"x":10,"y":20},"end":{"x":30,"y":40}},"duration":61}"#
        XCTAssertThrowsError(try decoder.decode(DragTarget.self, from: Data(dragJSON.utf8))) { error in
            XCTAssertTrue("\(error)".contains("duration must be number in 0...60.0"), "\(error)")
        }
    }

    // MARK: - DragTarget

    func testDragTargetRoundTrip() throws {
        let target = DragTarget(
            start: .element(.predicate(ElementPredicate(label: "handle"))),
            end: ScreenPoint(x: 200, y: 300),
            duration: GestureDuration(seconds: 0.8)
        )
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(DragTarget.self, from: data)
        XCTAssertEqual(decoded.start, .element(.predicate(ElementPredicate(label: "handle"))))
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
          "elementToPoint": {"element": {"label": "Card"}, "end": {"x": 30, "y": 40}},
          "pointToPoint": {"start": {"x": 10, "y": 20}, "end": {"x": 30, "y": 40}}
        }
        """#

        XCTAssertThrowsError(try decoder.decode(DragTarget.self, from: Data(json.utf8))) { error in
            assertErrorDescription(error, contains: ["drag accepts exactly one gesture intent"])
        }
    }

    func testDragTargetRejectsUnknownNestedIntentField() {
        let json = #"{"elementToPoint":{"element":{"label":"Handle"},"end":{"x":30,"y":40},"offset":{"x":10,"y":20}}}"#
        XCTAssertThrowsError(try decoder.decode(DragTarget.self, from: Data(json.utf8))) { error in
            assertDecodingError(error, contains: ["Unknown element-to-point drag field", "offset"])
        }
    }

    func testGestureResolvedDefaultsAreContractOwned() {
        XCTAssertEqual(
            SwipeTarget(selection: .point(start: .element(.predicate(ElementPredicate(label: "list"))), destination: .direction(.down))).resolvedDuration,
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
            selection: .element(.predicate(ElementPredicate(label: "list"))),
            direction: .down
        )
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(ScrollTarget.self, from: data)
        XCTAssertEqual(decoded.selection, .element(.predicate(ElementPredicate(label: "list"))))
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
        let data = Data(#"{"container":"main_scroll","direction":"up"}"#.utf8)
        let decoded = try decoder.decode(ScrollTarget.self, from: data)

        XCTAssertEqual(decoded.selection, .container("main_scroll"))
        XCTAssertEqual(decoded.direction, .up)
    }

    func testScrollTargetRejectsContainerObject() throws {
        let data = Data(#"{"container":{"containerName":"main_scroll"},"direction":"up"}"#.utf8)
        XCTAssertThrowsError(try decoder.decode(ScrollTarget.self, from: data)) { error in
            XCTAssertTrue("\(error)".contains("Expected to decode String"), "\(error)")
        }
    }

    func testScrollTargetRejectsUnknownPayloadKey() throws {
        let data = Data(#"{"direction":"down","foo":"bar"}"#.utf8)
        XCTAssertThrowsError(try decoder.decode(ScrollTarget.self, from: data)) { error in
            assertDecodingError(error, contains: [#"Unknown scroll target field "foo""#])
        }
    }

    func testScrollTargetRejectsContainerNamePayloadKey() throws {
        let data = Data(#"{"direction":"down","containerName":"main_scroll"}"#.utf8)
        XCTAssertThrowsError(try decoder.decode(ScrollTarget.self, from: data)) { error in
            assertDecodingError(error, contains: [#"Unknown scroll target field "containerName""#])
        }
    }

    func testScrollPrimitiveRequestEnvelopeIsRejected() throws {
        let data = Data("""
        {"buttonHeistVersion":"\(buttonHeistVersion)","type":"scroll","payload":{"direction":"down","containerName":"main_scroll"}}
        """.utf8)
        XCTAssertThrowsError(try decoder.decode(RequestEnvelope.self, from: data)) { error in
            assertDecodingError(error, contains: ["Unsupported client wire message type"])
        }
    }

    // MARK: - ScrollToEdgeTarget

    func testScrollToEdgeTargetAllEdges() throws {
        for edge in ScrollEdge.allCases {
            let target = ScrollToEdgeTarget(
                selection: .element(.predicate(ElementPredicate(label: "scroll_view"))),
                edge: edge
            )
            let data = try encoder.encode(target)
            let decoded = try decoder.decode(ScrollToEdgeTarget.self, from: data)
            XCTAssertEqual(decoded.edge, edge)
            XCTAssertEqual(decoded.selection, .element(.predicate(ElementPredicate(label: "scroll_view"))))
        }
    }

    func testScrollToEdgeTargetAcceptsContainerNameString() throws {
        let data = Data(#"{"container":"main_scroll","edge":"bottom"}"#.utf8)
        let decoded = try decoder.decode(ScrollToEdgeTarget.self, from: data)

        XCTAssertEqual(decoded.selection, .container("main_scroll"))
        XCTAssertEqual(decoded.edge, .bottom)
    }

    func testScrollToEdgeTargetRejectsContainerObject() throws {
        let data = Data(#"{"container":{"containerName":"main_scroll"},"edge":"bottom"}"#.utf8)
        XCTAssertThrowsError(try decoder.decode(ScrollToEdgeTarget.self, from: data)) { error in
            XCTAssertTrue("\(error)".contains("Expected to decode String"), "\(error)")
        }
    }

    func testScrollToEdgeTargetRejectsUnknownPayloadKey() throws {
        let data = Data(#"{"edge":"bottom","foo":"bar"}"#.utf8)
        XCTAssertThrowsError(try decoder.decode(ScrollToEdgeTarget.self, from: data)) { error in
            assertDecodingError(error, contains: [#"Unknown scroll_to_edge target field "foo""#])
        }
    }

    func testScrollToEdgeTargetRejectsContainerNamePayloadKey() throws {
        let data = Data(#"{"edge":"bottom","containerName":"main_scroll"}"#.utf8)
        XCTAssertThrowsError(try decoder.decode(ScrollToEdgeTarget.self, from: data)) { error in
            assertDecodingError(error, contains: [#"Unknown scroll_to_edge target field "containerName""#])
        }
    }

    func testScrollToEdgePrimitiveRequestEnvelopeIsRejected() throws {
        let data = Data("""
        {"buttonHeistVersion":"\(buttonHeistVersion)","type":"scrollToEdge","payload":{"edge":"bottom","unexpected":"main_scroll"}}
        """.utf8)
        XCTAssertThrowsError(try decoder.decode(RequestEnvelope.self, from: data)) { error in
            assertDecodingError(error, contains: ["Unsupported client wire message type"])
        }
    }

    // MARK: - ProtocolMismatchPayload

    func testProtocolMismatchPayloadRoundTrip() throws {
        let payload = ProtocolMismatchPayload(
            serverButtonHeistVersion: "2026.05.09",
            clientButtonHeistVersion: "2026.05.08"
        )
        let data = try encoder.encode(payload)
        let decoded = try decoder.decode(ProtocolMismatchPayload.self, from: data)
        XCTAssertEqual(decoded.serverButtonHeistVersion, "2026.05.09")
        XCTAssertEqual(decoded.clientButtonHeistVersion, "2026.05.08")
    }

    // MARK: - AccessibilityContainer

    func testAccessibilityContainerRoundTrip() throws {
        let container = makeTestAccessibilityContainer(
            type: .scrollable(contentSize: AccessibilitySize(width: 390, height: 1000)),
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
            type: .semanticGroup(label: "Settings", value: nil, identifier: "settings"),
            frameWidth: 390,
            frameHeight: 100
        )
        let data = try encoder.encode(container)
        let decoded = try decoder.decode(AccessibilityContainer.self, from: data)
        XCTAssertEqual(decoded, container)
    }

    func testAccessibilityContainerModalBoundaryRoundTrip() throws {
        let container = makeTestAccessibilityContainer(
            type: .semanticGroup(label: "Alert", value: nil, identifier: nil),
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

    // MARK: - SubtreeSelector

    func testSubtreeSelectorElementUsesToolSchemaShape() throws {
        let selector = SubtreeSelector.element(
            .predicate(ElementPredicate(label: "Save", traits: [.button]), ordinal: 2)
        )

        let data = try encoder.encode(selector)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(payload["ordinal"] as? Int, 2)
        let element = try XCTUnwrap(payload["element"] as? [String: Any])
        XCTAssertNil(payload["container"])
        XCTAssertNil(element["heistId"])
        let checks = try XCTUnwrap(element["checks"] as? [[String: Any]])
        XCTAssertEqual(checks.count, 2)
        XCTAssertEqual(checks[0]["kind"] as? String, "label")
        XCTAssertEqual(checks[0]["match"] as? String, "Save")
        XCTAssertEqual(checks[1]["kind"] as? String, "traits")
        XCTAssertEqual(checks[1]["values"] as? [String], ["button"])
        XCTAssertEqual(try decoder.decode(SubtreeSelector.self, from: data), selector)
    }

    func testSubtreeSelectorElementPredicateShape() throws {
        let selector = SubtreeSelector.element(.predicate(ElementPredicate(label: "Save")))

        let data = try encoder.encode(selector)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(payload["ordinal"])
        let element = try XCTUnwrap(payload["element"] as? [String: Any])
        XCTAssertNil(element["heistId"])
        let checks = try XCTUnwrap(element["checks"] as? [[String: Any]])
        XCTAssertEqual(checks.count, 1)
        XCTAssertEqual(checks[0]["kind"] as? String, "label")
        XCTAssertEqual(checks[0]["match"] as? String, "Save")
        XCTAssertEqual(try decoder.decode(SubtreeSelector.self, from: data), selector)
    }

    func testSubtreeSelectorContainerUsesToolSchemaShape() throws {
        let selector = SubtreeSelector.container(
            ContainerMatcher(containerName: "semantic_actions", type: .semanticGroup, label: "Actions"),
            ordinal: 1
        )

        let data = try encoder.encode(selector)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(payload["ordinal"] as? Int, 1)
        let container = try XCTUnwrap(payload["container"] as? [String: Any])
        XCTAssertNil(payload["element"])
        XCTAssertEqual(container["containerName"] as? String, "semantic_actions")
        XCTAssertEqual(container["type"] as? String, "semanticGroup")
        XCTAssertEqual(container["label"] as? String, "Actions")
        XCTAssertEqual(try decoder.decode(SubtreeSelector.self, from: data), selector)
    }

    func testSubtreeSelectorContainerRequiresMatcherObject() throws {
        // The MCP schema advertises subtree.container as an object-only matcher
        // (no oneOf string/object adapter), so a bare string container name is
        // no longer accepted at the wire boundary.
        let data = Data(#"{"container":"semantic_actions"}"#.utf8)
        XCTAssertThrowsError(try decoder.decode(SubtreeSelector.self, from: data))
    }

    func testSubtreeSelectorContainerAcceptsMatcherObject() throws {
        let data = Data(#"{"container":{"containerName":"semantic_actions"}}"#.utf8)
        let decoded = try decoder.decode(SubtreeSelector.self, from: data)

        XCTAssertEqual(decoded, .container(ContainerMatcher(containerName: "semantic_actions")))
    }

    func testSubtreeSelectorElementRejectsHeistIdField() {
        // heistId is no longer a targeting field — it is an unknown element key.
        let json = #"{"element":{"heistId":"button_save","label":"Save"}}"#
        XCTAssertThrowsError(try decoder.decode(SubtreeSelector.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("heistId"), "\(error)")
        }
    }

    func testSubtreeSelectorElementRejectsHeistIdOnlyField() {
        let json = #"{"element":{"heistId":"button_save"},"ordinal":1}"#
        XCTAssertThrowsError(try decoder.decode(SubtreeSelector.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("heistId"), "\(error)")
        }
    }

    func testSubtreeSelectorElementRejectsUnknownTargetField() {
        let json = #"{"element":{"label":"Save","unexpectedTargetField":"button_save"}}"#
        XCTAssertThrowsError(try decoder.decode(SubtreeSelector.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("unexpectedTargetField"), "\(error)")
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
            type: .semanticGroup(label: nil, value: nil, identifier: nil),
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
                    command: .activate(.predicate(ElementPredicateTemplate(label: .exact(.literal("Settings")), traits: [.button]), ordinal: 1)),
                    expectation: WaitStep(predicate: .change(.screen()), timeout: 2.5)
                )),
                .action(try ActionStep(
                    command: .setPasteboard(SetPasteboardTarget(text: "ready"))
                )),
                .warn(WarnStep(message: "optional step skipped")),
                .fail(FailStep(message: "unexpected state"))
            ]
        )

        let data = try encoder.encode(plan)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(payload["version"] as? Int, HeistPlan.currentVersion)
        let body = try XCTUnwrap(payload["body"] as? [[String: Any]])
        XCTAssertEqual(body.count, 4)
        XCTAssertEqual(body[0]["type"] as? String, "action")
        let action = try XCTUnwrap(body[0]["action"] as? [String: Any])
        let command = try XCTUnwrap(action["command"] as? [String: Any])
        XCTAssertEqual(command["type"] as? String, "activate")
        let target = try XCTUnwrap(command["payload"] as? [String: Any])
        XCTAssertEqual(target["ordinal"] as? Int, 1)
        let checks = try XCTUnwrap(target["checks"] as? [[String: Any]])
        XCTAssertEqual(checks.count, 2)
        XCTAssertEqual(checks[0]["kind"] as? String, "label")
        XCTAssertEqual(checks[0]["match"] as? String, "Settings")
        XCTAssertEqual(checks[1]["kind"] as? String, "traits")
        XCTAssertEqual(checks[1]["values"] as? [String], ["button"])
        let predicate = try XCTUnwrap((action["expectation"] as? [String: Any])?["predicate"] as? [String: Any])
        XCTAssertEqual(predicate["type"] as? String, "change")
        let scopes = try XCTUnwrap(predicate["scopes"] as? [[String: Any]])
        XCTAssertEqual(scopes.first?["type"] as? String, "screen")
        XCTAssertEqual((action["expectation"] as? [String: Any])?["timeout"] as? Double, 2.5)
        XCTAssertEqual((body[2]["warn"] as? [String: Any])?["message"] as? String, "optional step skipped")
        XCTAssertEqual((body[3]["fail"] as? [String: Any])?["message"] as? String, "unexpected state")

        let decoded = try decoder.decode(HeistPlan.self, from: data)
        XCTAssertEqual(decoded, plan)
    }

    func testHeistExecutionResultRoundTripPreservesActionFailureDiagnostics() throws {
        let command = HeistActionCommand.activate(.target(.predicate(ElementPredicate(label: "Save"))))
        let result = HeistExecutionResult(
            steps: [
                HeistExecutionStepResult(
                    path: "$.body[0]",
                    kind: .action,
                    status: .failed,
                    durationMs: 0,
                    intent: .action(command: "activate", target: "predicate(label=\"Save\")"),
                    evidence: .action(HeistActionEvidence(
                        command: command,
                        actionResult: ActionResult(
                            success: false,
                            method: .activate,
                            message: "No element matching label \"Save\"",
                            errorKind: .elementNotFound
                        )
                    )),
                    failure: HeistFailureDetail(
                        category: .targetResolution,
                        contract: "action dispatch succeeds",
                        observed: "No element matching label \"Save\"",
                        expected: "predicate(label=\"Save\")"
                    )
                ),
            ],
            durationMs: 1,
            abortedAtPath: "$.body[0]"
        )

        let data = try encoder.encode(result)
        let decoded = try decoder.decode(HeistExecutionResult.self, from: data)

        XCTAssertEqual(decoded.abortedAtPath, "$.body[0]")
        XCTAssertEqual(decoded.steps.count, 1)
        XCTAssertEqual(decoded.steps[0].status, .failed)
        XCTAssertEqual(decoded.steps[0].actionEvidence?.command?.wireType, .activate)
        XCTAssertEqual(decoded.steps[0].actionEvidence?.command?.reportTarget, .predicate(ElementPredicate(label: "Save")))
        XCTAssertEqual(decoded.steps[0].actionEvidence?.actionResult?.method, .activate)
        XCTAssertEqual(decoded.steps[0].actionEvidence?.actionResult?.errorKind, .elementNotFound)
        XCTAssertEqual(
            decoded.steps[0].actionEvidence?.actionResult?.message,
            "No element matching label \"Save\""
        )
        XCTAssertEqual(decoded.steps[0].failure?.category, .targetResolution)
    }

    func testHeistExecutionResultRoundTripPreservesForEachResult() throws {
        let matching = ElementPredicate(label: "Row")
        let result = HeistExecutionResult(
            steps: [
                HeistExecutionStepResult(
                    path: "$.body[0]",
                    kind: .forEachElement,
                    status: .passed,
                    durationMs: 500,
                    intent: .forEachElement(parameter: "row", matching: matching.description, limit: 10),
                    evidence: .forEachElement(HeistForEachElementEvidence(
                        parameter: "row",
                        matching: matching,
                        limit: 10,
                        matchedCount: 3,
                        iterationCount: 3
                    )),
                    children: [
                        forEachElementIteration(index: 0, durationMs: 50, matching: matching),
                        forEachElementIteration(index: 1, durationMs: 45, matching: matching),
                        forEachElementIteration(index: 2, durationMs: 40, matching: matching),
                    ]
                ),
            ],
            durationMs: 500
        )

        let data = try encoder.encode(result)
        let decoded = try decoder.decode(HeistExecutionResult.self, from: data)

        XCTAssertNil(decoded.abortedAtPath)
        let step = try XCTUnwrap(decoded.steps.first)
        XCTAssertEqual(step.kind, .forEachElement)
        XCTAssertEqual(step.forEachElementEvidence?.matchedCount, 3)
        XCTAssertEqual(step.forEachElementEvidence?.limit, 10)
        XCTAssertEqual(step.forEachElementEvidence?.iterationCount, 3)
        XCTAssertNil(step.forEachElementEvidence?.failureReason)
        XCTAssertEqual(step.children.map(\.kind), [.forEachIteration, .forEachIteration, .forEachIteration])
        XCTAssertEqual(step.children.first?.children.first?.actionEvidence?.actionResult?.method, .activate)
        XCTAssertFalse(step.isFailure)

        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let steps = try XCTUnwrap(payload["steps"] as? [[String: Any]])
        XCTAssertEqual(steps.first?["kind"] as? String, "for_each_element")
        XCTAssertNil(steps.first?["childResults"])
        XCTAssertNotNil(steps.first?["children"])
    }

    func testHeistExecutionResultRoundTripPreservesForEachFailure() throws {
        let result = HeistExecutionResult(
            steps: [
                HeistExecutionStepResult(
                    path: "$.body[0]",
                    kind: .forEachElement,
                    status: .failed,
                    durationMs: 200,
                    intent: .forEachElement(parameter: "row", matching: "predicate(label=\"Row\")", limit: 10),
                    evidence: .forEachElement(HeistForEachElementEvidence(
                        parameter: "row",
                        matching: ElementPredicate(label: "Row"),
                        limit: 10,
                        matchedCount: 5,
                        iterationCount: 2,
                        failureReason: "child step failed at iteration 2"
                    )),
                    failure: HeistFailureDetail(
                        category: .loop,
                        contract: "for_each_element completes all matched iterations",
                        observed: "child step failed at iteration 2",
                        expected: "5 iteration(s)"
                    )
                ),
            ],
            durationMs: 200,
            abortedAtPath: "$.body[0]"
        )

        let data = try encoder.encode(result)
        let decoded = try decoder.decode(HeistExecutionResult.self, from: data)

        XCTAssertEqual(decoded.abortedAtPath, "$.body[0]")
        let step = try XCTUnwrap(decoded.steps.first)
        XCTAssertEqual(step.forEachElementEvidence?.failureReason, "child step failed at iteration 2")
        XCTAssertTrue(step.isFailure)
    }

    func testHeistExecutionResultRoundTripPreservesCaseSelectionAndChildren() throws {
        let predicate = AccessibilityPredicate.state(.exists(ElementPredicate(label: "Home")))
        let child = HeistExecutionStepResult(
            path: "$.body[0].conditional.cases[0].body[0]",
            kind: .action,
            status: .failed,
            durationMs: 4,
            evidence: .action(HeistActionEvidence(
                command: nil,
                actionResult: ActionResult(
                    success: false,
                    method: .activate,
                    message: "button disabled",
                    errorKind: .actionFailed
                )
            )),
            failure: HeistFailureDetail(
                category: .action,
                contract: "action dispatch succeeds",
                observed: "button disabled"
            )
        )
        let result = HeistExecutionResult(
            steps: [
                HeistExecutionStepResult(
                    path: "$.body[0]",
                    kind: .conditional,
                    status: .failed,
                    durationMs: 6,
                    intent: .conditional,
                    evidence: .caseSelection(HeistCaseSelectionEvidence(selection: HeistCaseSelectionResult(
                        cases: [
                            HeistCaseMatchResult(
                                predicate: predicate,
                                result: ExpectationResult(met: true, predicate: predicate)
                            ),
                        ],
                        outcome: .matchedCase(index: 0),
                        elapsedMs: 2,
                        lastObservedSummary: "screen: login; known: 3 elements"
                    ))),
                    failure: HeistFailureDetail(
                        category: .invocation,
                        contract: "child execution completes without failure",
                        observed: "child failed at \(child.path)"
                    ),
                    abortedAtChildPath: child.path,
                    children: [child]
                ),
            ],
            durationMs: 7,
            abortedAtPath: child.path
        )

        let data = try encoder.encode(result)
        let decoded = try decoder.decode(HeistExecutionResult.self, from: data)

        let decodedStep = try XCTUnwrap(decoded.steps.first)
        XCTAssertEqual(decodedStep.caseSelectionEvidence?.selection.cases.first?.predicate, predicate)
        XCTAssertEqual(decodedStep.caseSelectionEvidence?.selection.cases.first?.result.met, true)
        XCTAssertEqual(decodedStep.caseSelectionEvidence?.selection.outcome, .matchedCase(index: 0))
        XCTAssertEqual(decodedStep.children.first?.actionEvidence?.actionResult?.errorKind, .actionFailed)
        XCTAssertTrue(decodedStep.children.first?.isFailure == true)
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
        XCTAssertThrowsError(try decoder.decode(HeistCaseSelectionResult.self, from: Data(looseOutcome.utf8))) { error in
            assertDecodingError(error, contains: ["no_match", "index"])
        }
    }

    private func forEachElementIteration(
        index: Int,
        durationMs: Int,
        matching: ElementPredicate
    ) -> HeistExecutionStepResult {
        let path = "$.body[0].for_each_element.iterations[\(index)]"
        return HeistExecutionStepResult(
            path: path,
            kind: .forEachIteration,
            status: .passed,
            durationMs: durationMs,
            intent: .forEachElement(parameter: "row", matching: matching.description, limit: 10),
            evidence: .forEachElement(HeistForEachElementEvidence(
                parameter: "row",
                matching: matching,
                limit: 10,
                matchedCount: 3,
                iterationCount: index + 1,
                iterationOrdinal: index,
                targetOrdinal: index,
                targetSummary: "predicate(label=\"Row\", ordinal: \(index))"
            )),
            children: [
                HeistExecutionStepResult(
                    path: "\(path).body[0]",
                    kind: .action,
                    status: .passed,
                    durationMs: durationMs,
                    evidence: .action(HeistActionEvidence(
                        command: nil,
                        actionResult: ActionResult(success: true, method: .activate, message: "activated")
                    ))
                ),
            ]
        )
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

    // MARK: - AccessibilityTrace.Delta
    //
    // Coverage lives in AccessibilityTraceDeltaRoundTripTests.swift — this file's
    // generic round-trip suite is for shapes without per-case Codable.

    // MARK: - PropertyChange / ElementUpdate

    func testPropertyChangeRoundTrip() throws {
        let change = PropertyChange(property: .value, old: "OK", new: "Cancel")
        let data = try encoder.encode(change)
        let decoded = try decoder.decode(PropertyChange.self, from: data)
        XCTAssertEqual(decoded, change)
    }

    func testElementPropertyIsGeometry() {
        XCTAssertTrue(ElementProperty.frame.isGeometry)
        XCTAssertTrue(ElementProperty.activationPoint.isGeometry)
        XCTAssertFalse(ElementProperty.value.isGeometry)
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
        // The carried element's heistId is excluded from the wire (decodes to ""),
        // so build the expectation with an empty heistId for round-trip equality.
        let update = ElementUpdate(
            element: HeistElement(
                description: "Button",
                label: "Button",
                value: nil,
                identifier: nil,
                frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44,
                actions: []
            ),
            changes: [
                PropertyChange(property: .value, old: "A", new: "B"),
                PropertyChange(property: .value, old: nil, new: "active"),
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

    // MARK: - EnvironmentKey

    func testEnvironmentKeyRawValues() {
        XCTAssertEqual(EnvironmentKey.buttonheistDevice.rawValue, "BUTTONHEIST_DEVICE")
        XCTAssertEqual(EnvironmentKey.buttonheistToken.rawValue, "BUTTONHEIST_TOKEN")
        XCTAssertEqual(EnvironmentKey.insideJobToken.rawValue, "INSIDEJOB_TOKEN")
        XCTAssertEqual(EnvironmentKey.insideJobPort.rawValue, "INSIDEJOB_PORT")
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
            predicate: .state(.missing(ElementPredicate(label: "loading"))),
            timeout: 15
        )
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(WaitTarget.self, from: data)
        XCTAssertEqual(decoded.predicate, .state(.missing(ElementPredicate(label: "loading"))))
        XCTAssertEqual(decoded.timeout, 15)
    }

    func testWaitTargetResolvedDefaults() {
        let target = WaitTarget(predicate: .state(.exists(ElementPredicate(label: "x"))))
        XCTAssertEqual(target.resolvedTimeout, defaultWaitTimeout)
    }

    func testWaitTargetTimeoutCapsAt30() {
        let target = WaitTarget(predicate: .state(.exists(ElementPredicate(label: "x"))), timeout: 60)
        XCTAssertEqual(target.resolvedTimeout, defaultWaitTimeout)
    }

    func testWaitTargetChangedResolvedDefaults() {
        let target = WaitTarget(predicate: .change(.elements()))
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
}
