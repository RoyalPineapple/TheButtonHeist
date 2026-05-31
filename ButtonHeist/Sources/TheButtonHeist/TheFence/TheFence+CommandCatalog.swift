import Foundation
import TheScore

extension TheFence {

    public enum Command: String, CaseIterable, Sendable {
        case help
        case ping
        case listDevices = "list_devices"
        case getInterface = "get_interface"
        case getScreen = "get_screen"
        case waitForChange = "wait_for_change"
        case oneFingerTap = "one_finger_tap"
        case longPress = "long_press"
        case swipe
        case drag
        case scroll
        case scrollToVisible = "scroll_to_visible"
        case elementSearch = "element_search"
        case scrollToEdge = "scroll_to_edge"
        case activate
        case rotor
        case typeText = "type_text"
        case editAction = "edit_action"
        case setPasteboard = "set_pasteboard"
        case getPasteboard = "get_pasteboard"
        case waitFor = "wait_for"
        case dismissKeyboard = "dismiss_keyboard"
        case runBatch = "run_batch"
        case getSessionState = "get_session_state"
        case connect
        case listTargets = "list_targets"
        case startHeist = "start_heist"
        case stopHeist = "stop_heist"
        case playHeist = "play_heist"
    }
}

public struct FenceCommandDescriptor: Sendable, Equatable {
    public let command: TheFence.Command
    public let cliExposure: CLIExposure
    public let mcpExposure: MCPExposure
    public let isBatchExecutable: Bool
    public let requiresConnectionBeforeDispatch: Bool
    public let parameters: [FenceParameterSpec]
    public let mcpAnnotations: MCPToolAnnotationSpec?
    public let description: String

    public var isPublicRequestContract: Bool {
        cliExposure != .notExposed || mcpExposure != .notExposed || isBatchExecutable
    }

    public var elementTargetParameterKeys: [String] {
        let elementTargetKeys = Set(FenceParameterBlocks.elementTarget.map(\.key))
        return parameters.map(\.key).filter(elementTargetKeys.contains)
    }

    public func parameter(named key: FenceParameterKey) -> FenceParameterSpec? {
        parameters.first { $0.key == key.rawValue }
    }

    public func defaultArgumentValue(for key: FenceParameterKey) -> HeistValue? {
        parameter(named: key)?.defaultValue
    }

    public init(
        command: TheFence.Command,
        cliExposure: CLIExposure,
        mcpExposure: MCPExposure,
        isBatchExecutable: Bool,
        requiresConnectionBeforeDispatch: Bool = true,
        parameters: [FenceParameterSpec],
        mcpAnnotations: MCPToolAnnotationSpec? = nil,
        description: String
    ) {
        self.command = command
        self.cliExposure = cliExposure
        self.mcpExposure = mcpExposure
        self.isBatchExecutable = isBatchExecutable
        self.requiresConnectionBeforeDispatch = requiresConnectionBeforeDispatch
        self.parameters = parameters
        self.mcpAnnotations = mcpAnnotations
        self.description = description
    }
}

private struct FenceCommandCatalogEntry {
    var cliExposure: CLIExposure = .directCommand
    var mcpExposure: MCPExposure = .directTool
    var isBatchExecutable = false
    var requiresConnectionBeforeDispatch = true
    var parameters: [FenceParameterSpec] = []
    var mcpAnnotations: MCPToolAnnotationSpec?
    var description = ""
}

public extension TheFence.Command {
    var descriptor: FenceCommandDescriptor { Self.descriptor(for: self) }

    static var descriptors: [FenceCommandDescriptor] { allCases.map(descriptor(for:)) }

    static var cliDirectCommandDescriptors: [FenceCommandDescriptor] {
        descriptors.filter { $0.cliExposure == .directCommand }
    }

    static var batchExecutableCases: [Self] {
        allCases.filter { command in
            command != .runBatch && command.catalogEntry.isBatchExecutable
        }
    }

}

extension TheFence.Command {
    static func descriptor(for command: Self) -> FenceCommandDescriptor {
        let entry = command.catalogEntry
        return FenceCommandDescriptor(
            command: command,
            cliExposure: entry.cliExposure,
            mcpExposure: entry.mcpExposure,
            isBatchExecutable: entry.isBatchExecutable,
            requiresConnectionBeforeDispatch: entry.requiresConnectionBeforeDispatch,
            parameters: entry.parameters,
            mcpAnnotations: entry.mcpAnnotations,
            description: entry.description
        )
    }

    private var catalogEntry: FenceCommandCatalogEntry {
        var entry = FenceCommandCatalogEntry()
        let target = FenceParameterBlocks.elementTarget
        let scrollContainerTarget = FenceParameterBlocks.scrollContainerTarget
        let filter = FenceParameterBlocks.elementFilter
        let expect = FenceParameterBlocks.expect
        let expectation = FenceParameterBlocks.expectation
        let duration = FenceParameterBlocks.gestureDuration

        switch self {
        case .help:
            entry.cliExposure = .sessionOnly
            entry.mcpExposure = .notExposed
            entry.requiresConnectionBeforeDispatch = false
            entry.description = "Return descriptor-backed help for the current Button Heist command surface."
        case .ping:
            entry.requiresConnectionBeforeDispatch = false
            entry.mcpAnnotations = MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
            entry.description = "Check connection health without reading accessibility state."
        case .listDevices:
            entry.requiresConnectionBeforeDispatch = false
            entry.mcpAnnotations = MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
            entry.description = "List discovered iOS devices and configured connection targets."
        case .getInterface:
            entry.mcpAnnotations = MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
            entry.parameters = filter + [
                FenceParameterBlocks.interfaceSubtree,
                param(.detail, .string, enumValues: fenceEnumValues(InterfaceDetail.self)),
            ]
            entry.description = "Read the app accessibility hierarchy, optionally scoped to a subtree."
        case .getScreen:
            entry.mcpAnnotations = MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
            entry.parameters = [param(.output, .string), param(.inlineData, .boolean), param(.includeInterface, .boolean)]
            entry.description = "Capture a PNG screenshot with optional inline data and interface state."
        case .waitForChange:
            entry.isBatchExecutable = true
            entry.mcpAnnotations = MCPToolAnnotationSpec(readOnlyHint: true)
            entry.parameters = expectation
            entry.description = "Wait for any UI change or for an expectation to become true."
        case .oneFingerTap:
            entry.isBatchExecutable = true
            entry.parameters = target + FenceParameterBlocks.coordinateXY + expectation
            entry.description = "Tap a coordinate or semantic target after actionability resolution."
        case .longPress:
            entry.isBatchExecutable = true
            entry.parameters = target + FenceParameterBlocks.coordinateXY + [duration] + expectation
            entry.description = "Long-press a coordinate or semantic target for a resolved duration."
        case .swipe:
            entry.isBatchExecutable = true
            entry.parameters = target + [
                param(.direction, .string, enumValues: fenceEnumValues(SwipeDirection.self)),
                param(.start, .object, objectProperties: FenceParameterBlocks.unitPoint),
                param(.end, .object, objectProperties: FenceParameterBlocks.unitPoint),
            ] + FenceParameterBlocks.optionalStart + FenceParameterBlocks.optionalEnd + [duration] + expectation
            entry.description = "Swipe in a direction or between explicit points; semantic targets are made actionable first."
        case .drag:
            entry.isBatchExecutable = true
            entry.parameters = target + FenceParameterBlocks.requiredEnd + FenceParameterBlocks.optionalStart + [duration] + expectation
            entry.description = "Drag from one point to another using explicit coordinates or a semantic target."
        case .scroll:
            entry.isBatchExecutable = true
            entry.parameters = scrollContainerTarget + target + [
                param(
                    .direction, .string,
                    enumValues: fenceEnumValues(ScrollDirection.self),
                    defaultValue: .string(ScrollDirection.down.rawValue)
                ),
            ] + expectation
            entry.description = "Scroll one page in a selected container or semantic target's owning scroll ancestor."
        case .scrollToVisible:
            entry.isBatchExecutable = true
            entry.parameters = target + expectation
            entry.description = "Make a semantic target actionable and report its fresh geometry."
        case .elementSearch:
            entry.isBatchExecutable = true
            entry.parameters = target + [
                param(.direction, .string, enumValues: fenceEnumValues(ScrollSearchDirection.self)),
            ] + expectation
            entry.description = "Search scrollable content for a semantic element match without performing an action."
        case .scrollToEdge:
            entry.isBatchExecutable = true
            entry.parameters = scrollContainerTarget + target + [
                param(
                    .edge, .string,
                    enumValues: fenceEnumValues(ScrollEdge.self),
                    defaultValue: .string(ScrollEdge.top.rawValue)
                ),
            ] + expectation
            entry.description = "Scroll the selected container, or the target's owning scroll ancestor, to a requested edge."
        case .activate:
            entry.isBatchExecutable = true
            entry.parameters = target + [param(.action, .string), FenceParameterBlocks.incrementCount] + expectation
            entry.description = "Activate a semantic UI element or one of its named accessibility actions."
        case .rotor:
            entry.isBatchExecutable = true
            entry.parameters = target + [
                param(.rotor, .string),
                param(.rotorIndex, .integer, minimum: 0),
                param(
                    .direction, .string,
                    enumValues: fenceEnumValues(RotorDirection.self),
                    defaultValue: .string(RotorDirection.next.rawValue)
                ),
                param(
                    .continuation,
                    .object,
                    objectProperties: [
                        param(.heistId, .string, required: true),
                        param(
                            .textRange,
                            .object,
                            objectProperties: [
                                param(.startOffset, .integer, required: true, minimum: 0),
                                param(.endOffset, .integer, required: true, minimum: 0),
                            ]
                        ),
                    ]
                ),
            ] + expectation
            entry.description = "Move through an element rotor using direction and continuation metadata."
        case .typeText:
            entry.isBatchExecutable = true
            entry.parameters = target + [param(.text, .string, required: true, minLength: 1)] + expectation
            entry.description = "Type non-empty text, optionally after making a semantic target actionable."
        case .editAction:
            entry.isBatchExecutable = true
            entry.parameters = [param(.action, .string, required: true, enumValues: fenceEnumValues(EditAction.self))] + expectation
            entry.description = "Perform an edit action on the current first responder."
        case .setPasteboard:
            entry.isBatchExecutable = true
            entry.parameters = [param(.text, .string, required: true)] + expectation
            entry.description = "Write text to the general pasteboard from within the app."
        case .getPasteboard:
            entry.mcpAnnotations = MCPToolAnnotationSpec(readOnlyHint: true)
            entry.description = "Read text from the general pasteboard."
        case .waitFor:
            entry.isBatchExecutable = true
            entry.parameters = target + [param(.absent, .boolean), FenceParameterBlocks.expectationTimeout, expect]
            entry.description = "Wait for a semantic element to appear or disappear."
        case .dismissKeyboard:
            entry.isBatchExecutable = true
            entry.parameters = expectation
            entry.description = "Dismiss the on-screen keyboard through the current first responder or keyboard action path."
        case .runBatch:
            entry.parameters = [
                param(
                    .steps, .array, required: true,
                    minItems: 1,
                    maxItems: TheFence.DecodeLimits.maxRunBatchSteps,
                    arrayItemType: .object,
                    arrayItemProperties: [
                        param(
                            .command, .string, required: true,
                            enumValues: Self.batchExecutableCases.map(\.rawValue)
                        ),
                        expect,
                    ],
                    arrayItemAdditionalProperties: true
                ),
                param(.policy, .string, enumValues: fenceEnumValues(BatchExecutionPolicy.self)),
            ]
            entry.description = "Execute ordered command steps with batch policy and per-step expectations."
        case .getSessionState:
            entry.requiresConnectionBeforeDispatch = false
            entry.mcpAnnotations = MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
            entry.description = "Inspect connection, device, and last-action session state."
        case .connect:
            entry.requiresConnectionBeforeDispatch = false
            entry.parameters = [param(.target, .string), param(.device, .string), param(.token, .string)]
            entry.description = "Establish or switch the active connection to a Button Heist app."
        case .listTargets:
            entry.requiresConnectionBeforeDispatch = false
            entry.mcpAnnotations = MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
            entry.description = "List configured connection targets and the default target."
        case .startHeist:
            entry.requiresConnectionBeforeDispatch = false
            entry.parameters = [param(.app, .string), param(.identifier, .string)]
            entry.description = "Start recording replayable heist steps from successful commands."
        case .stopHeist:
            entry.requiresConnectionBeforeDispatch = false
            entry.parameters = [param(.output, .string, required: true)]
            entry.description = "Stop heist recording and save a deterministic heist fixture."
        case .playHeist:
            entry.parameters = [param(.input, .string, required: true)]
            entry.description = "Play back a heist file and return step diagnostics on failure."
        }
        return entry
    }
}
