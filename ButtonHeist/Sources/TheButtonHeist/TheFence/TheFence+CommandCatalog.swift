import Foundation
import TheScore

extension TheFence {

    public enum Command: String, CaseIterable, Sendable {
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

public extension TheFence.Command {
    var descriptor: FenceCommandDescriptor { Self.descriptor(for: self) }

    static var descriptors: [FenceCommandDescriptor] { allCases.map(descriptor(for:)) }

    static var cliDirectCommandDescriptors: [FenceCommandDescriptor] {
        descriptors.filter { $0.cliExposure == .directCommand }
    }

    static var batchExecutableCases: [Self] {
        allCases.filter { command in
            command != .runBatch && command.descriptor.isBatchExecutable
        }
    }

}

extension TheFence.Command {
    static func descriptor(for command: Self) -> FenceCommandDescriptor {
        command.catalogDescriptor
    }

    private var catalogDescriptor: FenceCommandDescriptor {
        let target = FenceParameterBlocks.elementTarget
        let scrollContainerTarget = FenceParameterBlocks.scrollContainerTarget
        let filter = FenceParameterBlocks.elementFilter
        let expect = FenceParameterBlocks.expect
        let expectation = FenceParameterBlocks.expectation
        let duration = FenceParameterBlocks.gestureDuration

        switch self {
        case .ping:
            return descriptor(
                requiresConnectionBeforeDispatch: false,
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true),
                description: "Check connection health without reading accessibility state."
            )
        case .listDevices:
            return descriptor(
                requiresConnectionBeforeDispatch: false,
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true),
                description: "List discovered iOS devices and configured connection targets."
            )
        case .getInterface:
            return descriptor(
                parameters: filter + [
                    FenceParameterBlocks.interfaceSubtree,
                    param(.detail, .string, enumValues: fenceEnumValues(InterfaceDetail.self)),
                ],
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true),
                description: "Read the app accessibility hierarchy, optionally scoped to a subtree."
            )
        case .getScreen:
            return descriptor(
                parameters: [param(.output, .string), param(.inlineData, .boolean), param(.includeInterface, .boolean)],
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true),
                description: "Capture a PNG screenshot with optional inline data and interface state."
            )
        case .waitForChange:
            return descriptor(
                isBatchExecutable: true,
                parameters: expectation,
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true),
                description: "Wait for any UI change or for an expectation to become true."
            )
        case .oneFingerTap:
            return descriptor(
                isBatchExecutable: true,
                parameters: target + FenceParameterBlocks.coordinateXY + expectation,
                description: "Tap a coordinate or semantic target after actionability resolution."
            )
        case .longPress:
            return descriptor(
                isBatchExecutable: true,
                parameters: target + FenceParameterBlocks.coordinateXY + [duration] + expectation,
                description: "Long-press a coordinate or semantic target for a resolved duration."
            )
        case .swipe:
            return descriptor(
                isBatchExecutable: true,
                parameters: target + [
                    param(.direction, .string, enumValues: fenceEnumValues(SwipeDirection.self)),
                    param(.start, .object, objectProperties: FenceParameterBlocks.unitPoint),
                    param(.end, .object, objectProperties: FenceParameterBlocks.unitPoint),
                ] + FenceParameterBlocks.optionalStart + FenceParameterBlocks.optionalEnd + [duration] + expectation,
                description: "Swipe in a direction or between explicit points; semantic targets are made actionable first."
            )
        case .drag:
            return descriptor(
                isBatchExecutable: true,
                parameters: target + FenceParameterBlocks.requiredEnd + FenceParameterBlocks.optionalStart + [duration] + expectation,
                description: "Drag from one point to another using explicit coordinates or a semantic target."
            )
        case .scroll:
            return descriptor(
                isBatchExecutable: true,
                parameters: scrollContainerTarget + target + [
                    param(
                        .direction, .string,
                        enumValues: fenceEnumValues(ScrollDirection.self),
                        defaultValue: .string(ScrollDirection.down.rawValue)
                    ),
                ] + expectation,
                description: "Scroll one page in a selected container or semantic target's owning scroll ancestor."
            )
        case .scrollToVisible:
            return descriptor(
                isBatchExecutable: true,
                parameters: target + expectation,
                description: "Make a semantic target actionable and report its fresh geometry."
            )
        case .elementSearch:
            return descriptor(
                isBatchExecutable: true,
                parameters: target + [
                    param(.direction, .string, enumValues: fenceEnumValues(ScrollDirection.self)),
                ] + expectation,
                description: "Search scrollable content for a semantic element match without performing an action."
            )
        case .scrollToEdge:
            return descriptor(
                isBatchExecutable: true,
                parameters: scrollContainerTarget + target + [
                    param(
                        .edge, .string,
                        enumValues: fenceEnumValues(ScrollEdge.self),
                        defaultValue: .string(ScrollEdge.top.rawValue)
                    ),
                ] + expectation,
                description: "Scroll the selected container, or the target's owning scroll ancestor, to a requested edge."
            )
        case .activate:
            return descriptor(
                isBatchExecutable: true,
                parameters: target + [param(.action, .string), FenceParameterBlocks.incrementCount] + expectation,
                description: "Activate a semantic UI element or one of its named accessibility actions."
            )
        case .rotor:
            return descriptor(
                isBatchExecutable: true,
                parameters: target + [
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
                ] + expectation,
                description: "Move through an element rotor using direction and continuation metadata."
            )
        case .typeText:
            return descriptor(
                isBatchExecutable: true,
                parameters: target + [param(.text, .string, required: true, minLength: 1)] + expectation,
                description: "Type non-empty text, optionally after making a semantic target actionable."
            )
        case .editAction:
            return descriptor(
                isBatchExecutable: true,
                parameters: [param(.action, .string, required: true, enumValues: fenceEnumValues(EditAction.self))] + expectation,
                description: "Perform an edit action on the current first responder."
            )
        case .setPasteboard:
            return descriptor(
                isBatchExecutable: true,
                parameters: [param(.text, .string, required: true)] + expectation,
                description: "Write text to the general pasteboard from within the app."
            )
        case .getPasteboard:
            return descriptor(
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true),
                description: "Read text from the general pasteboard."
            )
        case .waitFor:
            return descriptor(
                isBatchExecutable: true,
                parameters: target + [param(.absent, .boolean), FenceParameterBlocks.expectationTimeout, expect],
                description: "Wait for a semantic element to appear or disappear."
            )
        case .dismissKeyboard:
            return descriptor(
                isBatchExecutable: true,
                parameters: expectation,
                description: "Dismiss the on-screen keyboard through the current first responder or keyboard action path."
            )
        case .runBatch:
            return descriptor(
                parameters: [
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
                ],
                description: "Execute ordered command steps with batch policy and per-step expectations."
            )
        case .getSessionState:
            return descriptor(
                requiresConnectionBeforeDispatch: false,
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true),
                description: "Inspect connection, device, and last-action session state."
            )
        case .connect:
            return descriptor(
                requiresConnectionBeforeDispatch: false,
                parameters: [param(.target, .string), param(.device, .string), param(.token, .string)],
                description: "Establish or switch the active connection to a Button Heist app."
            )
        case .listTargets:
            return descriptor(
                requiresConnectionBeforeDispatch: false,
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true),
                description: "List configured connection targets and the default target."
            )
        case .startHeist:
            return descriptor(
                requiresConnectionBeforeDispatch: false,
                parameters: [param(.app, .string), param(.identifier, .string)],
                description: "Start recording replayable heist steps from successful commands."
            )
        case .stopHeist:
            return descriptor(
                requiresConnectionBeforeDispatch: false,
                parameters: [param(.output, .string, required: true)],
                description: "Stop heist recording and save a deterministic heist fixture."
            )
        case .playHeist:
            return descriptor(
                parameters: [param(.input, .string, required: true)],
                description: "Play back a heist file and return step diagnostics on failure."
            )
        }
    }

    private func descriptor(
        cliExposure: CLIExposure = .directCommand,
        mcpExposure: MCPExposure = .directTool,
        isBatchExecutable: Bool = false,
        requiresConnectionBeforeDispatch: Bool = true,
        parameters: [FenceParameterSpec] = [],
        mcpAnnotations: MCPToolAnnotationSpec? = nil,
        description: String
    ) -> FenceCommandDescriptor {
        FenceCommandDescriptor(
            command: self,
            cliExposure: cliExposure,
            mcpExposure: mcpExposure,
            isBatchExecutable: isBatchExecutable,
            requiresConnectionBeforeDispatch: requiresConnectionBeforeDispatch,
            parameters: parameters,
            mcpAnnotations: mcpAnnotations,
            description: description
        )
    }
}
