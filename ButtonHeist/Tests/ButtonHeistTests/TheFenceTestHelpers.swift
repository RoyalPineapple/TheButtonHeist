import ButtonHeistTestSupport
import XCTest
import ThePlans
import Network
import AccessibilitySnapshotModel
@testable import ButtonHeist
@_spi(ButtonHeistInternals) import TheScore

// Shared fixtures and helpers for TheFence test classes. Keeps tests focused
// on behavior rather than repeating the connected-fence construction dance.

enum TheFenceFixtures {
    static let testDevice = DiscoveredDevice(
        id: "mock-device",
        name: "MockApp#test",
        endpoint: NWEndpoint.hostPort(host: .ipv6(.loopback), port: 1)
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
    func execute(command: Command, values: [String: HeistValue] = [:]) async throws -> FenceResponse {
        try await execute(command: command, arguments: CommandArgumentEnvelope(values: values))
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

extension Array where Element == (ClientMessage, String?) {
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

    /// The sent heist plan's body resolved back to runtime actions (action and
    /// wait steps) — what the in-app runtime dispatches after the public wire
    /// receives a one-step plan.
    var sentPlanMessages: [RuntimeActionMessage] {
        guard let plan = sentHeistPlan else { return [] }
        return plan.body.compactMap { step in
            switch step {
            case .action(let action):
                return try? action.command.resolveForRuntimeDispatch(in: .empty)
            case .wait(let wait):
                guard let resolved = try? wait.resolve(in: .empty) else { return nil }
                return .wait(WaitTarget(predicate: resolved.predicate, timeout: resolved.timeout))
            default:
                return nil
            }
        }
    }
}

func semanticTarget(
    label: String? = nil,
    identifier: String? = nil,
    value: String? = nil,
    traits: [HeistTrait]? = nil,
    excludeTraits: [HeistTrait]? = nil,
    ordinal: Int? = nil
) -> ElementTarget {
    .predicate(
        ElementPredicate(
            label: label.map(StringMatch.exact),
            identifier: identifier.map(StringMatch.exact),
            value: value.map(StringMatch.exact),
            traits: traits ?? [],
            excludeTraits: excludeTraits ?? []
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
    excludeTraits: [String]? = nil,
    ordinal: Int? = nil
) -> HeistValue {
    var target: [String: HeistValue] = [:]
    if let label { target["label"] = stringMatchArgumentValue(label) }
    if let identifier { target["identifier"] = stringMatchArgumentValue(identifier) }
    if let value { target["value"] = stringMatchArgumentValue(value) }
    if let traits { target["traits"] = .array(traits.map { .string($0) }) }
    if let excludeTraits { target["excludeTraits"] = .array(excludeTraits.map { .string($0) }) }
    if let ordinal { target["ordinal"] = .int(ordinal) }
    return .object(target)
}

func stringMatchArgumentValue(_ value: String, mode: String = "exact") -> HeistValue {
    .object([
        "mode": .string(mode),
        "value": .string(value),
    ])
}

struct TestHeistElementBuilder {
    var description: String?
    var label: String?
    var value: String?
    var identifier: String?
    var hint: String?
    var traits: [HeistTrait]
    var frameX: Double
    var frameY: Double
    var frameWidth: Double
    var frameHeight: Double
    var activationPointX: Double?
    var activationPointY: Double?
    var respondsToUserInteraction: Bool
    var customContent: [HeistCustomContent]?
    var rotors: [HeistRotor]?
    var actions: [ElementAction]?

    init(
        label: String? = "Element",
        value: String? = nil,
        identifier: String? = nil,
        hint: String? = nil,
        traits: [HeistTrait] = [.staticText],
        frameX: Double = 0,
        frameY: Double = 0,
        frameWidth: Double = 100,
        frameHeight: Double = 44,
        activationPointX: Double? = nil,
        activationPointY: Double? = nil,
        respondsToUserInteraction: Bool = true,
        customContent: [HeistCustomContent]? = nil,
        rotors: [HeistRotor]? = nil,
        actions: [ElementAction]? = nil
    ) {
        self.description = label
        self.label = label
        self.value = value
        self.identifier = identifier
        self.hint = hint
        self.traits = traits
        self.frameX = frameX
        self.frameY = frameY
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
        self.activationPointX = activationPointX
        self.activationPointY = activationPointY
        self.respondsToUserInteraction = respondsToUserInteraction
        self.customContent = customContent
        self.rotors = rotors
        self.actions = actions
    }

    func build() -> HeistElement {
        HeistElement(
            description: description ?? label ?? identifier ?? "Element",
            label: label,
            value: value,
            identifier: identifier,
            hint: hint,
            traits: traits,
            frameX: frameX,
            frameY: frameY,
            frameWidth: frameWidth,
            frameHeight: frameHeight,
            activationPointX: activationPointX,
            activationPointY: activationPointY,
            respondsToUserInteraction: respondsToUserInteraction,
            customContent: customContent,
            rotors: rotors,
            actions: actions ?? defaultActions
        )
    }

    private var defaultActions: [ElementAction] {
        traits.contains(.button) ? [.activate] : []
    }
}

struct TestInterfaceBuilder {
    enum Node {
        case element(HeistElement)
        case container(AccessibilityContainer, containerName: ContainerName? = nil, children: [Node])
    }

    var nodes: [Node]
    var timestamp: Date

    init(
        nodes: [Node],
        timestamp: Date = Date(timeIntervalSince1970: 0)
    ) {
        self.nodes = nodes
        self.timestamp = timestamp
    }

    init(
        elements: [HeistElement],
        timestamp: Date = Date(timeIntervalSince1970: 0)
    ) {
        self.init(nodes: elements.map(Node.element), timestamp: timestamp)
    }

    func build() -> Interface {
        var traversalIndex = 0
        var elementAnnotations: [InterfaceElementAnnotation] = []
        var containerAnnotations: [InterfaceContainerAnnotation] = []

        func convert(_ node: Node, path: TreePath) -> AccessibilityHierarchy {
            switch node {
            case .element(let element):
                let index = traversalIndex
                traversalIndex += 1
                elementAnnotations.append(InterfaceElementAnnotation(
                    path: path,
                    actions: element.actions
                ))
                return .element(Self.accessibilityElement(element), traversalIndex: index)

            case .container(let container, let containerName, let children):
                containerAnnotations.append(InterfaceContainerAnnotation(path: path, containerName: containerName))
                return .container(
                    container,
                    children: children.enumerated().map { index, child in
                        convert(child, path: path.appending(index))
                    }
                )
            }
        }

        return Interface(
            timestamp: timestamp,
            tree: nodes.enumerated().map { index, node in
                convert(node, path: TreePath([index]))
            },
            annotations: InterfaceAnnotations(elements: elementAnnotations, containers: containerAnnotations)
        )
    }

    private static func accessibilityElement(_ element: HeistElement) -> AccessibilityElement {
        AccessibilityElement(
            description: element.description,
            label: element.label,
            value: element.value,
            traits: AccessibilityTraits.fromNames(element.traits.map(\.rawValue)),
            identifier: element.identifier,
            hint: element.hint,
            userInputLabels: nil,
            shape: .frame(AccessibilityRect(
                x: element.frameX,
                y: element.frameY,
                width: element.frameWidth,
                height: element.frameHeight
            )),
            activationPoint: AccessibilityPoint(x: element.activationPointX, y: element.activationPointY),
            usesDefaultActivationPoint: true,
            customActions: [],
            customContent: element.customContent?.map {
                AccessibilityElement.CustomContent(
                    label: $0.label,
                    value: $0.value,
                    isImportant: $0.isImportant
                )
            } ?? [],
            customRotors: element.rotors?.map { AccessibilityElement.CustomRotor(name: $0.name) } ?? [],
            accessibilityLanguage: nil,
            respondsToUserInteraction: element.respondsToUserInteraction
        )
    }
}

typealias ReceiptTestInterfaceNode = TestInterfaceBuilder.Node

@ButtonHeistActor
func makeConnectedFence(configuration: TheFence.Configuration = .init()) -> (TheFence, MockConnection) {
    let mockConn = MockConnection()
    mockConn.serverInfo = TheFenceFixtures.testServerInfo
    mockConn.autoResponse = { message in
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
        default:
            return .actionResult(ActionResult(success: true, method: .activate))
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
    label: String,
    value: String? = nil,
    identifier: String? = nil,
    traits: [HeistTrait] = [.staticText],
    actions: [ElementAction] = []
) -> HeistElement {
    TestHeistElementBuilder(
        label: label,
        value: value,
        identifier: identifier,
        traits: traits,
        actions: actions
    ).build()
}

func makeReceiptTestInterface(
    _ elements: [HeistElement],
    timestamp: Date = Date(timeIntervalSince1970: 0)
) -> Interface {
    TestInterfaceBuilder(elements: elements, timestamp: timestamp).build()
}

func makeReceiptTestInterface(
    nodes: [ReceiptTestInterfaceNode],
    timestamp: Date = Date(timeIntervalSince1970: 0)
) -> Interface {
    TestInterfaceBuilder(nodes: nodes, timestamp: timestamp).build()
}

func makeTestInterface(
    elements: [HeistElement],
    timestamp: Date = Date(timeIntervalSince1970: 0)
) -> Interface {
    makeReceiptTestInterface(elements, timestamp: timestamp)
}

func makeReceiptTestContainer(
    type: AccessibilityContainer.ContainerType = .semanticGroup(label: nil, value: nil, identifier: nil),
    frameX: Double = 0,
    frameY: Double = 0,
    frameWidth: Double = 100,
    frameHeight: Double = 100,
    isModalBoundary: Bool = false
) -> AccessibilityContainer {
    AccessibilityContainer(
        type: type,
        frame: AccessibilityRect(x: frameX, y: frameY, width: frameWidth, height: frameHeight),
        isModalBoundary: isModalBoundary
    )
}

func makeReceiptTestSemanticContainer(
    label: String? = nil,
    value: String? = nil,
    identifier: String? = nil,
    frameX: Double = 0,
    frameY: Double = 0,
    frameWidth: Double = 100,
    frameHeight: Double = 100,
    isModalBoundary: Bool = false
) -> AccessibilityContainer {
    makeReceiptTestContainer(
        type: .semanticGroup(label: label, value: value, identifier: identifier),
        frameX: frameX,
        frameY: frameY,
        frameWidth: frameWidth,
        frameHeight: frameHeight,
        isModalBoundary: isModalBoundary
    )
}

func makeReceiptTestScrollableContainer(
    contentWidth: Double,
    contentHeight: Double,
    frameX: Double = 0,
    frameY: Double = 0,
    frameWidth: Double = 100,
    frameHeight: Double = 100,
    isModalBoundary: Bool = false
) -> AccessibilityContainer {
    makeReceiptTestContainer(
        type: .scrollable(contentSize: AccessibilitySize(width: contentWidth, height: contentHeight)),
        frameX: frameX,
        frameY: frameY,
        frameWidth: frameWidth,
        frameHeight: frameHeight,
        isModalBoundary: isModalBoundary
    )
}

func makeReceiptTestInterface(
    elementCount: Int,
    prefix: String = "element",
    timestamp: Date = Date(timeIntervalSince1970: 0)
) -> Interface {
    makeReceiptTestInterface(
        (0..<elementCount).map { makeReceiptTestElement(label: "\(prefix) \($0)") },
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

func makeTestHeistActionStep(
    path: String = "$.body[0]",
    command: HeistActionCommand? = nil,
    result: ActionResult = makeTestActionResult(),
    expectationActionResult: ActionResult? = nil,
    expectation: ExpectationResult? = nil,
    durationMs: Int = 1
) -> HeistExecutionStepResult {
    HeistExecutionStepResult(
        path: path,
        kind: .action,
        status: result.success ? .passed : .failed,
        durationMs: durationMs,
        evidence: .action(HeistActionEvidence(
            command: command,
            actionResult: result,
            expectationActionResult: expectationActionResult,
            expectation: expectation
        ))
    )
}

func makeBackgroundElementsChangedTrace(elementCount: Int) -> AccessibilityTrace {
    let interface = makeReceiptTestInterface(elementCount: elementCount)
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
    makeReceiptTestTrace(
        before: makeReceiptTestInterface(elementCount: 0, prefix: "before"),
        after: makeReceiptTestInterface(elementCount: elementCount, prefix: "after"),
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
    let abortedAtPath: String?
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
        switch self {
        case .activate, .increment, .decrement, .customAction:
            return .activate
        case .rotor:
            return .rotor
        case .mechanicalTap:
            return .oneFingerTap
        case .mechanicalLongPress:
            return .longPress
        case .mechanicalSwipe:
            return .swipe
        case .mechanicalDrag:
            return .drag
        case .typeText:
            return .typeText
        case .editAction:
            return .editAction
        case .setPasteboard:
            return .setPasteboard
        case .takeScreenshot:
            return .getScreen
        case .viewportScroll:
            return .scroll
        case .viewportScrollToVisible:
            return .scrollToVisible
        case .viewportScrollToEdge:
            return .scrollToEdge
        case .dismissKeyboard:
            return .dismissKeyboard
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
