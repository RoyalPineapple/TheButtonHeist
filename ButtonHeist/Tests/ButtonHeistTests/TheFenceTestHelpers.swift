import ButtonHeistTestSupport
import XCTest
import ThePlans
import Network
@_spi(ButtonHeistTooling) @testable import ButtonHeist
@_spi(ButtonHeistInternals) import TheScore

// Shared fixtures and helpers for TheFence test classes. Keeps tests focused
// on behavior rather than repeating the connected-fence construction dance.

enum TheFenceFixtures {
    static let testDevice = DiscoveredDevice(
        id: "mock-device",
        name: "MockApp#test",
        endpoint: DiscoveredDeviceEndpoint.hostPort(host: "::1", port: 1)
    )

    static let testServerInfo = ServerInfo(
        appName: "MockApp",
        bundleIdentifier: "com.test.mock",
        deviceName: "MockDevice",
        systemVersion: "18.0",
        screenWidth: 393,
        screenHeight: 852,
        instanceId: "mock-session",
        instanceIdentifier: "mock-server",
        listeningPort: 49152,
        tlsActive: true
    )
}

extension TheFence {
    @ButtonHeistActor
    func parseRequest(command: Command, values: [String: HeistValue] = [:]) throws -> ParsedRequest {
        try parseRequest(
            command: command,
            arguments: CommandArgumentEnvelope(values: values)
        )
    }

    @ButtonHeistActor
    func parseRequest(command: Command, arguments: CommandArgumentEnvelope) throws -> ParsedRequest {
        try admit(FenceCommandInput(command: command, arguments: arguments)).parsed
    }

    @ButtonHeistActor
    func execute(command: Command, arguments: CommandArgumentEnvelope) async throws -> FenceResponse {
        let request: FenceOperationRequest
        do {
            request = try admit(FenceCommandInput(command: command, arguments: arguments))
        } catch {
            return .failure(error)
        }
        return try await execute(request)
    }

    @ButtonHeistActor
    func execute(command: Command, values: [String: HeistValue] = [:]) async throws -> FenceResponse {
        let request: FenceOperationRequest
        do {
            request = try admit(FenceCommandInput(command: command, arguments: CommandArgumentEnvelope(values: values)))
        } catch {
            return .failure(error)
        }
        return try await execute(request)
    }
}

extension FenceResponse {
    /// The leaf action for assertions, whether the response is a direct
    /// `.action` (e.g. the `get_pasteboard` read) or a single-leaf
    /// `.heistExecution` (a single command executed as a one-step heist).
    @ButtonHeistActor
    var leafAction: (result: ActionResult, expectation: ExpectationResult?)? {
        if case .action(_, let result, let expectation) = self {
            return (result, expectation)
        }
        if case .heistExecution(_, let result, _) = self,
           let step = result.steps.firstActionLeaf,
           let actionResult = step.reportActionResult {
            return (actionResult, step.reportExpectation)
        }
        return nil
    }
}

private extension Array where Element == HeistExecutionStepResult {
    var firstActionLeaf: HeistExecutionStepResult? {
        for step in self {
            if step.kind == .action {
                return step
            }
            if let child = step.children.firstActionLeaf {
                return child
            }
        }
        return nil
    }
}

extension Array where Element == (ClientMessage, RequestID?) {
    /// The single `HeistPlan` sent for a command, when execution routed through
    /// the one-step heist pipeline.
    var sentHeistPlan: HeistPlan? {
        for (message, _) in self {
            if case .heistPlan(let run) = message { return run.plan }
        }
        return nil
    }

    var sentHeistRun: HeistPlanRun? {
        for (message, _) in self {
            if case .heistPlan(let run) = message { return run }
        }
        return nil
    }

    /// Action commands inside the sent heist plan, in order — the wire-level
    /// equivalent of the old per-message dispatch list now that a command
    /// executes as a plan.
    var sentHeistActionCommands: [HeistActionCommand] {
        guard let plan = sentHeistPlan else { return [] }
        return plan.body.compactMap { step in
            if case .action(let action) = step { return action.command }
            return nil
        }
    }

    var sentWaitSteps: [WaitStep] {
        guard let plan = sentHeistPlan else { return [] }
        return plan.body.compactMap { step in
            if case .wait(let wait) = step { return wait }
            return nil
        }
    }

    /// The sent heist plan's action steps resolved to runtime commands.
    var sentPlanMessages: [ResolvedHeistActionCommand] {
        guard let plan = sentHeistPlan else { return [] }
        return plan.body.compactMap { step in
            guard case .action(let action) = step else { return nil }
            return try? action.command.resolve(in: .empty)
        }
    }
}

func semanticTarget(
    label: String? = nil,
    identifier: String? = nil,
    value: String? = nil,
    traits: [HeistTrait]? = nil,
    ordinal: Int? = nil
) -> AccessibilityTarget {
    .predicate(
        ElementPredicateTemplate(
            label: label.map(StringMatch.exact),
            identifier: identifier.map(StringMatch.exact),
            value: value.map(StringMatch.exact),
            traits: traits ?? []
        ),
        ordinal: ordinal
    )
}

func targetArgumentValue(heistId: String) -> HeistValue {
    .object(["heistId": .string(heistId)])
}

func targetArgumentValue(
    label: String? = nil,
    identifier: String? = nil,
    value: String? = nil,
    traits: [String]? = nil,
    ordinal: Int? = nil
) -> HeistValue {
    var checks: [HeistValue] = []
    if let label { checks.append(predicateCheckArgumentValue(kind: "label", match: stringMatchArgumentValue(label))) }
    if let identifier { checks.append(predicateCheckArgumentValue(kind: "identifier", match: stringMatchArgumentValue(identifier))) }
    if let value { checks.append(predicateCheckArgumentValue(kind: "value", match: stringMatchArgumentValue(value))) }
    if let traits { checks.append(predicateCheckArgumentValue(kind: "traits", values: traits.map { .string($0) })) }
    var target: [String: HeistValue] = ["checks": .array(checks)]
    if let ordinal { target["ordinal"] = .int(ordinal) }
    return .object(target)
}

func scriptedHeistResponse(
    _ result: HeistExecutionResult = HeistReceiptFixture.result(steps: [HeistReceiptFixture.action()])
) -> ServerMessage {
    .actionResult(.success(payload: .heistExecution(result)))
}

func stringMatchArgumentValue(_ value: String, mode: String = "exact") -> HeistValue {
    .object([
        "mode": .string(mode),
        "value": .string(value),
    ])
}

private func predicateCheckArgumentValue(
    kind: String,
    match: HeistValue? = nil,
    values: [HeistValue]? = nil
) -> HeistValue {
    var object: [String: HeistValue] = ["kind": .string(kind)]
    if let match { object["match"] = match }
    if let values { object["values"] = .array(values) }
    return .object(object)
}

@ButtonHeistActor
func makeConnectedFence(configuration: TheFence.Configuration = .init()) -> (TheFence, MockConnection) {
    let mockConn = MockConnection()
    mockConn.serverInfo = TheFenceFixtures.testServerInfo
    mockConn.responseScript = { message in
        switch message {
        case .ping:
            return .pong(PongPayload(
                buttonHeistVersion: "0.0.1",
                appName: "MockApp",
                bundleIdentifier: "com.test.mock",
                appVersion: "1.0",
                appBuild: "1",
                serverInstanceIdentifier: "mock-server",
                serverTimestampMs: 1_700_000_000_000
            ))
        case .requestInterface:
            return .interface(Interface(timestamp: Date(), tree: []))
        case .requestScreen:
            return .screen(ScreenPayload(pngData: "", width: 393, height: 852, interface: Interface(timestamp: Date(), tree: [])))
        case .heistPlan:
            return scriptedHeistResponse()
        default:
            return .actionResult(ActionResult.success(method: .activate))
        }
    }

    let mockDisc = MockDiscovery()
    mockDisc.discoveredDevices = [TheFenceFixtures.testDevice]

    let fence = TheFence(configuration: configuration)
    fence.handoff.makeDiscovery = { mockDisc }
    fence.handoff.makeConnection = { _ in mockConn }

    makeReachabilityConnection = { _ in
        let probe = MockConnection()
        probe.emitTransportReadyOnConnect = true
        probe.responseScript = { message in
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
            return .actionResult(ActionResult.success(method: .activate))
        }
        return probe
    }

    return (fence, mockConn)
}

func makeBackgroundElementsChangedTrace(elementCount: Int) -> AccessibilityTrace {
    let interface = makeTestInterface(elementCount: elementCount)
    let beforeCapture = AccessibilityTrace.Capture(sequence: 1, interface: interface)
    let afterCapture = AccessibilityTrace.Capture(
        sequence: 2,
        interface: interface,
        parentHash: beforeCapture.hash,
        context: AccessibilityTrace.Context(screenId: "background-change")
    )
    return AccessibilityTrace(captures: [beforeCapture, afterCapture])
}

func makeBackgroundScreenChangedTrace(elementCount: Int) -> AccessibilityTrace {
    makeTestTrace(
        before: makeTestInterface(elementCount: 0, prefix: "before"),
        after: makeTestInterface(elementCount: elementCount, prefix: "after"),
        beforeScreenId: "before",
        afterScreenId: "after"
    )
}

func publicJSONProbe(
    _ response: FenceResponse,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> JSONProbe {
    try JSONProbe(data: try response.jsonData())
}

func publicInterfaceJSONProbe(
    _ interface: PublicInterface,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> JSONProbe {
    try JSONProbe(data: try JSONEncoder().encode(interface))
}

struct HeistInspection {
    let commands: [TheFence.Command]
    let steps: [HeistStep]
    let executionResult: HeistExecutionResult
    let executedTopLevelStepCount: Int
    let abortedAtPath: HeistExecutionPath?
    let durationMs: Int
    let expectationsChecked: Int
    let expectationsMet: Int
    let accessibilityTrace: AccessibilityTrace?
}

func inspectHeist(_ response: FenceResponse) -> HeistInspection? {
    guard case .heistExecution(let plan, let result, let accessibilityTrace) = response else {
        return nil
    }
    let plannedSteps = plan.body
    return HeistInspection(
        commands: plannedSteps.map(\.commandForInspection),
        steps: plannedSteps,
        executionResult: result,
        executedTopLevelStepCount: result.executedTopLevelStepCount,
        abortedAtPath: result.abortedAtPath,
        durationMs: result.durationMs,
        expectationsChecked: result.expectationsChecked,
        expectationsMet: result.expectationsMet,
        accessibilityTrace: accessibilityTrace
    )
}

private extension HeistStep {
    var commandForInspection: TheFence.Command {
        switch self {
        case .action(let action):
            return action.command.fenceCommandForInspection
        case .wait:
            return .wait
        case .conditional, .forEachElement, .forEachString, .repeatUntil, .heist, .invoke, .warn, .fail:
            return .runHeist
        }
    }
}

private extension HeistActionCommand {
    var fenceCommandForInspection: TheFence.Command {
        switch wireType {
        case .activate, .increment, .decrement, .performCustomAction:
            return .activate
        case .rotor:
            return .rotor
        case .dismiss, .magicTap:
            return .perform
        case .oneFingerTap:
            return .oneFingerTap
        case .longPress:
            return .longPress
        case .swipe:
            return .swipe
        case .drag:
            return .drag
        case .typeText:
            return .typeText
        case .editAction:
            return .editAction
        case .setPasteboard:
            return .setPasteboard
        case .takeScreenshot:
            return .getScreen
        case .scroll:
            return .scroll
        case .scrollToVisible:
            return .scrollToVisible
        case .scrollToEdge:
            return .scrollToEdge
        case .resignFirstResponder:
            return .dismissKeyboard
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
