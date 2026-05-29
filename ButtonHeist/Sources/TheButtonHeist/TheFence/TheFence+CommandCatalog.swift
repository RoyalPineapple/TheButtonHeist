import Foundation
import TheScore

extension TheFence {

    /// Canonical set of all commands supported by TheFence (CLI and MCP).
    public enum Command: String, CaseIterable, Sendable {
        case help
        case ping
        case quit
        case listDevices = "list_devices"
        case getInterface = "get_interface"
        case getScreen = "get_screen"
        case waitForChange = "wait_for_change"
        case oneFingerTap = "one_finger_tap"
        case longPress = "long_press"
        case swipe
        case drag
        case pinch
        case rotate
        case twoFingerTap = "two_finger_tap"
        case drawPath = "draw_path"
        case drawBezier = "draw_bezier"
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
        case startRecording = "start_recording"
        case stopRecording = "stop_recording"
        case runBatch = "run_batch"
        case getSessionState = "get_session_state"
        case connect
        case listTargets = "list_targets"
        case getSessionLog = "get_session_log"
        case archiveSession = "archive_session"
        case startHeist = "start_heist"
        case stopHeist = "stop_heist"
        case playHeist = "play_heist"
    }
}

/// Canonical command descriptor for TheFence command surfaces.
///
/// The enum is the stable wire identity. This descriptor owns the contract
/// projected from that identity: adapter exposure, batch eligibility,
/// parameter shape, and user-facing help text.
public struct FenceCommandDescriptor: Sendable, Equatable {
    public let command: TheFence.Command
    public var canonicalName: String { command.rawValue }
    public let requestPayloadKind: FenceRequestPayloadKind
    public let cliExposure: CLIExposure
    public let mcpExposure: MCPExposure
    public let isBatchExecutable: Bool
    public let requiresConnectionBeforeDispatch: Bool
    public let humanPositionalSyntax: FenceHumanPositionalSyntax
    public let parameters: [FenceParameterSpec]
    public let mcpAnnotations: MCPToolAnnotationSpec?
    public let description: String

    public var isPublicRequestContract: Bool {
        cliExposure != .notExposed || mcpExposure != .notExposed || isBatchExecutable
    }

    /// Parameter keys that identify an element target for this command.
    ///
    /// Adapters use this projection when they need to talk about target matcher
    /// fields without knowing how the catalog orders or composes parameter blocks.
    public var elementTargetParameterKeys: [String] {
        let elementTargetKeys = Set(FenceParameterBlocks.elementTarget.map(\.key))
        return parameters.map(\.key).filter(elementTargetKeys.contains)
    }

    public init(
        command: TheFence.Command,
        requestPayloadKind: FenceRequestPayloadKind,
        cliExposure: CLIExposure,
        mcpExposure: MCPExposure,
        isBatchExecutable: Bool,
        requiresConnectionBeforeDispatch: Bool = true,
        humanPositionalSyntax: FenceHumanPositionalSyntax = .target,
        parameters: [FenceParameterSpec],
        mcpAnnotations: MCPToolAnnotationSpec? = nil,
        description: String
    ) {
        self.command = command
        self.requestPayloadKind = requestPayloadKind
        self.cliExposure = cliExposure
        self.mcpExposure = mcpExposure
        self.isBatchExecutable = isBatchExecutable
        self.requiresConnectionBeforeDispatch = requiresConnectionBeforeDispatch
        self.humanPositionalSyntax = humanPositionalSyntax
        self.parameters = parameters
        self.mcpAnnotations = mcpAnnotations
        self.description = description
    }
}

/// Catalog-owned request payload family for a Fence command.
///
/// This keeps request parsing routed by command metadata instead of a separate
/// switch in request decoding. The individual family decoders still own field
/// validation for their typed payloads.
public enum FenceRequestPayloadKind: Sendable, Equatable {
    case none
    case observation
    case waitForChange
    case gesture
    case elementAction
    case session
}

/// Catalog-owned positional grammar for the CLI's human command parser.
///
/// The CLI still owns tokenization and key=value parsing. Command-specific
/// meaning for positional tokens lives here so adapters do not mirror command
/// identity or parameter roles.
public enum FenceHumanPositionalSyntax: Sendable, Equatable {
    case target
    case joinedText(FenceParameterKey)
    case firstToken(FenceParameterKey)
    case targetThenJoinedText(FenceParameterKey)
    case leadingDirectionThenTarget(Set<String>)
    case leadingEdgeThenTarget(Set<String>)
}

private struct FenceCommandCatalogEntry {
    var requestPayloadKind: FenceRequestPayloadKind = .none
    var cliExposure: CLIExposure = .directCommand
    var mcpExposure: MCPExposure = .directTool
    var isBatchExecutable = false
    var requiresConnectionBeforeDispatch = true
    var humanPositionalSyntax: FenceHumanPositionalSyntax = .target
    var parameters: [FenceParameterSpec] = []
    var mcpAnnotations: MCPToolAnnotationSpec?
    var description = ""
}

extension FenceCommandDescriptor {
    func executionTimeout(for request: TheFence.ParsedRequest) throws -> TimeInterval {
        if command == .getPasteboard {
            return Timeouts.healthSeconds
        }
        if command == .elementSearch || command == .typeText {
            return Timeouts.longActionSeconds
        }
        if command == .waitFor {
            guard case .waitFor(let target)? = request.executableMessages?.first else {
                throw FenceError.invalidRequest("command \"\(canonicalName)\" is missing wait_for payload")
            }
            return target.resolvedTimeout + 5
        }
        if command == .waitForChange {
            guard case .waitForChange(let target)? = request.executableMessages?.first else {
                throw FenceError.invalidRequest("command \"\(canonicalName)\" is missing wait_for_change payload")
            }
            return target.resolvedTimeout + 5
        }
        return Timeouts.actionSeconds
    }
}

public extension TheFence.Command {
    var descriptor: FenceCommandDescriptor {
        Self.descriptor(for: self)
    }

    static var descriptors: [FenceCommandDescriptor] {
        allCases.map(descriptor(for:))
    }

    static var cliDirectCommandDescriptors: [FenceCommandDescriptor] {
        descriptors.filter { $0.cliExposure == .directCommand }
    }

    var canonicalName: String {
        descriptor.canonicalName
    }

    var cliExposure: CLIExposure {
        descriptor.cliExposure
    }

    var mcpExposure: MCPExposure {
        descriptor.mcpExposure
    }

    var parameters: [FenceParameterSpec] {
        descriptor.parameters
    }

    var requestPayloadKind: FenceRequestPayloadKind {
        descriptor.requestPayloadKind
    }

    func parameter(named key: FenceParameterKey) -> FenceParameterSpec? {
        parameters.first { $0.key == key.rawValue }
    }

    func defaultArgumentValue(for key: FenceParameterKey) -> HeistValue? {
        parameter(named: key)?.defaultValue
    }

    var humanPositionalSyntax: FenceHumanPositionalSyntax {
        descriptor.humanPositionalSyntax
    }

    static let humanDirectionValues = Set(fenceEnumValues(ScrollDirection.self))

    static let humanScrollEdgeValues = Set(fenceEnumValues(ScrollEdge.self))

    /// Commands that can execute as a run_batch step.
    ///
    /// Session-control and batch-orchestration commands are accepted at
    /// external edges but should not appear in batch schemas or execution.
    var isBatchExecutable: Bool {
        descriptor.isBatchExecutable
    }

    static var batchExecutableCases: [Self] {
        allCases.filter { command in
            // runBatch builds its step schema from batchExecutableCases; skip it
            // before reading catalogEntry to avoid recursive catalog construction.
            command != .runBatch && command.catalogEntry.isBatchExecutable
        }
    }

    /// Commands that should establish a device connection before dispatch.
    var requiresConnectionBeforeDispatch: Bool {
        descriptor.requiresConnectionBeforeDispatch
    }

    static var mcpToolContracts: [MCPToolContract] {
        descriptors.compactMap { descriptor in
            guard descriptor.mcpExposure == .directTool else { return nil }
            return MCPToolContract(
                name: descriptor.canonicalName,
                description: descriptor.description,
                parameters: descriptor.parameters,
                annotations: descriptor.mcpAnnotations
            )
        }
    }

}

extension TheFence.Command {
    static func descriptor(for command: Self) -> FenceCommandDescriptor {
        let entry = command.catalogEntry
        return FenceCommandDescriptor(
            command: command,
            requestPayloadKind: entry.requestPayloadKind,
            cliExposure: entry.cliExposure,
            mcpExposure: entry.mcpExposure,
            isBatchExecutable: entry.isBatchExecutable,
            requiresConnectionBeforeDispatch: entry.requiresConnectionBeforeDispatch,
            humanPositionalSyntax: entry.humanPositionalSyntax,
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
            entry.description = """
                Check Button Heist connection health. Returns cheap static app/server identity facts \
                without reading UI hierarchy or accessibility state.
                """
        case .quit:
            entry.cliExposure = .sessionOnly
            entry.mcpExposure = .notExposed
            entry.description = "End the interactive CLI session."
        case .listDevices:
            entry.requiresConnectionBeforeDispatch = false
            entry.mcpAnnotations = MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
            entry.description = """
                List iOS devices discovered via Bonjour plus named targets from .buttonheist.json. \
                Empty when Bonjour is blocked and no config targets exist — use connect(device:token:) directly.
                """
        case .getInterface:
            entry.requestPayloadKind = .observation
            entry.mcpAnnotations = MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
            entry.parameters = filter + [
                FenceParameterBlocks.interfaceSubtree,
                param(.detail, .string, enumValues: fenceEnumValues(InterfaceDetail.self)),
            ]
            entry.description = """
                Read the app accessibility hierarchy. Call once on a new screen, then track changes via \
                action deltas — re-fetch only when you need elements the delta didn't cover. \
                Omit subtree for the whole hierarchy, or pass subtree to select the returned tree from \
                a selected leaf or container node.
                """
        case .getScreen:
            entry.requestPayloadKind = .observation
            entry.mcpAnnotations = MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
            entry.parameters = [param(.output, .string), param(.inlineData, .boolean), param(.includeInterface, .boolean)]
            entry.description = """
                Capture a PNG screenshot from the connected device. Returns metadata plus an artifact path \
                by default. Set inlineData=true to return capped base64 PNG data inline; set includeInterface=true \
                to include the fresh visible accessibility tree.
                """
        case .waitForChange:
            entry.requestPayloadKind = .waitForChange
            entry.isBatchExecutable = true
            entry.mcpAnnotations = MCPToolAnnotationSpec(readOnlyHint: true)
            entry.parameters = expectation
            entry.description = """
                Wait for the UI to change. With no expect, returns on any tree change. With expect, \
                rides through intermediate states (spinners, loading) until the expectation is met. \
                Use after an action whose delta showed a transient state and the expectation wasn't met yet.
                """
        case .oneFingerTap:
            entry.requestPayloadKind = .gesture
            entry.isBatchExecutable = true
            entry.parameters = target + FenceParameterBlocks.coordinateXY + expectation
            entry.description = "Tap a coordinate or semantic target after actionability resolution."
        case .longPress:
            entry.requestPayloadKind = .gesture
            entry.isBatchExecutable = true
            entry.parameters = target + FenceParameterBlocks.coordinateXY + [duration] + expectation
            entry.description = "Long-press a coordinate or semantic target for a resolved duration."
        case .swipe:
            entry.requestPayloadKind = .gesture
            entry.isBatchExecutable = true
            entry.humanPositionalSyntax = .leadingDirectionThenTarget(Self.humanDirectionValues)
            entry.parameters = target + [
                param(.direction, .string, enumValues: fenceEnumValues(SwipeDirection.self)),
                param(.start, .object, objectProperties: FenceParameterBlocks.unitPoint),
                param(.end, .object, objectProperties: FenceParameterBlocks.unitPoint),
            ] + FenceParameterBlocks.optionalStart + FenceParameterBlocks.optionalEnd + [duration] + expectation
            entry.description = "Swipe in a direction or between explicit points; semantic targets are made actionable first."
        case .drag:
            entry.requestPayloadKind = .gesture
            entry.isBatchExecutable = true
            entry.parameters = target + FenceParameterBlocks.requiredEnd + FenceParameterBlocks.optionalStart + [duration] + expectation
            entry.description = "Drag from one point to another using explicit coordinates or a semantic target."
        case .pinch:
            entry.requestPayloadKind = .gesture
            entry.isBatchExecutable = true
            entry.parameters = target + [param(.scale, .number, required: true)] + FenceParameterBlocks.center + [
                param(.spread, .number), duration,
            ] + expectation
            entry.description = "Pinch around a resolved center point using scale, angle, and duration."
        case .rotate:
            entry.requestPayloadKind = .gesture
            entry.isBatchExecutable = true
            entry.parameters = target + [param(.angle, .number, required: true)] + FenceParameterBlocks.center + [
                param(.radius, .number), duration,
            ] + expectation
            entry.description = "Rotate around a resolved center point using angle, radius, and duration."
        case .twoFingerTap:
            entry.requestPayloadKind = .gesture
            entry.isBatchExecutable = true
            entry.parameters = target + FenceParameterBlocks.center + [param(.spread, .number)] + expectation
            entry.description = "Tap with two fingers at a coordinate or actionable semantic target."
        case .drawPath:
            entry.requestPayloadKind = .gesture
            entry.isBatchExecutable = true
            entry.parameters = [
                param(
                    .points, .array, required: true,
                    minItems: 2,
                    maxItems: TheFence.DecodeLimits.maxDrawPathPoints,
                    arrayItemType: .object,
                    arrayItemProperties: FenceParameterBlocks.unitPoint
                ),
                duration,
                param(.velocity, .number),
            ] + expectation
            entry.description = "Draw a free-form path through explicit screen-coordinate points."
        case .drawBezier:
            entry.requestPayloadKind = .gesture
            entry.isBatchExecutable = true
            entry.parameters = FenceParameterBlocks.requiredStart + [
                param(
                    .segments, .array, required: true,
                    minItems: 1,
                    maxItems: TheFence.DecodeLimits.maxDrawBezierSegments,
                    arrayItemType: .object,
                    arrayItemProperties: FenceParameterBlocks.bezierSegment
                ),
                param(
                    .samplesPerSegment, .integer,
                    minimum: Double(TheFence.DecodeLimits.minDrawBezierSamplesPerSegment),
                    maximum: Double(TheFence.DecodeLimits.maxDrawBezierSamplesPerSegment)
                ),
                duration,
                param(.velocity, .number),
            ] + expectation
            entry.description = "Draw a Bezier path from a start point through one or more curve segments."
        case .scroll:
            entry.requestPayloadKind = .elementAction
            entry.isBatchExecutable = true
            entry.humanPositionalSyntax = .leadingDirectionThenTarget(Self.humanDirectionValues)
            entry.parameters = scrollContainerTarget + target + [
                param(
                    .direction, .string,
                    enumValues: fenceEnumValues(ScrollDirection.self),
                    defaultValue: .string(ScrollDirection.down.rawValue)
                ),
            ] + expectation
            entry.description = """
                Scroll one page within scroll views in the requested direction. Use scroll_to_visible, \
                element_search, or scroll_to_edge for those canonical operations.
                """
        case .scrollToVisible:
            entry.requestPayloadKind = .elementAction
            entry.isBatchExecutable = true
            entry.parameters = target + expectation
            entry.description = """
                Make a semantic target visible by resolving it, revealing its owning scroll path, \
                refreshing the hierarchy, and returning fresh live geometry.
                """
        case .elementSearch:
            entry.requestPayloadKind = .elementAction
            entry.isBatchExecutable = true
            entry.parameters = target + [
                param(.direction, .string, enumValues: fenceEnumValues(ScrollSearchDirection.self)),
            ] + expectation
            entry.description = "Search scrollable content for a semantic element match without performing an action."
        case .scrollToEdge:
            entry.requestPayloadKind = .elementAction
            entry.isBatchExecutable = true
            entry.humanPositionalSyntax = .leadingEdgeThenTarget(Self.humanScrollEdgeValues)
            entry.parameters = scrollContainerTarget + target + [
                param(
                    .edge, .string,
                    enumValues: fenceEnumValues(ScrollEdge.self),
                    defaultValue: .string(ScrollEdge.top.rawValue)
                ),
            ] + expectation
            entry.description = "Scroll the selected container, or the target's owning scroll ancestor, to a requested edge."
        case .activate:
            entry.requestPayloadKind = .elementAction
            entry.isBatchExecutable = true
            entry.parameters = target + [param(.action, .string), FenceParameterBlocks.incrementCount] + expectation
            entry.description = """
                Activate a UI element (VoiceOver-style double-tap): tap buttons, follow links, toggle \
                controls. Pass 'action' to invoke a named action like "increment", "decrement", or \
                any entry from the element's actions array.
                """
        case .rotor:
            entry.requestPayloadKind = .elementAction
            entry.isBatchExecutable = true
            entry.humanPositionalSyntax = .leadingDirectionThenTarget(Self.humanDirectionValues)
            entry.parameters = target + [
                param(.rotor, .string),
                param(.rotorIndex, .integer, minimum: 0),
                param(
                    .direction, .string,
                    enumValues: fenceEnumValues(RotorDirection.self),
                    defaultValue: .string(RotorDirection.next.rawValue)
                ),
                param(.currentHeistId, .string),
                param(.currentTextStartOffset, .integer, minimum: 0),
                param(.currentTextEndOffset, .integer, minimum: 0),
            ] + expectation
            entry.description = """
                Move through a rotor exposed by an element. Defaults to next. Use rotors listed by \
                get_interface to pick rotor or rotorIndex; pass currentHeistId from the previous \
                object result to continue like a VoiceOver user. For text-range results, also pass \
                the returned start and end offsets.
                """
        case .typeText:
            entry.requestPayloadKind = .elementAction
            entry.isBatchExecutable = true
            entry.humanPositionalSyntax = .joinedText(.text)
            entry.parameters = target + [param(.text, .string, required: true, minLength: 1)] + expectation
            entry.description = """
                Type non-empty text via keyboard injection. Optionally target an \
                element to focus it first and read back the resulting value.
                """
        case .editAction:
            entry.requestPayloadKind = .elementAction
            entry.isBatchExecutable = true
            entry.humanPositionalSyntax = .firstToken(.action)
            entry.parameters = [param(.action, .string, required: true, enumValues: fenceEnumValues(EditAction.self))] + expectation
            entry.description = """
                Perform an edit or keyboard action on the current first responder. \
                Actions: copy, paste, cut, select, selectAll, delete. Use dismiss_keyboard to dismiss the keyboard.
                """
        case .setPasteboard:
            entry.requestPayloadKind = .elementAction
            entry.isBatchExecutable = true
            entry.parameters = [param(.text, .string, required: true)] + expectation
            entry.description = """
                Write text to the general pasteboard from within the app. Content written by the app \
                itself does not trigger the iOS "Allow Paste" dialog when subsequently read.
                """
        case .getPasteboard:
            entry.mcpAnnotations = MCPToolAnnotationSpec(readOnlyHint: true)
            entry.description = """
                Read text from the general pasteboard. iOS may show "Allow Paste" if the content \
                was written by another app.
                """
        case .waitFor:
            entry.requestPayloadKind = .elementAction
            entry.isBatchExecutable = true
            entry.parameters = target + [param(.absent, .boolean), FenceParameterBlocks.expectationTimeout, expect]
            entry.description = """
                Wait for an element matching a predicate to appear, or to disappear with absent=true. \
                Polls on UI settle events. Returns the matched element or diagnostic info on timeout.
                """
        case .dismissKeyboard:
            entry.isBatchExecutable = true
            entry.parameters = expectation
            entry.description = "Dismiss the on-screen keyboard through the current first responder or keyboard action path."
        case .startRecording:
            entry.requestPayloadKind = .session
            entry.parameters = [
                param(.fps, .integer, minimum: 1, maximum: 15),
                param(.scale, .number, minimum: 0.25, maximum: 1.0),
                param(.maxDuration, .number),
                param(.inactivityTimeout, .number),
            ]
            entry.description = "Start an H.264/MP4 screen recording. Recording runs until max duration unless inactivity_timeout is explicitly supplied."
        case .stopRecording:
            entry.requestPayloadKind = .observation
            entry.parameters = [param(.output, .string), param(.inlineData, .boolean), param(.includeInteractionLog, .boolean)]
            entry.description = """
                Stop an in-progress screen recording. Returns artifact path and metadata by default. \
                Set inlineData=true and/or includeInteractionLog=true for a capped expanded JSON response.
                """
        case .runBatch:
            entry.requestPayloadKind = .session
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
            entry.description = """
                Execute multiple commands in one call. Each step is a JSON object with 'command' set \
                to a canonical TheFence.Command name plus that command's parameters. Attach 'expect' per step \
                to verify inline. Returns ordered per-step results. \
                policy=stop_on_error (default) or continue_on_error.
                """
        case .getSessionState:
            entry.requiresConnectionBeforeDispatch = false
            entry.mcpAnnotations = MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
            entry.description = """
                Inspect the current Button Heist session: connection status, device/app identity, \
                recording state, client timeouts, and a lightweight summary of the last action.
                """
        case .connect:
            entry.requestPayloadKind = .session
            entry.requiresConnectionBeforeDispatch = false
            entry.parameters = [param(.target, .string), param(.device, .string), param(.token, .string)]
            entry.description = """
                Establish or switch the active connection to an iOS app with Button Heist enabled. \
                Three patterns: target=NAME from .buttonheist.json, device=HOST:PORT + token, or \
                BUTTONHEIST_DEVICE/BUTTONHEIST_TOKEN env vars. Tears down any existing session first. \
                Returns session state; call get_interface explicitly to observe UI hierarchy.
                """
        case .listTargets:
            entry.requiresConnectionBeforeDispatch = false
            entry.mcpAnnotations = MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
            entry.description = """
                List named connection targets from .buttonheist.json (or ~/.config/buttonheist/config.json), \
                including each target's address and which one is the default.
                """
        case .getSessionLog:
            entry.requiresConnectionBeforeDispatch = false
            entry.mcpAnnotations = MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
            entry.description = "Return the current session log snapshot: commands executed and artifacts produced."
        case .archiveSession:
            entry.requestPayloadKind = .session
            entry.requiresConnectionBeforeDispatch = false
            entry.parameters = [param(.deleteSource, .boolean)]
            entry.description = "Close and compress the current session into a .tar.gz archive; returns the path."
        case .startHeist:
            entry.requestPayloadKind = .session
            entry.requiresConnectionBeforeDispatch = false
            entry.parameters = [param(.app, .string), param(.identifier, .string)]
            entry.description = """
                Start recording a heist. Successful commands become steps in a .heist file; \
                the recorder derives minimum matcher fields for durable element targeting; heistId remains recording evidence only. \
                Attach 'expect' to validate outcomes during playback.
                """
        case .stopHeist:
            entry.requestPayloadKind = .session
            entry.requiresConnectionBeforeDispatch = false
            entry.parameters = [param(.output, .string, required: true)]
            entry.description = """
                Stop recording and save the heist as a self-contained JSON playback script. \
                Returns the file path and step count. At least one step must have been recorded.
                """
        case .playHeist:
            entry.requestPayloadKind = .session
            entry.parameters = [param(.input, .string, required: true)]
            entry.description = """
                Play back a .heist file. Steps execute sequentially; playback stops on the first \
                failed step. On failure, returns full diagnostics: command, target, error, action \
                result, expectation result, and a complete interface snapshot at the failure point.
                """
        }
        return entry
    }
}
