import XCTest
@testable import TheScore

// MARK: - Wire Type Codable Round-Trip Tests

final class WireTypeRoundTripTests: XCTestCase {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - ScrollEdge

    func testScrollEdgeAllCasesRoundTrip() throws {
        for edge in ScrollEdge.allCases {
            let data = try encoder.encode(edge)
            let decoded = try decoder.decode(ScrollEdge.self, from: data)
            XCTAssertEqual(decoded, edge)
        }
    }

    func testScrollEdgeRawValues() {
        XCTAssertEqual(ScrollEdge.top.rawValue, "top")
        XCTAssertEqual(ScrollEdge.bottom.rawValue, "bottom")
        XCTAssertEqual(ScrollEdge.left.rawValue, "left")
        XCTAssertEqual(ScrollEdge.right.rawValue, "right")
    }

    // MARK: - ScrollDirection

    func testScrollDirectionAllCasesRoundTrip() throws {
        for direction in ScrollDirection.allCases {
            let data = try encoder.encode(direction)
            let decoded = try decoder.decode(ScrollDirection.self, from: data)
            XCTAssertEqual(decoded, direction)
        }
    }

    func testScrollDirectionCaseCount() {
        XCTAssertEqual(ScrollDirection.allCases.count, 6)
    }

    func testScrollDirectionRawValues() {
        XCTAssertEqual(ScrollDirection.next.rawValue, "next")
        XCTAssertEqual(ScrollDirection.previous.rawValue, "previous")
    }

    // MARK: - EditAction

    func testEditActionAllCasesRoundTrip() throws {
        for action in EditAction.allCases {
            let data = try encoder.encode(action)
            let decoded = try decoder.decode(EditAction.self, from: data)
            XCTAssertEqual(decoded, action)
        }
    }

    func testEditActionCaseCount() {
        XCTAssertEqual(EditAction.allCases.count, 5)
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
        XCTAssertEqual(decoded.elementTarget, .heistId("btn_save"))
        XCTAssertEqual(decoded.actionName, "Delete Item")
    }

    func testCustomActionTargetWithMatcher() throws {
        let target = CustomActionTarget(
            elementTarget: .matcher(ElementMatcher(label: "Menu")),
            actionName: "Open Submenu"
        )
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(CustomActionTarget.self, from: data)
        XCTAssertEqual(decoded.actionName, "Open Submenu")
    }

    // MARK: - LongPressTarget

    func testLongPressTargetRoundTrip() throws {
        let target = LongPressTarget(
            elementTarget: .heistId("cell_1"),
            duration: 1.5
        )
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(LongPressTarget.self, from: data)
        XCTAssertEqual(decoded.elementTarget, .heistId("cell_1"))
        XCTAssertEqual(decoded.duration, 1.5)
    }

    func testLongPressTargetWithPointRoundTrip() throws {
        let target = LongPressTarget(pointX: 100, pointY: 200, duration: 0.8)
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(LongPressTarget.self, from: data)
        XCTAssertEqual(decoded.pointX, 100)
        XCTAssertEqual(decoded.pointY, 200)
        XCTAssertEqual(decoded.duration, 0.8)
        XCTAssertNil(decoded.elementTarget)
    }

    func testLongPressTargetDefaultDuration() {
        let target = LongPressTarget()
        XCTAssertEqual(target.duration, 0.5)
    }

    func testLongPressTargetPointComputed() {
        let withPoint = LongPressTarget(pointX: 10, pointY: 20)
        XCTAssertEqual(withPoint.point, CGPoint(x: 10, y: 20))

        let withoutPoint = LongPressTarget()
        XCTAssertNil(withoutPoint.point)

        let partialPoint = LongPressTarget(pointX: 10)
        XCTAssertNil(partialPoint.point)
    }

    // MARK: - DragTarget

    func testDragTargetRoundTrip() throws {
        let target = DragTarget(
            elementTarget: .heistId("handle"),
            startX: 50, startY: 100,
            endX: 200, endY: 300,
            duration: 0.8
        )
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(DragTarget.self, from: data)
        XCTAssertEqual(decoded.elementTarget, .heistId("handle"))
        XCTAssertEqual(decoded.startX, 50)
        XCTAssertEqual(decoded.startY, 100)
        XCTAssertEqual(decoded.endX, 200)
        XCTAssertEqual(decoded.endY, 300)
        XCTAssertEqual(decoded.duration, 0.8)
    }

    func testDragTargetComputedPoints() {
        let target = DragTarget(startX: 10, startY: 20, endX: 30, endY: 40)
        XCTAssertEqual(target.startPoint, CGPoint(x: 10, y: 20))
        XCTAssertEqual(target.endPoint, CGPoint(x: 30, y: 40))

        let noStart = DragTarget(endX: 30, endY: 40)
        XCTAssertNil(noStart.startPoint)
    }

    // MARK: - PinchTarget

    func testPinchTargetRoundTrip() throws {
        let target = PinchTarget(
            elementTarget: .heistId("map"),
            centerX: 195, centerY: 422,
            scale: 2.0, spread: 100, duration: 0.5
        )
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(PinchTarget.self, from: data)
        XCTAssertEqual(decoded.elementTarget, .heistId("map"))
        XCTAssertEqual(decoded.centerX, 195)
        XCTAssertEqual(decoded.centerY, 422)
        XCTAssertEqual(decoded.scale, 2.0)
        XCTAssertEqual(decoded.spread, 100)
        XCTAssertEqual(decoded.duration, 0.5)
    }

    func testPinchTargetMinimalRoundTrip() throws {
        let target = PinchTarget(scale: 0.5)
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(PinchTarget.self, from: data)
        XCTAssertEqual(decoded.scale, 0.5)
        XCTAssertNil(decoded.elementTarget)
        XCTAssertNil(decoded.centerX)
        XCTAssertNil(decoded.spread)
        XCTAssertNil(decoded.duration)
    }

    // MARK: - RotateTarget

    func testRotateTargetRoundTrip() throws {
        let target = RotateTarget(
            elementTarget: .heistId("dial"),
            centerX: 195, centerY: 422,
            angle: .pi / 4, radius: 80, duration: 0.6
        )
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(RotateTarget.self, from: data)
        XCTAssertEqual(decoded.elementTarget, .heistId("dial"))
        XCTAssertEqual(decoded.angle, .pi / 4)
        XCTAssertEqual(decoded.radius, 80)
        XCTAssertEqual(decoded.duration, 0.6)
    }

    func testRotateTargetMinimalRoundTrip() throws {
        let target = RotateTarget(angle: 1.57)
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(RotateTarget.self, from: data)
        XCTAssertEqual(decoded.angle, 1.57)
        XCTAssertNil(decoded.elementTarget)
        XCTAssertNil(decoded.radius)
    }

    // MARK: - TwoFingerTapTarget

    func testTwoFingerTapTargetRoundTrip() throws {
        let target = TwoFingerTapTarget(
            elementTarget: .heistId("canvas"),
            centerX: 200, centerY: 300,
            spread: 60
        )
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(TwoFingerTapTarget.self, from: data)
        XCTAssertEqual(decoded.elementTarget, .heistId("canvas"))
        XCTAssertEqual(decoded.centerX, 200)
        XCTAssertEqual(decoded.centerY, 300)
        XCTAssertEqual(decoded.spread, 60)
    }

    func testTwoFingerTapTargetMinimalRoundTrip() throws {
        let target = TwoFingerTapTarget()
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(TwoFingerTapTarget.self, from: data)
        XCTAssertNil(decoded.elementTarget)
        XCTAssertNil(decoded.centerX)
        XCTAssertNil(decoded.spread)
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

    // MARK: - BezierSegment

    func testBezierSegmentRoundTrip() throws {
        let segment = BezierSegment(
            cp1X: 10, cp1Y: 20, cp2X: 30, cp2Y: 40, endX: 50, endY: 60
        )
        let data = try encoder.encode(segment)
        let decoded = try decoder.decode(BezierSegment.self, from: data)
        XCTAssertEqual(decoded.cp1X, 10)
        XCTAssertEqual(decoded.endY, 60)
    }

    func testBezierSegmentComputedPoints() {
        let segment = BezierSegment(
            cp1X: 1, cp1Y: 2, cp2X: 3, cp2Y: 4, endX: 5, endY: 6
        )
        XCTAssertEqual(segment.cp1, CGPoint(x: 1, y: 2))
        XCTAssertEqual(segment.cp2, CGPoint(x: 3, y: 4))
        XCTAssertEqual(segment.end, CGPoint(x: 5, y: 6))
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
        XCTAssertEqual(decoded.startX, 0)
        XCTAssertEqual(decoded.startY, 0)
        XCTAssertEqual(decoded.segments.count, 1)
        XCTAssertEqual(decoded.samplesPerSegment, 30)
        XCTAssertEqual(decoded.duration, 2.0)
        XCTAssertNil(decoded.velocity)
    }

    func testDrawBezierTargetStartPoint() {
        let target = DrawBezierTarget(startX: 42, startY: 99, segments: [])
        XCTAssertEqual(target.startPoint, CGPoint(x: 42, y: 99))
    }

    // MARK: - WatchPayload

    func testWatchPayloadRoundTrip() throws {
        let payload = WatchPayload(token: "my-token")
        let data = try encoder.encode(payload)
        let decoded = try decoder.decode(WatchPayload.self, from: data)
        XCTAssertEqual(decoded.token, "my-token")
    }

    func testWatchPayloadDefaultToken() throws {
        let payload = WatchPayload()
        XCTAssertEqual(payload.token, "")
        let data = try encoder.encode(payload)
        let decoded = try decoder.decode(WatchPayload.self, from: data)
        XCTAssertEqual(decoded.token, "")
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
            elementTarget: .heistId("list"),
            direction: .down
        )
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(ScrollTarget.self, from: data)
        XCTAssertEqual(decoded.elementTarget, .heistId("list"))
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

    // MARK: - ScrollToEdgeTarget

    func testScrollToEdgeTargetAllEdges() throws {
        for edge in ScrollEdge.allCases {
            let target = ScrollToEdgeTarget(
                elementTarget: .heistId("scroll_view"),
                edge: edge
            )
            let data = try encoder.encode(target)
            let decoded = try decoder.decode(ScrollToEdgeTarget.self, from: data)
            XCTAssertEqual(decoded.edge, edge)
            XCTAssertEqual(decoded.elementTarget, .heistId("scroll_view"))
        }
    }

    // MARK: - ProtocolMismatchPayload

    func testProtocolMismatchPayloadRoundTrip() throws {
        let payload = ProtocolMismatchPayload(
            expectedProtocolVersion: "6.7",
            receivedProtocolVersion: "5.0"
        )
        let data = try encoder.encode(payload)
        let decoded = try decoder.decode(ProtocolMismatchPayload.self, from: data)
        XCTAssertEqual(decoded.expectedProtocolVersion, "6.7")
        XCTAssertEqual(decoded.receivedProtocolVersion, "5.0")
    }

    // MARK: - Group

    func testGroupRoundTrip() throws {
        let group = Group(
            type: .scrollable,
            label: "Messages",
            value: nil,
            identifier: "msg_list",
            frameX: 0, frameY: 100, frameWidth: 390, frameHeight: 700
        )
        let data = try encoder.encode(group)
        let decoded = try decoder.decode(Group.self, from: data)
        XCTAssertEqual(decoded.type, .scrollable)
        XCTAssertEqual(decoded.label, "Messages")
        XCTAssertNil(decoded.value)
        XCTAssertEqual(decoded.identifier, "msg_list")
        XCTAssertEqual(decoded.frameWidth, 390)
    }

    func testGroupAllTypes() throws {
        for groupType in GroupType.allCases {
            let group = Group(
                type: groupType, label: nil, value: nil, identifier: nil,
                frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 100
            )
            let data = try encoder.encode(group)
            let decoded = try decoder.decode(Group.self, from: data)
            XCTAssertEqual(decoded.type, groupType)
        }
    }

    func testGroupUnknownTypeRoundTrip() throws {
        let group = Group(
            type: .unknown("customLayout"), label: nil, value: nil, identifier: nil,
            frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 100
        )
        let data = try encoder.encode(group)
        let decoded = try decoder.decode(Group.self, from: data)
        XCTAssertEqual(decoded.type, .unknown("customLayout"))
    }

    // MARK: - ElementNode

    func testElementNodeLeafRoundTrip() throws {
        let node = ElementNode.element(order: 5)
        let data = try encoder.encode(node)
        let decoded = try decoder.decode(ElementNode.self, from: data)
        XCTAssertEqual(decoded, node)
    }

    func testElementNodeContainerRoundTrip() throws {
        let group = Group(
            type: .list, label: "Items", value: nil, identifier: nil,
            frameX: 0, frameY: 0, frameWidth: 390, frameHeight: 600
        )
        let node = ElementNode.container(group, children: [
            .element(order: 0),
            .element(order: 1),
            .container(
                Group(type: .semanticGroup, label: nil, value: nil, identifier: nil,
                      frameX: 0, frameY: 0, frameWidth: 390, frameHeight: 44),
                children: [.element(order: 2)]
            ),
        ])
        let data = try encoder.encode(node)
        let decoded = try decoder.decode(ElementNode.self, from: data)
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

    // MARK: - RecordingConfig Validation

    func testRecordingConfigValidRoundTrip() throws {
        let config = RecordingConfig(fps: 8, scale: 0.5, inactivityTimeout: 5, maxDuration: 60)
        let data = try encoder.encode(config)
        let decoded = try decoder.decode(RecordingConfig.self, from: data)
        XCTAssertEqual(decoded.fps, 8)
        XCTAssertEqual(decoded.scale, 0.5)
        XCTAssertEqual(decoded.inactivityTimeout, 5)
        XCTAssertEqual(decoded.maxDuration, 60)
    }

    func testRecordingConfigBoundaryFPS() throws {
        let min = RecordingConfig(fps: 1)
        let minData = try encoder.encode(min)
        let decodedMin = try decoder.decode(RecordingConfig.self, from: minData)
        XCTAssertEqual(decodedMin.fps, 1)

        let max = RecordingConfig(fps: 15)
        let maxData = try encoder.encode(max)
        let decodedMax = try decoder.decode(RecordingConfig.self, from: maxData)
        XCTAssertEqual(decodedMax.fps, 15)
    }

    func testRecordingConfigFPSTooLowThrows() throws {
        let json = #"{"fps":0}"#
        XCTAssertThrowsError(
            try decoder.decode(RecordingConfig.self, from: Data(json.utf8))
        )
    }

    func testRecordingConfigFPSTooHighThrows() throws {
        let json = #"{"fps":16}"#
        XCTAssertThrowsError(
            try decoder.decode(RecordingConfig.self, from: Data(json.utf8))
        )
    }

    func testRecordingConfigScaleTooLowThrows() throws {
        let json = #"{"scale":0.1}"#
        XCTAssertThrowsError(
            try decoder.decode(RecordingConfig.self, from: Data(json.utf8))
        )
    }

    func testRecordingConfigScaleTooHighThrows() throws {
        let json = #"{"scale":1.5}"#
        XCTAssertThrowsError(
            try decoder.decode(RecordingConfig.self, from: Data(json.utf8))
        )
    }

    func testRecordingConfigBoundaryScale() throws {
        let min = RecordingConfig(fps: nil, scale: 0.25)
        let minData = try encoder.encode(min)
        let decodedMin = try decoder.decode(RecordingConfig.self, from: minData)
        XCTAssertEqual(decodedMin.scale, 0.25)

        let max = RecordingConfig(fps: nil, scale: 1.0)
        let maxData = try encoder.encode(max)
        let decodedMax = try decoder.decode(RecordingConfig.self, from: maxData)
        XCTAssertEqual(decodedMax.scale, 1.0)
    }

    func testRecordingConfigNilFieldsRoundTrip() throws {
        let config = RecordingConfig()
        let data = try encoder.encode(config)
        let decoded = try decoder.decode(RecordingConfig.self, from: data)
        XCTAssertNil(decoded.fps)
        XCTAssertNil(decoded.scale)
        XCTAssertNil(decoded.inactivityTimeout)
        XCTAssertNil(decoded.maxDuration)
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

    // MARK: - InterfaceDelta

    func testInterfaceDeltaRoundTrip() throws {
        let delta = InterfaceDelta(
            kind: .elementsChanged,
            elementCount: 10,
            added: [HeistElement(
                heistId: "new_btn", description: "New Button",
                label: "Save", value: nil, identifier: nil,
                traits: [.button],
                frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44,
                actions: [.activate]
            )],
            removed: ["old_btn"],
            updated: [ElementUpdate(
                heistId: "counter",
                changes: [PropertyChange(property: .value, old: "1", new: "2")]
            )]
        )
        let data = try encoder.encode(delta)
        let decoded = try decoder.decode(InterfaceDelta.self, from: data)
        XCTAssertEqual(decoded.kind, .elementsChanged)
        XCTAssertEqual(decoded.elementCount, 10)
        XCTAssertEqual(decoded.added?.count, 1)
        XCTAssertEqual(decoded.removed, ["old_btn"])
        XCTAssertEqual(decoded.updated?.count, 1)
        XCTAssertNil(decoded.newInterface)
    }

    func testInterfaceDeltaKindAllCases() throws {
        for kind in [InterfaceDelta.DeltaKind.noChange, .elementsChanged, .screenChanged] {
            let delta = InterfaceDelta(kind: kind, elementCount: 0)
            let data = try encoder.encode(delta)
            let decoded = try decoder.decode(InterfaceDelta.self, from: data)
            XCTAssertEqual(decoded.kind, kind)
        }
    }

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

    // MARK: - ActionMethod

    func testActionMethodAllCasesRoundTrip() throws {
        let allMethods: [ActionMethod] = [
            .activate, .increment, .decrement,
            .syntheticTap, .syntheticLongPress, .syntheticSwipe, .syntheticDrag,
            .syntheticPinch, .syntheticRotate, .syntheticTwoFingerTap, .syntheticDrawPath,
            .typeText, .customAction, .editAction, .resignFirstResponder,
            .setPasteboard, .getPasteboard, .waitForIdle,
            .scroll, .scrollToVisible, .elementSearch, .scrollToEdge,
            .waitFor, .explore, .elementNotFound, .elementDeallocated,
        ]
        for method in allMethods {
            let data = try encoder.encode(method)
            let decoded = try decoder.decode(ActionMethod.self, from: data)
            XCTAssertEqual(decoded, method)
        }
    }

    // MARK: - WireMessageType

    func testWireMessageTypeAllCasesRoundTrip() throws {
        for messageType in WireMessageType.allCases {
            let data = try encoder.encode(messageType)
            let decoded = try decoder.decode(WireMessageType.self, from: data)
            XCTAssertEqual(decoded, messageType)
        }
    }

    func testWireMessageTypeCaseCount() {
        XCTAssertEqual(WireMessageType.allCases.count, 54)
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

    // MARK: - ActionResult.adding

    func testActionResultAddingScrollSearchResult() {
        let result = ActionResult(success: true, method: .scroll)
        let searchResult = ScrollSearchResult(
            scrollCount: 3, uniqueElementsSeen: 20, exhaustive: true
        )
        let updated = result.adding(scrollSearchResult: searchResult)
        XCTAssertEqual(updated.scrollSearchResult?.scrollCount, 3)
        XCTAssertTrue(updated.success)
    }

    func testActionResultAddingExploreElementsWithNoExploreResult() {
        let result = ActionResult(success: true, method: .explore)
        let updated = result.adding(exploreElements: [])
        XCTAssertNil(updated.exploreResult)
    }

    func testActionResultAddingExploreElements() {
        let element = HeistElement(
            heistId: "el_1", description: "Button",
            label: "Save", value: nil, identifier: nil,
            traits: [.button],
            frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44,
            actions: [.activate]
        )
        let explore = ExploreResult(
            elements: [], scrollCount: 5, containersExplored: 2, explorationTime: 1.5
        )
        let result = ActionResult(
            success: true, method: .explore, exploreResult: explore
        )
        let updated = result.adding(exploreElements: [element])
        XCTAssertEqual(updated.exploreResult?.elements.count, 1)
        XCTAssertEqual(updated.exploreResult?.scrollCount, 5)
        XCTAssertEqual(updated.exploreResult?.containersExplored, 2)
    }

    // MARK: - RecordingPayload.StopReason

    func testStopReasonAllCasesRoundTrip() throws {
        let reasons: [RecordingPayload.StopReason] = [.manual, .inactivity, .maxDuration, .fileSizeLimit]
        for reason in reasons {
            let data = try encoder.encode(reason)
            let decoded = try decoder.decode(RecordingPayload.StopReason.self, from: data)
            XCTAssertEqual(decoded, reason)
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

    func testElementSearchTargetResolvedDirection() {
        let withDirection = ElementSearchTarget(direction: .left)
        XCTAssertEqual(withDirection.resolvedDirection, .left)

        let withoutDirection = ElementSearchTarget()
        XCTAssertEqual(withoutDirection.resolvedDirection, .down)
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
}
