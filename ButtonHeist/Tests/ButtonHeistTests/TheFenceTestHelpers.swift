import XCTest
import Network
@testable import ButtonHeist
import TheScore

// Shared fixtures and helpers for TheFence test classes. Keeps tests focused
// on behavior rather than repeating the connected-fence construction dance.

enum TheFenceFixtures {
    static let testDevice = DiscoveredDevice(
        id: "mock-device",
        name: "MockApp#test",
        endpoint: NWEndpoint.hostPort(host: .ipv6(.loopback), port: 1),
        certFingerprint: "sha256:mock"
    )

    static let testServerInfo = ServerInfo(
        appName: "MockApp",
        bundleIdentifier: "com.test.mock",
        deviceName: "MockDevice",
        systemVersion: "18.0",
        screenWidth: 393,
        screenHeight: 852
    )
}

@ButtonHeistActor
func makeConnectedFence(configuration: TheFence.Configuration = .init()) -> (TheFence, MockConnection) {
    let mockConn = MockConnection()
    mockConn.serverInfo = TheFenceFixtures.testServerInfo
    mockConn.autoResponse = { message in
        switch message {
        case .requestInterface:
            return .interface(Interface(timestamp: Date(), tree: []))
        case .requestScreen:
            return .screen(ScreenPayload(pngData: "", width: 393, height: 852))
        case .startRecording:
            return .recordingStarted
        case .stopRecording:
            return .recording(RecordingPayload(
                videoData: "", width: 390, height: 844, duration: 1,
                frameCount: 8, fps: 8, startTime: Date(), endTime: Date(),
                stopReason: .manual
            ))
        default:
            return .actionResult(ActionResult(success: true, method: .activate))
        }
    }

    let mockDisc = MockDiscovery()
    mockDisc.discoveredDevices = [TheFenceFixtures.testDevice]

    let fence = TheFence(configuration: configuration)
    fence.handoff.makeDiscovery = { mockDisc }
    fence.handoff.makeConnection = { _, _, _ in mockConn }

    makeReachabilityConnection = { _ in
        let probe = MockConnection()
        probe.emitTransportReadyOnConnect = true
        probe.autoResponse = { message in
            if case .status = message {
                return .status(StatusPayload(
                    identity: StatusIdentity(
                        appName: "Mock", bundleIdentifier: "com.test",
                        appBuild: "1", deviceName: "Mock",
                        systemVersion: "18.0", buttonHeistVersion: "0.0.1"
                    ),
                    session: StatusSession(active: false, watchersAllowed: false, activeConnections: 0)
                ))
            }
            return .actionResult(ActionResult(success: true, method: .activate))
        }
        return probe
    }

    return (fence, mockConn)
}

func makeReceiptTestElement(
    heistId: String,
    label: String,
    value: String? = nil,
    identifier: String? = nil,
    traits: [HeistTrait] = [.staticText]
) -> HeistElement {
    HeistElement(
        heistId: heistId,
        description: label,
        label: label,
        value: value,
        identifier: identifier,
        traits: traits,
        frameX: 0,
        frameY: 0,
        frameWidth: 100,
        frameHeight: 44,
        actions: []
    )
}

func makeReceiptTestInterface(
    _ elements: [HeistElement],
    timestamp: Date = Date(timeIntervalSince1970: 0)
) -> Interface {
    Interface(timestamp: timestamp, tree: elements.map(InterfaceNode.element))
}

func makeReceiptTestInterface(
    elementCount: Int,
    prefix: String = "element",
    timestamp: Date = Date(timeIntervalSince1970: 0)
) -> Interface {
    makeReceiptTestInterface(
        (0..<elementCount).map { makeReceiptTestElement(heistId: "\(prefix)-\($0)", label: "\(prefix) \($0)") },
        timestamp: timestamp
    )
}

func makeReceiptTestTrace(
    before beforeInterface: Interface,
    after afterInterface: Interface,
    beforeScreenId: String? = "screen",
    afterScreenId: String? = "screen"
) -> AccessibilityTrace {
    let beforeCapture = AccessibilityTrace.Capture(
        sequence: 1,
        interface: beforeInterface,
        context: AccessibilityTrace.Context(screenId: beforeScreenId)
    )
    let afterCapture = AccessibilityTrace.Capture(
        sequence: 2,
        interface: afterInterface,
        parentHash: beforeCapture.hash,
        context: AccessibilityTrace.Context(screenId: afterScreenId)
    )
    return AccessibilityTrace(captures: [beforeCapture, afterCapture])
}

func makeBackgroundElementsChangedTrace(elementCount: Int) -> AccessibilityTrace {
    let interface = makeReceiptTestInterface(elementCount: elementCount)
    let beforeCapture = AccessibilityTrace.Capture(sequence: 1, interface: interface)
    let afterCapture = AccessibilityTrace.Capture(
        sequence: 2,
        interface: interface,
        parentHash: beforeCapture.hash,
        context: AccessibilityTrace.Context(focusedElementId: "background-change")
    )
    return AccessibilityTrace(captures: [beforeCapture, afterCapture])
}

func makeBackgroundScreenChangedTrace(elementCount: Int) -> AccessibilityTrace {
    makeReceiptTestTrace(
        before: makeReceiptTestInterface(elementCount: 0, prefix: "before"),
        after: makeReceiptTestInterface(elementCount: elementCount, prefix: "after"),
        beforeScreenId: "before",
        afterScreenId: "after"
    )
}

func makeBatchOutcome(
    command: String = "test",
    response: FenceResponse = .ok(message: "ok"),
    stopsBatch: Bool = false
) -> BatchStepOutcome {
    BatchStepOutcome(command: command, response: response, stopsBatch: stopsBatch)
}

func makeExpectationBatchOutcome(
    command: String = "activate",
    met: Bool,
    stopsBatch: Bool = false
) -> BatchStepOutcome {
    let expectation = ExpectationResult(
        met: met,
        expectation: .screenChanged,
        actual: met ? nil : "noChange"
    )
    let result = ActionResult(success: true, method: .activate)
    return BatchStepOutcome(
        command: command,
        response: .action(result: result, expectation: expectation),
        stopsBatch: stopsBatch
    )
}

struct BatchInspection {
    let outcomes: [BatchStepOutcome]
    let results: [[String: Any]]
    let completedSteps: Int
    let failedIndex: Int?
    let totalTimingMs: Int
    let expectationsChecked: Int
    let expectationsMet: Int
    let summaries: [BatchStepSummary]
    let accessibilityTrace: AccessibilityTrace?
}

func inspectBatch(_ response: FenceResponse) -> BatchInspection? {
    guard case .batch(let outcomes, let totalTimingMs, let accessibilityTrace) = response else {
        return nil
    }
    return BatchInspection(
        outcomes: outcomes,
        results: outcomes.jsonResultRows,
        completedSteps: outcomes.completedStepCount,
        failedIndex: outcomes.stoppedFailedIndex,
        totalTimingMs: totalTimingMs,
        expectationsChecked: outcomes.expectationsChecked,
        expectationsMet: outcomes.expectationsMet,
        summaries: outcomes.stepSummaries,
        accessibilityTrace: accessibilityTrace
    )
}
