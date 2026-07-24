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
    func parseRequest(command: Command, values: [String: HeistValue] = [:]) throws -> AdmittedFenceCommand {
        try parseRequest(
            command: command,
            arguments: CommandArgumentEnvelope(values: values)
        )
    }

    @ButtonHeistActor
    func parseRequest(command: Command, arguments: CommandArgumentEnvelope) throws -> AdmittedFenceCommand {
        try admit(FenceCommandInput(command: command, arguments: arguments))
    }

    @ButtonHeistActor
    func execute(command: Command, arguments: CommandArgumentEnvelope) async throws -> FenceResponse {
        let request: AdmittedFenceCommand
        do {
            request = try admit(FenceCommandInput(command: command, arguments: arguments))
        } catch {
            return .failure(error)
        }
        return try await execute(request)
    }

    @ButtonHeistActor
    func execute(command: Command, values: [String: HeistValue] = [:]) async throws -> FenceResponse {
        try await execute(command: command, arguments: CommandArgumentEnvelope(values: values))
    }
}

extension FenceResponse {
    @ButtonHeistActor
    var containsAction: Bool {
        switch self {
        case .action:
            true
        case .heistExecution(_, let report):
            report.outputNodes.contains { $0.kind == .action }
        default:
            false
        }
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
        ElementPredicate(
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
    _ result: HeistResult = HeistResultFixture.result(steps: [HeistResultFixture.action()])
) -> ServerMessage {
    .actionResult(.success(payload: .heist(result)))
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
            return .actionResult(ActionResult.success(payload: .activate))
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
            return .actionResult(ActionResult.success(payload: .activate))
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
    _ interface: InterfaceProjection,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> JSONProbe {
    try JSONProbe(data: try JSONEncoder().encode(interface))
}

func publicInterfaceProjection(
    interface: Interface,
    detail: InterfaceDetail,
    visibleElementBudget: Int = ButtonHeistRuntimeKnobs.current.visibleElementBudget,
    totalNodeBudget: Int = ButtonHeistRuntimeKnobs.current.totalNodeBudget
) -> InterfaceProjection {
    InterfaceProjection(
        interface: interface,
        detail: detail,
        visibleElementBudget: visibleElementBudget,
        totalNodeBudget: totalNodeBudget
    )
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
