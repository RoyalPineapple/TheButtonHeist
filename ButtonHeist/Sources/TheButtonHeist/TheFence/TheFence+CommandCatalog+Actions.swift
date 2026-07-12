import TheScore
import ThePlans

extension TheFence.Command {
    func makeSpatialActionDescriptor() -> FenceCommandDescriptor {
        switch self {
        case .oneFingerTap:
            return makeDescriptor(
                family: .spatialAction,
                requestDecoder: TheFence.decodeOneFingerTapRequest,
                parameters: FenceParameterBlocks.gesturePointSelection + FenceParameterBlocks.expectation,
                timeout: .singleStepAction(base: .standardAction),
                responseProjection: .heistExecution,
                execution: [.appInteraction, .heistPrimitive, .payloadCheckedHeistPrimitive],
                projection: .cliOnly(
                    "Explicit mechanical/spatial tap. Element targets dispatch at their activation point "
                        + "unless unitPoint supplies an element-frame override; point supplies a raw screen coordinate. "
                        + "ordinary accessible controls should use the semantic command path."
                )
            )
        case .longPress:
            return makeDescriptor(
                family: .spatialAction,
                requestDecoder: TheFence.decodeLongPressRequest,
                parameters: FenceParameterBlocks.gesturePointSelection
                    + [FenceParameterBlocks.gestureDuration] + FenceParameterBlocks.expectation,
                timeout: .singleStepAction(base: .standardAction),
                responseProjection: .heistExecution,
                execution: [.appInteraction, .heistPrimitive, .payloadCheckedHeistPrimitive],
                projection: .cliOnly(
                    "Explicit mechanical/spatial long press. Element targets dispatch at their activation point "
                        + "unless unitPoint supplies an element-frame override; point supplies a raw screen coordinate."
                )
            )
        case .swipe:
            return makeDescriptor(
                family: .spatialAction,
                requestDecoder: TheFence.decodeSwipeRequest,
                parameters: FenceParameterBlocks.swipeIntents
                    + [FenceParameterBlocks.gestureDuration] + FenceParameterBlocks.expectation,
                timeout: .singleStepAction(base: .standardAction),
                responseProjection: .heistExecution,
                execution: [.appInteraction, .heistPrimitive, .payloadCheckedHeistPrimitive],
                projection: .cliOnly(
                    "Explicit mechanical/spatial swipe using exactly one typed intent: "
                        + "elementDirection, elementUnitPoints, pointToPoint, or pointDirection."
                )
            )
        case .drag:
            return makeDescriptor(
                family: .spatialAction,
                requestDecoder: TheFence.decodeDragRequest,
                parameters: FenceParameterBlocks.dragIntents
                    + [FenceParameterBlocks.gestureDuration] + FenceParameterBlocks.expectation,
                timeout: .singleStepAction(base: .standardAction),
                responseProjection: .heistExecution,
                execution: [.appInteraction, .heistPrimitive, .payloadCheckedHeistPrimitive],
                projection: .cliOnly(
                    "Explicit mechanical/spatial drag using exactly one typed intent: "
                        + "elementToPoint (activation point or unit start override) or pointToPoint."
                )
            )
        case .ping, .listDevices, .getInterface, .getScreen, .getPasteboard, .getAnnouncements,
             .getSessionState, .connect, .listTargets, .wait, .scroll, .scrollToVisible, .scrollToEdge,
             .activate, .rotor, .typeText, .editAction, .setPasteboard, .dismissKeyboard,
             .perform, .runHeist, .listHeists, .describeHeist:
            preconditionFailure("\(rawValue) is not a spatial action command")
        }
    }

    func makeViewportDebugDescriptor() -> FenceCommandDescriptor {
        switch self {
        case .scroll:
            return makeDescriptor(
                family: .viewportDebug,
                requestDecoder: TheFence.decodeScrollRequest,
                parameters: FenceParameterBlocks.elementTarget + [
                    param(.containerName, .string),
                    FenceParameters.scrollDirection.spec,
                ] + FenceParameterBlocks.expectation,
                timeout: .fixed(.standardAction),
                responseProjection: .action,
                execution: [.appInteraction],
                projection: .cliOnly(
                    "Explicit viewport/debug operation: scroll one page in the visible viewport, "
                        + "within a semantic target's owning scroll ancestor, or for direct debug requests, "
                        + "within a current containerName."
                )
            )
        case .scrollToVisible:
            return makeDescriptor(
                family: .viewportDebug,
                requestDecoder: TheFence.decodeScrollToVisibleRequest,
                parameters: FenceParameterBlocks.elementTarget + FenceParameterBlocks.expectation,
                timeout: .fixed(.standardAction),
                responseProjection: .action,
                execution: [.appInteraction],
                projection: .cliOnly(
                    "Explicit viewport/debug operation: move the viewport until a "
                        + "semantic target is visible and report its fresh geometry."
                )
            )
        case .scrollToEdge:
            return makeDescriptor(
                family: .viewportDebug,
                requestDecoder: TheFence.decodeScrollToEdgeRequest,
                parameters: FenceParameterBlocks.elementTarget + [
                    param(.containerName, .string),
                    FenceParameters.scrollEdge.spec,
                ] + FenceParameterBlocks.expectation,
                timeout: .fixed(.standardAction),
                responseProjection: .action,
                execution: [.appInteraction],
                projection: .cliOnly(
                    "Explicit viewport/debug operation: scroll the visible viewport, "
                        + "a semantic target's owning scroll ancestor, or for direct debug requests, "
                        + "a current containerName, to a requested edge."
                )
            )
        case .ping, .listDevices, .getInterface, .getScreen, .getPasteboard, .getAnnouncements,
             .getSessionState, .connect, .listTargets, .wait, .oneFingerTap, .longPress, .swipe, .drag,
             .activate, .rotor, .typeText, .editAction, .setPasteboard, .dismissKeyboard,
             .perform, .runHeist, .listHeists, .describeHeist:
            preconditionFailure("\(rawValue) is not a viewport debug command")
        }
    }

    func makeSemanticActionDescriptor() -> FenceCommandDescriptor {
        switch self {
        case .activate:
            return makeDescriptor(
                family: .semanticAction,
                requestDecoder: TheFence.decodeActivateRequest,
                parameters: FenceParameterBlocks.elementTarget
                    + [param(.action, .string)] + FenceParameterBlocks.expectation,
                timeout: .singleStepAction(base: .standardAction),
                responseProjection: .heistExecution,
                execution: [.appInteraction, .heistPrimitive],
                projection: .cliOnly(
                    "Perform primary accessibility activation on a semantic UI element, "
                        + "or one of its named accessibility actions."
                )
            )
        case .rotor:
            return makeDescriptor(
                family: .semanticAction,
                requestDecoder: TheFence.decodeRotorRequest,
                parameters: FenceParameterBlocks.elementTarget + [
                    FenceParameters.rotorName.spec,
                    FenceParameters.rotorIndex.spec,
                    FenceParameters.rotorDirection.spec,
                ] + FenceParameterBlocks.expectation,
                timeout: .singleStepAction(base: .standardAction),
                responseProjection: .heistExecution,
                execution: [.appInteraction, .heistPrimitive],
                projection: .cliOnly(
                    "Move through an element rotor by direction. The server holds the rotor cursor "
                        + "while in rotor mode (entering at the first item); any other interaction exits rotor mode "
                        + "and drops the cursor."
                )
            )
        case .typeText:
            return makeDescriptor(
                family: .semanticAction,
                requestDecoder: TheFence.decodeTypeTextRequest,
                parameters: FenceParameterBlocks.elementTarget + [
                    FenceParameters.text.spec,
                    FenceParameters.replacingExisting.spec,
                ] + FenceParameterBlocks.expectation,
                timeout: .singleStepAction(base: .longAction),
                responseProjection: .heistExecution,
                execution: [.appInteraction, .heistPrimitive],
                projection: .cliOnly(
                    "Type text. With replacingExisting=true, The Button Heist clears the focused field before typing."
                )
            )
        case .editAction:
            return makeDescriptor(
                family: .semanticAction,
                requestDecoder: TheFence.decodeEditActionRequest,
                parameters: [FenceParameters.editAction.spec] + FenceParameterBlocks.expectation,
                timeout: .singleStepAction(base: .standardAction),
                responseProjection: .heistExecution,
                execution: [.appInteraction, .heistPrimitive],
                projection: .cliOnly("Perform an edit action on the current first responder.")
            )
        case .setPasteboard:
            return makeDescriptor(
                family: .semanticAction,
                requestDecoder: TheFence.decodeSetPasteboardRequest,
                parameters: [FenceParameters.pasteboardText.spec] + FenceParameterBlocks.expectation,
                timeout: .singleStepAction(base: .standardAction),
                responseProjection: .heistExecution,
                execution: [.appInteraction, .heistPrimitive],
                projection: .cliOnly("Write text to the general pasteboard from within the app.")
            )
        case .dismissKeyboard:
            return makeDescriptor(
                family: .semanticAction,
                requestDecoder: TheFence.decodeDismissKeyboardRequest,
                parameters: FenceParameterBlocks.expectation,
                timeout: .singleStepAction(base: .standardAction),
                responseProjection: .heistExecution,
                execution: [.appInteraction, .heistPrimitive],
                projection: .cliOnly("Dismiss the on-screen keyboard through the current first responder or keyboard action path.")
            )
        case .ping, .listDevices, .getInterface, .getScreen, .getPasteboard, .getAnnouncements,
             .getSessionState, .connect, .listTargets, .wait, .oneFingerTap, .longPress, .swipe, .drag,
             .scroll, .scrollToVisible, .scrollToEdge, .perform, .runHeist, .listHeists, .describeHeist:
            preconditionFailure("\(rawValue) is not a semantic action command")
        }
    }
}
