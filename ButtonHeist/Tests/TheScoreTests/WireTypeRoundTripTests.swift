import XCTest
import AccessibilitySnapshotModel
@testable import TheScore

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

    // MARK: - CustomActionTarget

    func testCustomActionTargetRoundTrip() throws {
        let target = CustomActionTarget(
            elementTarget: .heistId("btn_save"),
            actionName: "Delete Item"
        )
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(CustomActionTarget.self, from: data)
        XCTAssertEqual(decoded.selection, .element(.heistId("btn_save"), actionName: "Delete Item"))
        XCTAssertEqual(decoded.actionName, "Delete Item")
    }

    func testCustomActionTargetWithMatcher() throws {
        let target = CustomActionTarget(
            elementTarget: .matcher(ElementMatcher(label: "Menu")),
            actionName: "Open Submenu"
        )
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(CustomActionTarget.self, from: data)
        XCTAssertEqual(decoded.selection, .element(.matcher(ElementMatcher(label: "Menu")), actionName: "Open Submenu"))
        XCTAssertEqual(decoded.actionName, "Open Submenu")
    }

    func testCustomActionTargetWithContainerRoundTrip() throws {
        let target = CustomActionTarget(
            containerTarget: ContainerMatcher(stableId: "semantic_actions__actions"),
            actionName: "Dismiss"
        )
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(CustomActionTarget.self, from: data)
        XCTAssertEqual(
            decoded.selection,
            .container(ContainerMatcher(stableId: "semantic_actions__actions"), ordinal: nil, actionName: "Dismiss")
        )
        XCTAssertEqual(decoded.actionName, "Dismiss")
    }

    func testCustomActionTargetRejectsContainerOrdinalOnly() throws {
        let target = CustomActionTarget(
            containerTarget: ContainerMatcher(),
            ordinal: 1,
            actionName: "Dismiss"
        )

        XCTAssertThrowsError(try encoder.encode(target)) { error in
            guard case EncodingError.invalidValue = error else {
                return XCTFail("Expected invalidValue, got \(error)")
            }
            XCTAssertTrue("\(error)".contains("ordinal only disambiguates"))
        }
    }

    // MARK: - LongPressTarget

    func testLongPressTargetRoundTrip() throws {
        let target = LongPressTarget(
            selection: .element(.heistId("cell_1")),
            duration: 1.5
        )
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(LongPressTarget.self, from: data)
        XCTAssertEqual(decoded.selection, .element(.heistId("cell_1")))
        XCTAssertEqual(decoded.duration, 1.5)
    }

    func testLongPressTargetWithPointRoundTrip() throws {
        let target = LongPressTarget(selection: .coordinate(ScreenPoint(x: 100, y: 200)), duration: 0.8)
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(LongPressTarget.self, from: data)
        XCTAssertEqual(decoded.selection, .coordinate(ScreenPoint(x: 100, y: 200)))
        XCTAssertEqual(decoded.duration, 0.8)
    }

    func testLongPressTargetDefaultDuration() {
        let target = LongPressTarget(selection: .coordinate(ScreenPoint(x: 10, y: 20)))
        XCTAssertEqual(target.duration, 0.5)
    }

    // MARK: - DragTarget

    func testDragTargetRoundTrip() throws {
        let target = DragTarget(
            start: .element(.heistId("handle")),
            end: ScreenPoint(x: 200, y: 300),
            duration: 0.8
        )
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(DragTarget.self, from: data)
        XCTAssertEqual(decoded.start, .element(.heistId("handle")))
        XCTAssertEqual(decoded.end, ScreenPoint(x: 200, y: 300))
        XCTAssertEqual(decoded.duration, 0.8)
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
        let json = #"{"startX":10,"startY":20,"endX":30,"endY":40,"unexpected":true}"#
        XCTAssertThrowsError(try decoder.decode(DragTarget.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("Unknown drag target field"), "\(error)")
            XCTAssertTrue("\(error)".contains("unexpected"), "\(error)")
        }
    }

    func testSwipeTargetRejectsUnknownField() {
        let json = #"{"heistId":"list","direction":"down","unexpected":true}"#
        XCTAssertThrowsError(try decoder.decode(SwipeTarget.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("Unknown swipe target field"), "\(error)")
            XCTAssertTrue("\(error)".contains("unexpected"), "\(error)")
        }
    }

    func testGestureResolvedDefaultsAreContractOwned() {
        XCTAssertEqual(
            SwipeTarget(selection: .point(start: .element(.heistId("list")), destination: .direction(.down))).resolvedDuration,
            0.15
        )
        XCTAssertEqual(
            DragTarget(start: .coordinate(ScreenPoint(x: 10, y: 20)), end: ScreenPoint(x: 30, y: 40)).resolvedDuration,
            0.5
        )
        XCTAssertEqual(PinchTarget(center: .coordinate(ScreenPoint(x: 0, y: 0)), scale: 2).resolvedSpread, 100)
        XCTAssertEqual(PinchTarget(center: .coordinate(ScreenPoint(x: 0, y: 0)), scale: 2).resolvedDuration, 0.5)
        XCTAssertEqual(RotateTarget(center: .coordinate(ScreenPoint(x: 0, y: 0)), angle: 1).resolvedRadius, 100)
        XCTAssertEqual(RotateTarget(center: .coordinate(ScreenPoint(x: 0, y: 0)), angle: 1).resolvedDuration, 0.5)
        XCTAssertEqual(TwoFingerTapTarget(center: .coordinate(ScreenPoint(x: 0, y: 0))).resolvedSpread, 40)
        XCTAssertEqual(DrawBezierTarget(startX: 0, startY: 0, segments: []).resolvedSamplesPerSegment, 20)
        XCTAssertEqual(
            DrawBezierTarget(startX: 0, startY: 0, segments: [], samplesPerSegment: 5_000).resolvedSamplesPerSegment,
            1_000
        )
    }

    // MARK: - PinchTarget

    func testPinchTargetRoundTrip() throws {
        let target = PinchTarget(
            center: .element(.heistId("map")),
            scale: 2.0, spread: 100, duration: 0.5
        )
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(PinchTarget.self, from: data)
        XCTAssertEqual(decoded.center, GesturePointSelection.element(.heistId("map")))
        XCTAssertEqual(decoded.scale, 2.0)
        XCTAssertEqual(decoded.spread, 100)
        XCTAssertEqual(decoded.duration, 0.5)
    }

    func testPinchTargetCoordinateCenterRoundTrip() throws {
        let target = PinchTarget(center: .coordinate(ScreenPoint(x: 10, y: 20)), scale: 0.5)
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(PinchTarget.self, from: data)
        XCTAssertEqual(decoded.scale, 0.5)
        XCTAssertEqual(decoded.center, .coordinate(ScreenPoint(x: 10, y: 20)))
        XCTAssertNil(decoded.spread)
        XCTAssertNil(decoded.duration)
    }

    func testPinchTargetRejectsMissingCenter() {
        let json = #"{"scale":0.5}"#
        XCTAssertThrowsError(try decoder.decode(PinchTarget.self, from: Data(json.utf8)))
    }

    func testPinchTargetRejectsUnknownField() {
        let json = #"{"scale":0.5,"centerX":10,"centerY":20,"unexpectedScale":2}"#
        XCTAssertThrowsError(try decoder.decode(PinchTarget.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("Unknown pinch target field"), "\(error)")
        }
    }

    // MARK: - RotateTarget

    func testRotateTargetRoundTrip() throws {
        let target = RotateTarget(
            center: .element(.heistId("dial")),
            angle: .pi / 4, radius: 80, duration: 0.6
        )
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(RotateTarget.self, from: data)
        XCTAssertEqual(decoded.center, GesturePointSelection.element(.heistId("dial")))
        XCTAssertEqual(decoded.angle, .pi / 4)
        XCTAssertEqual(decoded.radius, 80)
        XCTAssertEqual(decoded.duration, 0.6)
    }

    func testRotateTargetCoordinateCenterRoundTrip() throws {
        let target = RotateTarget(center: .coordinate(ScreenPoint(x: 10, y: 20)), angle: 1.57)
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(RotateTarget.self, from: data)
        XCTAssertEqual(decoded.angle, 1.57)
        XCTAssertEqual(decoded.center, .coordinate(ScreenPoint(x: 10, y: 20)))
        XCTAssertNil(decoded.radius)
    }

    func testRotateTargetRejectsMissingCenter() {
        let json = #"{"angle":1.57}"#
        XCTAssertThrowsError(try decoder.decode(RotateTarget.self, from: Data(json.utf8)))
    }

    func testRotateTargetRejectsUnknownField() {
        let json = #"{"angle":1.57,"centerX":10,"centerY":20,"unexpectedRadius":100}"#
        XCTAssertThrowsError(try decoder.decode(RotateTarget.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("Unknown rotate target field"), "\(error)")
        }
    }

    // MARK: - TwoFingerTapTarget

    func testTwoFingerTapTargetRoundTrip() throws {
        let target = TwoFingerTapTarget(
            center: .element(.heistId("canvas")),
            spread: 60
        )
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(TwoFingerTapTarget.self, from: data)
        XCTAssertEqual(decoded.center, GesturePointSelection.element(.heistId("canvas")))
        XCTAssertEqual(decoded.spread, 60)
    }

    func testTwoFingerTapTargetCoordinateCenterRoundTrip() throws {
        let target = TwoFingerTapTarget(center: .coordinate(ScreenPoint(x: 10, y: 20)))
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(TwoFingerTapTarget.self, from: data)
        XCTAssertEqual(decoded.center, .coordinate(ScreenPoint(x: 10, y: 20)))
        XCTAssertNil(decoded.spread)
    }

    func testTwoFingerTapTargetRejectsMissingCenter() {
        let json = #"{}"#
        XCTAssertThrowsError(try decoder.decode(TwoFingerTapTarget.self, from: Data(json.utf8)))
    }

    func testTwoFingerTapTargetRejectsUnknownField() {
        let json = #"{"centerX":10,"centerY":20,"unexpectedSpread":60}"#
        XCTAssertThrowsError(try decoder.decode(TwoFingerTapTarget.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("Unknown two finger tap target field"), "\(error)")
        }
    }

    // MARK: - PathPoint

    func testPathPointRoundTrip() throws {
        let point = PathPoint(x: 42.5, y: 99.1)
        let data = try encoder.encode(point)
        let decoded = try decoder.decode(PathPoint.self, from: data)
        XCTAssertEqual(decoded, point)
    }

    func testPathPointCGPoint() {
        let point = PathPoint(x: 10, y: 20)
        XCTAssertEqual(point.cgPoint, CGPoint(x: 10, y: 20))
    }

    func testPathPointRejectsUnknownField() {
        let json = #"{"x":10,"y":20,"pressure":0.5}"#
        XCTAssertThrowsError(try decoder.decode(PathPoint.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("Unknown draw path point field"), "\(error)")
        }
    }

    // MARK: - BezierSegment

    func testBezierSegmentRoundTrip() throws {
        let segment = BezierSegment(
            cp1X: 10, cp1Y: 20, cp2X: 30, cp2Y: 40, endX: 50, endY: 60
        )
        let data = try encoder.encode(segment)
        let decoded = try decoder.decode(BezierSegment.self, from: data)
        XCTAssertEqual(decoded.cp1, CGPoint(x: 10, y: 20))
        XCTAssertEqual(decoded.cp2, CGPoint(x: 30, y: 40))
        XCTAssertEqual(decoded.end, CGPoint(x: 50, y: 60))
    }

    func testBezierSegmentComputedPoints() {
        let segment = BezierSegment(
            cp1X: 1, cp1Y: 2, cp2X: 3, cp2Y: 4, endX: 5, endY: 6
        )
        XCTAssertEqual(segment.cp1, CGPoint(x: 1, y: 2))
        XCTAssertEqual(segment.cp2, CGPoint(x: 3, y: 4))
        XCTAssertEqual(segment.end, CGPoint(x: 5, y: 6))
    }

    func testBezierSegmentRejectsUnknownField() {
        let json = """
        {"cp1X":1,"cp1Y":2,"cp2X":3,"cp2Y":4,"endX":5,"endY":6,"weight":0.5}
        """
        XCTAssertThrowsError(try decoder.decode(BezierSegment.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("Unknown bezier segment field"), "\(error)")
        }
    }

    // MARK: - DrawPathTarget

    func testDrawPathTargetRoundTrip() throws {
        let target = DrawPathTarget(
            points: [PathPoint(x: 0, y: 0), PathPoint(x: 100, y: 100)],
            duration: 1.0
        )
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(DrawPathTarget.self, from: data)
        XCTAssertEqual(decoded.points.count, 2)
        XCTAssertEqual(decoded.duration, 1.0)
        XCTAssertNil(decoded.velocity)
    }

    func testDrawPathTargetWithVelocity() throws {
        let target = DrawPathTarget(
            points: [PathPoint(x: 0, y: 0), PathPoint(x: 50, y: 50)],
            velocity: 200
        )
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(DrawPathTarget.self, from: data)
        XCTAssertNil(decoded.duration)
        XCTAssertEqual(decoded.velocity, 200)
    }

    func testDrawPathTargetRejectsDurationAndVelocityTogether() throws {
        let target = DrawPathTarget(
            points: [PathPoint(x: 0, y: 0), PathPoint(x: 50, y: 50)],
            duration: 1,
            velocity: 200
        )
        XCTAssertThrowsError(try encoder.encode(target)) { error in
            XCTAssertTrue("\(error)".contains("duration or velocity"), "\(error)")
        }

        let json = """
        {"points":[{"x":0,"y":0},{"x":50,"y":50}],"duration":1,"velocity":200}
        """
        XCTAssertThrowsError(try decoder.decode(DrawPathTarget.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("duration or velocity"), "\(error)")
        }
    }

    // MARK: - DrawBezierTarget

    func testDrawBezierTargetRoundTrip() throws {
        let target = DrawBezierTarget(
            startX: 0, startY: 0,
            segments: [
                BezierSegment(cp1X: 10, cp1Y: 50, cp2X: 90, cp2Y: 50, endX: 100, endY: 0)
            ],
            samplesPerSegment: 30,
            duration: 2.0
        )
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(DrawBezierTarget.self, from: data)
        XCTAssertEqual(decoded.startPoint, CGPoint(x: 0, y: 0))
        XCTAssertEqual(decoded.segments.count, 1)
        XCTAssertEqual(decoded.segments[0].end, CGPoint(x: 100, y: 0))
        XCTAssertEqual(decoded.samplesPerSegment, 30)
        XCTAssertEqual(decoded.duration, 2.0)
        XCTAssertNil(decoded.velocity)
    }

    func testDrawBezierTargetStartPoint() {
        let target = DrawBezierTarget(startX: 42, startY: 99, segments: [])
        XCTAssertEqual(target.startPoint, CGPoint(x: 42, y: 99))
    }

    func testDrawBezierTargetRejectsDurationAndVelocityTogether() throws {
        let segment = BezierSegment(cp1X: 10, cp1Y: 50, cp2X: 90, cp2Y: 50, endX: 100, endY: 0)
        let target = DrawBezierTarget(
            startX: 0,
            startY: 0,
            segments: [segment],
            duration: 1,
            velocity: 200
        )
        XCTAssertThrowsError(try encoder.encode(target)) { error in
            XCTAssertTrue("\(error)".contains("duration or velocity"), "\(error)")
        }

        let json = """
        {
          "startX":0,
          "startY":0,
          "segments":[{"cp1X":10,"cp1Y":50,"cp2X":90,"cp2Y":50,"endX":100,"endY":0}],
          "duration":1,
          "velocity":200
        }
        """
        XCTAssertThrowsError(try decoder.decode(DrawBezierTarget.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("duration or velocity"), "\(error)")
        }
    }

    // MARK: - WaitForIdleTarget

    func testWaitForIdleTargetRoundTrip() throws {
        let target = WaitForIdleTarget(timeout: 3.0)
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(WaitForIdleTarget.self, from: data)
        XCTAssertEqual(decoded.timeout, 3.0)
    }

    func testWaitForIdleTargetNilTimeout() throws {
        let target = WaitForIdleTarget()
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(WaitForIdleTarget.self, from: data)
        XCTAssertNil(decoded.timeout)
    }

    // MARK: - ScrollTarget

    func testScrollTargetRoundTrip() throws {
        let target = ScrollTarget(
            selection: .element(.heistId("list")),
            direction: .down
        )
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(ScrollTarget.self, from: data)
        XCTAssertEqual(decoded.selection, .element(.heistId("list")))
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

    func testScrollTargetContainerRoundTrip() throws {
        let target = ScrollTarget(
            selection: .container(ScrollContainerTarget(stableId: "main_scroll")),
            direction: .up
        )
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(ScrollTarget.self, from: data)
        XCTAssertEqual(decoded.selection, .container(ScrollContainerTarget(stableId: "main_scroll")))
        XCTAssertEqual(decoded.direction, .up)
    }

    // MARK: - ScrollToEdgeTarget

    func testScrollToEdgeTargetAllEdges() throws {
        for edge in ScrollEdge.allCases {
            let target = ScrollToEdgeTarget(
                selection: .element(.heistId("scroll_view")),
                edge: edge
            )
            let data = try encoder.encode(target)
            let decoded = try decoder.decode(ScrollToEdgeTarget.self, from: data)
            XCTAssertEqual(decoded.edge, edge)
            XCTAssertEqual(decoded.selection, .element(.heistId("scroll_view")))
        }
    }

    func testScrollToEdgeTargetContainerRoundTrip() throws {
        let target = ScrollToEdgeTarget(
            selection: .container(ScrollContainerTarget(stableId: "main_scroll")),
            edge: .bottom
        )
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(ScrollToEdgeTarget.self, from: data)
        XCTAssertEqual(decoded.selection, .container(ScrollContainerTarget(stableId: "main_scroll")))
        XCTAssertEqual(decoded.edge, .bottom)
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

    // MARK: - SubtreeSelector

    func testSubtreeSelectorElementUsesToolSchemaShape() throws {
        let selector = SubtreeSelector.element(
            .matcher(ElementMatcher(label: "Save", traits: [.button]), ordinal: 2)
        )

        let data = try encoder.encode(selector)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(payload["ordinal"] as? Int, 2)
        let element = try XCTUnwrap(payload["element"] as? [String: Any])
        XCTAssertNil(payload["container"])
        XCTAssertNil(element["heistId"])
        XCTAssertEqual(element["label"] as? String, "Save")
        XCTAssertEqual(element["traits"] as? [String], ["button"])
        XCTAssertEqual(try decoder.decode(SubtreeSelector.self, from: data), selector)
    }

    func testSubtreeSelectorElementUsesCurrentCaptureHandleShape() throws {
        let selector = SubtreeSelector.element(.heistId("button_save"))

        let data = try encoder.encode(selector)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(payload["ordinal"])
        let element = try XCTUnwrap(payload["element"] as? [String: Any])
        XCTAssertEqual(element["heistId"] as? String, "button_save")
        XCTAssertEqual(try decoder.decode(SubtreeSelector.self, from: data), selector)
    }

    func testSubtreeSelectorContainerUsesToolSchemaShape() throws {
        let selector = SubtreeSelector.container(
            ContainerMatcher(stableId: "semantic_actions", type: .semanticGroup, label: "Actions"),
            ordinal: 1
        )

        let data = try encoder.encode(selector)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(payload["ordinal"] as? Int, 1)
        let container = try XCTUnwrap(payload["container"] as? [String: Any])
        XCTAssertNil(payload["element"])
        XCTAssertEqual(container["stableId"] as? String, "semantic_actions")
        XCTAssertEqual(container["type"] as? String, "semanticGroup")
        XCTAssertEqual(container["label"] as? String, "Actions")
        XCTAssertEqual(try decoder.decode(SubtreeSelector.self, from: data), selector)
    }

    func testSubtreeSelectorElementRejectsHeistIdWithMatcherFields() {
        let json = #"{"element":{"heistId":"button_save","label":"Save"}}"#
        XCTAssertThrowsError(try decoder.decode(SubtreeSelector.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("cannot be combined"), "\(error)")
        }
    }

    func testSubtreeSelectorElementRejectsHeistIdWithOrdinal() {
        let json = #"{"element":{"heistId":"button_save"},"ordinal":1}"#
        XCTAssertThrowsError(try decoder.decode(SubtreeSelector.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("cannot be combined"), "\(error)")
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
            heistId: "btn",
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
            heistId: "a", description: "A", label: "A", value: nil, identifier: nil,
            frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44, actions: []
        )
        let elementB = HeistElement(
            heistId: "b", description: "B", label: "B", value: nil, identifier: nil,
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

    // MARK: - BatchPlan

    func testBatchPlanRoundTripPreservesCommandStepWireShape() throws {
        let plan = BatchPlan(
            steps: [
                BatchStep(
                    command: .activate(.matcher(ElementMatcher(label: "Settings", traits: [.button]), ordinal: 1)),
                    expectation: .screenChanged,
                    deadline: Deadline(timeout: 2.5)
                ),
                BatchStep(
                    command: .setPasteboard(SetPasteboardTarget(text: "ready")),
                    expectation: .delivery,
                    deadline: Deadline()
                ),
            ],
            policy: .continueOnError
        )

        let data = try encoder.encode(plan)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(payload["policy"] as? String, "continue_on_error")
        let steps = try XCTUnwrap(payload["steps"] as? [[String: Any]])
        XCTAssertEqual(steps.count, 2)
        let activate = try XCTUnwrap(steps[0]["command"] as? [String: Any])
        XCTAssertEqual(activate["type"] as? String, "activate")
        let target = try XCTUnwrap(activate["payload"] as? [String: Any])
        XCTAssertEqual(target["ordinal"] as? Int, 1)
        XCTAssertEqual(target["label"] as? String, "Settings")
        XCTAssertEqual(target["traits"] as? [String], ["button"])
        XCTAssertEqual((steps[0]["expect"] as? [String: Any])?["type"] as? String, "screen_changed")
        XCTAssertEqual((steps[0]["deadline"] as? [String: Any])?["timeout"] as? Double, 2.5)

        let decoded = try decoder.decode(BatchPlan.self, from: data)
        XCTAssertEqual(decoded.policy, .continueOnError)
        XCTAssertEqual(decoded.steps.count, 2)
        guard case .activate(let decodedTarget) = decoded.steps[0].command else {
            return XCTFail("Expected activate command")
        }
        XCTAssertEqual(decodedTarget, .matcher(ElementMatcher(label: "Settings", traits: [.button]), ordinal: 1))
        XCTAssertEqual(decoded.steps[0].expectation, .screenChanged)
        XCTAssertEqual(decoded.steps[0].deadline, Deadline(timeout: 2.5))
        guard case .setPasteboard(let pasteboardTarget) = decoded.steps[1].command else {
            return XCTFail("Expected set_pasteboard command")
        }
        XCTAssertEqual(pasteboardTarget.text, "ready")
        XCTAssertEqual(decoded.steps[1].expectation, .delivery)
    }

    func testBatchExecutionResultRoundTripPreservesActionFailureDiagnostics() throws {
        let result = BatchExecutionResult(
            policy: .stopOnError,
            steps: [
                BatchExecutionStepResult(
                    index: 0,
                    actionResult: ActionResult(
                        success: false,
                        method: .activate,
                        message: "No element matching label \"Save\"",
                        errorKind: .elementNotFound
                    ),
                    durationMs: 0,
                    stopsBatch: true
                ),
                BatchExecutionStepResult(
                    index: 1,
                    durationMs: 0,
                    skipped: BatchExecutionSkippedStepResult(
                        index: 1,
                        reason: "skipped: stop_on_error stopped batch after step 0",
                        afterFailedIndex: 0
                    )
                ),
            ],
            totalTimingMs: 1,
            failedIndex: 0
        )

        let data = try encoder.encode(result)
        let decoded = try decoder.decode(BatchExecutionResult.self, from: data)

        XCTAssertEqual(decoded.policy, .stopOnError)
        XCTAssertEqual(decoded.failedIndex, 0)
        XCTAssertEqual(decoded.steps.count, 2)
        XCTAssertTrue(decoded.steps[0].stopsBatch)
        XCTAssertEqual(decoded.steps[0].actionResult?.method, .activate)
        XCTAssertEqual(decoded.steps[0].actionResult?.errorKind, .elementNotFound)
        XCTAssertEqual(
            decoded.steps[0].actionResult?.message,
            "No element matching label \"Save\""
        )
        XCTAssertTrue(decoded.steps[1].isSkipped)
        XCTAssertEqual(decoded.steps[1].skipped?.reason, "skipped: stop_on_error stopped batch after step 0")
        XCTAssertEqual(decoded.steps[1].skipped?.afterFailedIndex, 0)
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
        let change = PropertyChange(property: .label, old: "OK", new: "Cancel")
        let data = try encoder.encode(change)
        let decoded = try decoder.decode(PropertyChange.self, from: data)
        XCTAssertEqual(decoded, change)
    }

    func testElementPropertyIsGeometry() {
        XCTAssertTrue(ElementProperty.frame.isGeometry)
        XCTAssertTrue(ElementProperty.activationPoint.isGeometry)
        XCTAssertFalse(ElementProperty.label.isGeometry)
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
        let update = ElementUpdate(
            heistId: "btn_1",
            changes: [
                PropertyChange(property: .label, old: "A", new: "B"),
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
        XCTAssertEqual(TXTRecordKey.certFingerprint.rawValue, "certfp")
        XCTAssertEqual(TXTRecordKey.transport.rawValue, "transport")
        XCTAssertEqual(TXTRecordKey.sessionActive.rawValue, "sessionactive")
    }

    // MARK: - EnvironmentKey

    func testEnvironmentKeyRawValues() {
        XCTAssertEqual(EnvironmentKey.buttonheistDevice.rawValue, "BUTTONHEIST_DEVICE")
        XCTAssertEqual(EnvironmentKey.buttonheistToken.rawValue, "BUTTONHEIST_TOKEN")
        XCTAssertEqual(EnvironmentKey.insideJobToken.rawValue, "INSIDEJOB_TOKEN")
        XCTAssertEqual(EnvironmentKey.insideJobPort.rawValue, "INSIDEJOB_PORT")
    }

    // MARK: - ScrollSearchDirection

    func testScrollSearchDirectionAllCasesRoundTrip() throws {
        for direction in ScrollSearchDirection.allCases {
            let data = try encoder.encode(direction)
            let decoded = try decoder.decode(ScrollSearchDirection.self, from: data)
            XCTAssertEqual(decoded, direction)
        }
    }

    // MARK: - ErrorKind

    func testErrorKindAllCasesRoundTrip() throws {
        for kind in ErrorKind.allCases {
            let data = try encoder.encode(kind)
            let decoded = try decoder.decode(ErrorKind.self, from: data)
            XCTAssertEqual(decoded, kind)
        }
    }

    // MARK: - ElementSearchTarget

    func testElementSearchTargetRoundTrip() throws {
        let target = ElementSearchTarget(
            elementTarget: .heistId("item_42"),
            direction: .up
        )
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(ElementSearchTarget.self, from: data)
        XCTAssertEqual(decoded.elementTarget, .heistId("item_42"))
        XCTAssertEqual(decoded.direction, .up)
    }

    func testElementSearchTargetDirectionDefaults() {
        let withDirection = ElementSearchTarget(elementTarget: .heistId("item"), direction: .left)
        XCTAssertEqual(withDirection.direction, .left)

        let defaultDirection = ElementSearchTarget(elementTarget: .heistId("item"))
        XCTAssertEqual(defaultDirection.direction, .down)
    }

    // MARK: - WaitForTarget

    func testWaitForTargetRoundTrip() throws {
        let target = WaitForTarget(
            elementTarget: .heistId("loading"),
            absent: true,
            timeout: 15
        )
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(WaitForTarget.self, from: data)
        XCTAssertEqual(decoded.elementTarget, .heistId("loading"))
        XCTAssertEqual(decoded.absent, true)
        XCTAssertEqual(decoded.timeout, 15)
    }

    func testWaitForTargetResolvedDefaults() {
        let target = WaitForTarget(elementTarget: .heistId("x"))
        XCTAssertFalse(target.resolvedAbsent)
        XCTAssertEqual(target.resolvedTimeout, 10)
    }

    func testWaitForTargetTimeoutCapsAt30() {
        let target = WaitForTarget(elementTarget: .heistId("x"), timeout: 60)
        XCTAssertEqual(target.resolvedTimeout, 30)
    }

    func testWaitForChangeTargetResolvedDefaults() {
        let target = WaitForChangeTarget()
        XCTAssertEqual(target.resolvedTimeout, 30)
    }
}
