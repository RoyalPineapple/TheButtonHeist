import TheScore

extension TheFence.Command {
    static var actionCommandDescriptors: [FenceCommandDescriptor] {
        [
            commandDescriptor(
                .oneFingerTap, requestDecoder: TheFence.decodeOneFingerTapRequest,
                isHeistExecutable: true,
                parameters: FenceParameterBlocks.gesturePointSelection + FenceParameterBlocks.expectation,
                description: "Explicit mechanical/spatial tap. An element target supplies live geometry; "
                    + "ordinary accessible controls should use the semantic command path."
            ),
            commandDescriptor(
                .longPress, requestDecoder: TheFence.decodeLongPressRequest,
                isHeistExecutable: true,
                parameters: FenceParameterBlocks.gesturePointSelection
                    + [FenceParameterBlocks.gestureDuration] + FenceParameterBlocks.expectation,
                description: "Long-press an explicit point or semantic element for a resolved duration."
            ),
            commandDescriptor(
                .swipe, requestDecoder: TheFence.decodeSwipeRequest,
                isHeistExecutable: true,
                parameters: FenceParameterBlocks.swipeIntents
                    + [FenceParameterBlocks.gestureDuration] + FenceParameterBlocks.expectation,
                description: "Swipe using exactly one typed intent: elementDirection, elementUnitPoints, pointToPoint, or pointDirection."
            ),
            commandDescriptor(
                .drag, requestDecoder: TheFence.decodeDragRequest,
                isHeistExecutable: true,
                parameters: FenceParameterBlocks.dragIntents
                    + [FenceParameterBlocks.gestureDuration] + FenceParameterBlocks.expectation,
                description: "Drag using exactly one typed intent: elementToPoint or pointToPoint."
            ),
            commandDescriptor(
                .scroll, requestDecoder: TheFence.decodeScrollRequest,
                isHeistExecutable: true,
                parameters: FenceParameterBlocks.elementTarget + [
                    param(.direction, .string, enumValues: fenceEnumValues(ScrollDirection.self), defaultValue: .string(ScrollDirection.down.rawValue)),
                ] + FenceParameterBlocks.expectation,
                description: "Explicit viewport operation: scroll one page in the visible viewport, "
                    + "or within a semantic target's owning scroll ancestor."
            ),
            commandDescriptor(
                .scrollToVisible, requestDecoder: TheFence.decodeScrollToVisibleRequest,
                isHeistExecutable: true,
                parameters: FenceParameterBlocks.elementTarget + FenceParameterBlocks.expectation,
                description: "Explicit viewport/debug operation: make a semantic target actionable "
                    + "and report its fresh geometry."
            ),
            commandDescriptor(
                .scrollToEdge, requestDecoder: TheFence.decodeScrollToEdgeRequest,
                isHeistExecutable: true,
                parameters: FenceParameterBlocks.elementTarget + [
                    param(.edge, .string, enumValues: fenceEnumValues(ScrollEdge.self), defaultValue: .string(ScrollEdge.top.rawValue)),
                ] + FenceParameterBlocks.expectation,
                description: "Explicit viewport operation: scroll the visible viewport, "
                    + "or a semantic target's owning scroll ancestor, to a requested edge."
            ),
            commandDescriptor(
                .activate, requestDecoder: TheFence.decodeActivateRequest,
                isHeistExecutable: true,
                parameters: FenceParameterBlocks.elementTarget
                    + [param(.action, .string), FenceParameterBlocks.incrementCount] + FenceParameterBlocks.expectation,
                description: "Perform primary accessibility activation on a semantic UI element, "
                    + "or one of its named accessibility actions."
            ),
            commandDescriptor(
                .rotor, requestDecoder: TheFence.decodeRotorRequest,
                isHeistExecutable: true,
                parameters: FenceParameterBlocks.elementTarget + [
                    param(.rotor, .string),
                    param(.rotorIndex, .integer, minimum: 0),
                    param(
                        .direction, .string,
                        enumValues: fenceEnumValues(RotorDirection.self),
                        defaultValue: .string(RotorDirection.next.rawValue)
                    ),
                ] + FenceParameterBlocks.expectation,
                description: "Move through an element rotor by direction. The server holds the rotor cursor "
                    + "while in rotor mode (entering at the first item); any other interaction exits rotor mode "
                    + "and drops the cursor."
            ),
            commandDescriptor(
                .typeText, requestDecoder: TheFence.decodeTypeTextRequest,
                isHeistExecutable: true,
                parameters: FenceParameterBlocks.elementTarget + [param(.text, .string, required: true, minLength: 1)] + FenceParameterBlocks.expectation,
                description: "Type non-empty text, optionally after making a semantic target actionable."
            ),
            commandDescriptor(
                .editAction, requestDecoder: TheFence.decodeEditActionRequest,
                isHeistExecutable: true,
                parameters: [param(.action, .string, required: true, enumValues: fenceEnumValues(EditAction.self))] + FenceParameterBlocks.expectation,
                description: "Perform an edit action on the current first responder."
            ),
            commandDescriptor(
                .setPasteboard, requestDecoder: TheFence.decodeSetPasteboardRequest,
                isHeistExecutable: true,
                parameters: [param(.text, .string, required: true)] + FenceParameterBlocks.expectation,
                description: "Write text to the general pasteboard from within the app."
            ),
            commandDescriptor(
                .getPasteboard, requestDecoder: TheFence.decodeGetPasteboardRequest,
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true),
                description: "Read text from the general pasteboard."
            ),
            commandDescriptor(
                .dismissKeyboard, requestDecoder: TheFence.decodeDismissKeyboardRequest,
                isHeistExecutable: true,
                parameters: FenceParameterBlocks.expectation,
                description: "Dismiss the on-screen keyboard through the current first responder or keyboard action path."
            ),
        ]
    }
}
