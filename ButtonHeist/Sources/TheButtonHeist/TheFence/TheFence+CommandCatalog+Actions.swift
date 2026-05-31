import TheScore

extension TheFence.Command {
    static var actionCommandDescriptors: [FenceCommandDescriptor] {
        [
            commandDescriptor(
                .oneFingerTap, requestDecoder: TheFence.decodeOneFingerTapRequest,
                isBatchExecutable: true,
                parameters: FenceParameterBlocks.elementTarget + FenceParameterBlocks.coordinateXY + FenceParameterBlocks.expectation,
                description: "Tap a coordinate or semantic target after actionability resolution."
            ),
            commandDescriptor(
                .longPress, requestDecoder: TheFence.decodeLongPressRequest,
                isBatchExecutable: true,
                parameters: FenceParameterBlocks.elementTarget + FenceParameterBlocks.coordinateXY
                    + [FenceParameterBlocks.gestureDuration] + FenceParameterBlocks.expectation,
                description: "Long-press a coordinate or semantic target for a resolved duration."
            ),
            commandDescriptor(
                .swipe, requestDecoder: TheFence.decodeSwipeRequest,
                isBatchExecutable: true,
                parameters: FenceParameterBlocks.elementTarget + [
                    param(.direction, .string, enumValues: fenceEnumValues(SwipeDirection.self)),
                    param(.start, .object, objectProperties: FenceParameterBlocks.unitPoint),
                    param(.end, .object, objectProperties: FenceParameterBlocks.unitPoint),
                ] + FenceParameterBlocks.optionalStart + FenceParameterBlocks.optionalEnd
                    + [FenceParameterBlocks.gestureDuration] + FenceParameterBlocks.expectation,
                description: "Swipe in a direction or between explicit points; semantic targets are made actionable first."
            ),
            commandDescriptor(
                .drag, requestDecoder: TheFence.decodeDragRequest,
                isBatchExecutable: true,
                parameters: FenceParameterBlocks.elementTarget + FenceParameterBlocks.requiredEnd
                    + FenceParameterBlocks.optionalStart + [FenceParameterBlocks.gestureDuration] + FenceParameterBlocks.expectation,
                description: "Drag from one point to another using explicit coordinates or a semantic target."
            ),
            commandDescriptor(
                .scroll, requestDecoder: TheFence.decodeScrollRequest,
                isBatchExecutable: true,
                parameters: FenceParameterBlocks.scrollContainerTarget + FenceParameterBlocks.elementTarget + [
                    param(.direction, .string, enumValues: fenceEnumValues(ScrollDirection.self), defaultValue: .string(ScrollDirection.down.rawValue)),
                ] + FenceParameterBlocks.expectation,
                description: "Scroll one page in a selected container or semantic target's owning scroll ancestor."
            ),
            commandDescriptor(
                .scrollToVisible, requestDecoder: TheFence.decodeScrollToVisibleRequest,
                isBatchExecutable: true,
                parameters: FenceParameterBlocks.elementTarget + FenceParameterBlocks.expectation,
                description: "Make a semantic target actionable and report its fresh geometry."
            ),
            commandDescriptor(
                .elementSearch, requestDecoder: TheFence.decodeElementSearchRequest,
                isBatchExecutable: true,
                parameters: FenceParameterBlocks.elementTarget
                    + [param(.direction, .string, enumValues: fenceEnumValues(ScrollDirection.self))] + FenceParameterBlocks.expectation,
                description: "Search scrollable content for a semantic element match without performing an action."
            ),
            commandDescriptor(
                .scrollToEdge, requestDecoder: TheFence.decodeScrollToEdgeRequest,
                isBatchExecutable: true,
                parameters: FenceParameterBlocks.scrollContainerTarget + FenceParameterBlocks.elementTarget + [
                    param(.edge, .string, enumValues: fenceEnumValues(ScrollEdge.self), defaultValue: .string(ScrollEdge.top.rawValue)),
                ] + FenceParameterBlocks.expectation,
                description: "Scroll the selected container, or the target's owning scroll ancestor, to a requested edge."
            ),
            commandDescriptor(
                .activate, requestDecoder: TheFence.decodeActivateRequest,
                isBatchExecutable: true,
                parameters: FenceParameterBlocks.elementTarget
                    + [param(.action, .string), FenceParameterBlocks.incrementCount] + FenceParameterBlocks.expectation,
                description: "Activate a semantic UI element or one of its named accessibility actions."
            ),
            commandDescriptor(
                .rotor, requestDecoder: TheFence.decodeRotorRequest,
                isBatchExecutable: true,
                parameters: FenceParameterBlocks.elementTarget + [
                    param(.rotor, .string),
                    param(.rotorIndex, .integer, minimum: 0),
                    param(.direction, .string, enumValues: fenceEnumValues(RotorDirection.self), defaultValue: .string(RotorDirection.next.rawValue)),
                    param(
                        .continuation, .object,
                        objectProperties: [
                            param(.heistId, .string, required: true),
                            param(.textRange, .object, objectProperties: [
                                param(.startOffset, .integer, required: true, minimum: 0),
                                param(.endOffset, .integer, required: true, minimum: 0),
                            ]),
                        ]
                    ),
                ] + FenceParameterBlocks.expectation,
                description: "Move through an element rotor using direction and continuation metadata."
            ),
            commandDescriptor(
                .typeText, requestDecoder: TheFence.decodeTypeTextRequest,
                isBatchExecutable: true,
                parameters: FenceParameterBlocks.elementTarget + [param(.text, .string, required: true, minLength: 1)] + FenceParameterBlocks.expectation,
                description: "Type non-empty text, optionally after making a semantic target actionable."
            ),
            commandDescriptor(
                .editAction, requestDecoder: TheFence.decodeEditActionRequest,
                isBatchExecutable: true,
                parameters: [param(.action, .string, required: true, enumValues: fenceEnumValues(EditAction.self))] + FenceParameterBlocks.expectation,
                description: "Perform an edit action on the current first responder."
            ),
            commandDescriptor(
                .setPasteboard, requestDecoder: TheFence.decodeSetPasteboardRequest,
                isBatchExecutable: true,
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
                isBatchExecutable: true,
                parameters: FenceParameterBlocks.expectation,
                description: "Dismiss the on-screen keyboard through the current first responder or keyboard action path."
            ),
        ]
    }
}
