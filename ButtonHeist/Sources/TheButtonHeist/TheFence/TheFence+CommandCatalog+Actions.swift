import TheScore
import ThePlans

enum SpatialActionCommand: String, CaseIterable, FenceCommand {
    case oneFingerTap = "one_finger_tap"
    case longPress = "long_press"
    case swipe
    case drag

    var descriptor: FenceCommandDescriptor {
        switch self {
        case .oneFingerTap:
            return TheFence.Command.commandDescriptor(
                command, family: .spatialAction,
                requestDecoder: TheFence.decodeOneFingerTapRequest,
                parameters: FenceParameterBlocks.gesturePointSelection + FenceParameterBlocks.expectation,
                execution: [.appInteraction, .heistPrimitive, .payloadCheckedHeistPrimitive],
                projection: .cliOnly(
                    "Explicit mechanical/spatial tap. Element targets dispatch at their activation point "
                        + "unless unitPoint supplies an element-frame override; point supplies a raw screen coordinate. "
                        + "ordinary accessible controls should use the semantic command path."
                )
            )
        case .longPress:
            return TheFence.Command.commandDescriptor(
                command, family: .spatialAction,
                requestDecoder: TheFence.decodeLongPressRequest,
                parameters: FenceParameterBlocks.gesturePointSelection
                    + [FenceParameterBlocks.gestureDuration] + FenceParameterBlocks.expectation,
                execution: [.appInteraction, .heistPrimitive, .payloadCheckedHeistPrimitive],
                projection: .cliOnly(
                    "Explicit mechanical/spatial long press. Element targets dispatch at their activation point "
                        + "unless unitPoint supplies an element-frame override; point supplies a raw screen coordinate."
                )
            )
        case .swipe:
            return TheFence.Command.commandDescriptor(
                command, family: .spatialAction,
                requestDecoder: TheFence.decodeSwipeRequest,
                parameters: FenceParameterBlocks.swipeIntents
                    + [FenceParameterBlocks.gestureDuration] + FenceParameterBlocks.expectation,
                execution: [.appInteraction, .heistPrimitive, .payloadCheckedHeistPrimitive],
                projection: .cliOnly(
                    "Explicit mechanical/spatial swipe using exactly one typed intent: "
                        + "elementDirection, elementUnitPoints, pointToPoint, or pointDirection."
                )
            )
        case .drag:
            return TheFence.Command.commandDescriptor(
                command, family: .spatialAction,
                requestDecoder: TheFence.decodeDragRequest,
                parameters: FenceParameterBlocks.dragIntents
                    + [FenceParameterBlocks.gestureDuration] + FenceParameterBlocks.expectation,
                execution: [.appInteraction, .heistPrimitive, .payloadCheckedHeistPrimitive],
                projection: .cliOnly(
                    "Explicit mechanical/spatial drag using exactly one typed intent: "
                        + "elementToPoint (activation point or unit start override) or pointToPoint."
                )
            )
        }
    }
}

enum ViewportDebugCommand: String, CaseIterable, FenceCommand {
    case scroll
    case scrollToVisible = "scroll_to_visible"
    case scrollToEdge = "scroll_to_edge"

    var descriptor: FenceCommandDescriptor {
        switch self {
        case .scroll:
            return TheFence.Command.commandDescriptor(
                command, family: .viewportDebug,
                requestDecoder: TheFence.decodeScrollRequest,
                parameters: FenceParameterBlocks.elementTarget + [
                    param(.container, .string),
                    param(.direction, .string, enumValues: fenceEnumValues(ScrollDirection.self), defaultValue: .string(ScrollDirection.down.rawValue)),
                ] + FenceParameterBlocks.expectation,
                execution: [.appInteraction],
                projection: .cliOnly(
                    "Explicit viewport/debug operation: scroll one page in the visible viewport, "
                        + "within a semantic target's owning scroll ancestor, or for direct debug requests, "
                        + "within a current containerName."
                )
            )
        case .scrollToVisible:
            return TheFence.Command.commandDescriptor(
                command, family: .viewportDebug,
                requestDecoder: TheFence.decodeScrollToVisibleRequest,
                parameters: FenceParameterBlocks.elementTarget + FenceParameterBlocks.expectation,
                execution: [.appInteraction],
                projection: .cliOnly(
                    "Explicit viewport/debug operation: move the viewport until a "
                        + "semantic target is visible and report its fresh geometry."
                )
            )
        case .scrollToEdge:
            return TheFence.Command.commandDescriptor(
                command, family: .viewportDebug,
                requestDecoder: TheFence.decodeScrollToEdgeRequest,
                parameters: FenceParameterBlocks.elementTarget + [
                    param(.container, .string),
                    param(.edge, .string, enumValues: fenceEnumValues(ScrollEdge.self), defaultValue: .string(ScrollEdge.top.rawValue)),
                ] + FenceParameterBlocks.expectation,
                execution: [.appInteraction],
                projection: .cliOnly(
                    "Explicit viewport/debug operation: scroll the visible viewport, "
                        + "a semantic target's owning scroll ancestor, or for direct debug requests, "
                        + "a current containerName, to a requested edge."
                )
            )
        }
    }
}

enum SemanticActionCommand: String, CaseIterable, FenceCommand {
    case activate
    case rotor
    case typeText = "type_text"
    case editAction = "edit_action"
    case setPasteboard = "set_pasteboard"
    case dismissKeyboard = "dismiss_keyboard"

    var descriptor: FenceCommandDescriptor {
        switch self {
        case .activate:
            return TheFence.Command.commandDescriptor(
                command, family: .semanticAction,
                requestDecoder: TheFence.decodeActivateRequest,
                parameters: FenceParameterBlocks.elementTarget
                    + [param(.action, .string)] + FenceParameterBlocks.expectation,
                execution: [.appInteraction, .heistPrimitive],
                projection: .cliOnly(
                    "Perform primary accessibility activation on a semantic UI element, "
                        + "or one of its named accessibility actions."
                )
            )
        case .rotor:
            return TheFence.Command.commandDescriptor(
                command, family: .semanticAction,
                requestDecoder: TheFence.decodeRotorRequest,
                parameters: FenceParameterBlocks.elementTarget + [
                    param(.rotor, .string),
                    param(.rotorIndex, .integer, minimum: 0),
                    param(
                        .direction, .string,
                        enumValues: fenceEnumValues(RotorDirection.self),
                        defaultValue: .string(RotorDirection.next.rawValue)
                    ),
                ] + FenceParameterBlocks.expectation,
                execution: [.appInteraction, .heistPrimitive],
                projection: .cliOnly(
                    "Move through an element rotor by direction. The server holds the rotor cursor "
                        + "while in rotor mode (entering at the first item); any other interaction exits rotor mode "
                        + "and drops the cursor."
                )
            )
        case .typeText:
            return TheFence.Command.commandDescriptor(
                command, family: .semanticAction,
                requestDecoder: TheFence.decodeTypeTextRequest,
                parameters: FenceParameterBlocks.elementTarget + [
                    param(.text, .string, required: true),
                    param(.replacingExisting, .boolean, defaultValue: .bool(false)),
                ] + FenceParameterBlocks.expectation,
                execution: [.appInteraction, .heistPrimitive],
                projection: .cliOnly(
                    "Type text. With replacingExisting=true, The Button Heist clears the focused field before typing."
                )
            )
        case .editAction:
            return TheFence.Command.commandDescriptor(
                command, family: .semanticAction,
                requestDecoder: TheFence.decodeEditActionRequest,
                parameters: [param(.action, .string, required: true, enumValues: fenceEnumValues(EditAction.self))] + FenceParameterBlocks.expectation,
                execution: [.appInteraction, .heistPrimitive],
                projection: .cliOnly("Perform an edit action on the current first responder.")
            )
        case .setPasteboard:
            return TheFence.Command.commandDescriptor(
                command, family: .semanticAction,
                requestDecoder: TheFence.decodeSetPasteboardRequest,
                parameters: [param(.text, .string, required: true)] + FenceParameterBlocks.expectation,
                execution: [.appInteraction, .heistPrimitive],
                projection: .cliOnly("Write text to the general pasteboard from within the app.")
            )
        case .dismissKeyboard:
            return TheFence.Command.commandDescriptor(
                command, family: .semanticAction,
                requestDecoder: TheFence.decodeDismissKeyboardRequest,
                parameters: FenceParameterBlocks.expectation,
                execution: [.appInteraction, .heistPrimitive],
                projection: .cliOnly("Dismiss the on-screen keyboard through the current first responder or keyboard action path.")
            )
        }
    }
}
