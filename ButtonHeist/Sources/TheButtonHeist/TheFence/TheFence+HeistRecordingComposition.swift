import TheScore

struct HeistRecordingComposition {
    let request: TheFence.ParsedRequest
    let dispatchedResponse: FenceResponse
    let validatedResponse: FenceResponse

    func steps() throws -> [HeistStep] {
        guard request.command.descriptor.isHeistExecutable else { return [] }
        guard let dispatchedReceipt = dispatchedResponse.heistRecordingReceipt,
              dispatchedReceipt.actionResult.success else {
            return []
        }
        guard let finalReceipt = validatedResponse.heistRecordingReceipt,
              finalReceipt.shouldRecord else {
            return []
        }
        if request.expectationPayload.expectation != nil,
           finalReceipt.expectation?.met != true {
            return []
        }
        guard let messages = request.executableMessages,
              let message = messages.first,
              messages.count == 1
        else {
            throw TheFence.HeistStepPlanBuildError(
                message: """
                heist action command "\(request.command.rawValue)" expands to \
                \(request.executableMessages?.count ?? 0) actions; express repeats as separate ordered steps
                """
            )
        }

        if case .wait(let target) = message {
            return [.wait(WaitStep(predicate: target.predicate, timeout: target.resolvedTimeout))]
        }

        if case .scrollToVisible = message {
            return []
        }

        let normalizedCommand = Self.normalizedCommand(
            message,
            actionResult: dispatchedReceipt.actionResult
        )
        let expectation = Self.recordedExpectation(
            request: request,
            actionResult: dispatchedReceipt.actionResult,
            finalReceipt: finalReceipt
        )
        return [.action(try ActionStep(
            command: normalizedCommand,
            expectation: expectation
        ))]
    }

    private static func recordedExpectation(
        request: TheFence.ParsedRequest,
        actionResult: ActionResult,
        finalReceipt: FenceResponse.HeistRecordingReceipt
    ) -> WaitStep? {
        if let explicit = request.expectationPayload.expectation,
           finalReceipt.expectation?.met == true {
            return WaitStep(
                predicate: explicit,
                timeout: request.expectationPayload.postActionValidationTimeout ?? 10
            )
        }
        return inferredExpectation(actionResult: actionResult)
    }

    private static func normalizedCommand(
        _ message: ClientMessage,
        actionResult: ActionResult
    ) -> ClientMessage {
        switch message {
        case .activate(let target):
            return .activate(normalizedTarget(target, actionResult: actionResult))
        case .increment(let target):
            return .increment(normalizedTarget(target, actionResult: actionResult))
        case .decrement(let target):
            return .decrement(normalizedTarget(target, actionResult: actionResult))
        case .performCustomAction(let target):
            return .performCustomAction(CustomActionTarget(
                elementTarget: normalizedTarget(target.elementTarget, actionResult: actionResult),
                actionName: target.actionName
            ))
        case .rotor(let target):
            return .rotor(RotorTarget(
                elementTarget: normalizedTarget(target.elementTarget, actionResult: actionResult),
                selection: target.selection,
                direction: target.direction
            ))
        case .oneFingerTap(let target):
            return .oneFingerTap(TapTarget(
                selection: normalizedGesturePoint(target.selection, actionResult: actionResult)
            ))
        case .longPress(let target):
            return .longPress(LongPressTarget(
                selection: normalizedGesturePoint(target.selection, actionResult: actionResult),
                duration: target.duration
            ))
        case .swipe(let target):
            return .swipe(normalizedSwipe(target, actionResult: actionResult))
        case .drag(let target):
            return .drag(normalizedDrag(target, actionResult: actionResult))
        case .typeText(let target):
            return .typeText(TypeTextTarget(
                text: target.text,
                elementTarget: target.elementTarget.map {
                    normalizedTarget($0, actionResult: actionResult)
                }
            ))
        default:
            return message
        }
    }

    private static func normalizedGesturePoint(
        _ selection: GesturePointSelection,
        actionResult: ActionResult
    ) -> GesturePointSelection {
        switch selection {
        case .element(let target):
            return .element(normalizedTarget(target, actionResult: actionResult))
        case .coordinate:
            return selection
        }
    }

    private static func normalizedSwipe(
        _ target: SwipeTarget,
        actionResult: ActionResult
    ) -> SwipeTarget {
        let selection: SwipeGestureSelection
        switch target.selection {
        case .unitElement(let element, let start, let end):
            selection = .unitElement(
                normalizedTarget(element, actionResult: actionResult),
                start: start,
                end: end
            )
        case .elementDirection(let element, let direction):
            selection = .elementDirection(
                normalizedTarget(element, actionResult: actionResult),
                direction
            )
        case .point:
            selection = target.selection
        }
        return SwipeTarget(selection: selection, duration: target.duration)
    }

    private static func normalizedDrag(
        _ target: DragTarget,
        actionResult: ActionResult
    ) -> DragTarget {
        switch target.selection {
        case .elementToPoint(let element, let end):
            return DragTarget(
                selection: .elementToPoint(normalizedTarget(element, actionResult: actionResult), end: end),
                duration: target.duration
            )
        case .pointToPoint:
            return target
        }
    }

    private static func normalizedTarget(
        _ target: ElementTarget,
        actionResult: ActionResult
    ) -> ElementTarget {
        minimumTarget(actionResult: actionResult) ?? target
    }

    private static func minimumTarget(actionResult: ActionResult) -> ElementTarget? {
        guard actionResult.settled != false,
              let evidence = actionResult.subjectEvidence,
              let trace = actionResult.accessibilityTrace,
              let before = trace.captures.first
        else { return nil }

        let elements = before.interface.projectedElements
        guard let index = contextIndex(for: evidence, in: elements) else { return nil }
        let context = PredicateSelectionContext(
            elements: elements.enumerated().map { offset, element in
                PredicateSelectionContext.Element(id: "\(offset)", element: element)
            },
            screenId: before.context.screenId,
            semanticHash: before.hash,
            scope: .visible
        )
        return minimumUniquePredicate(for: "\(index)", in: context)?.target
    }

    private static func contextIndex(
        for evidence: ActionSubjectEvidence,
        in elements: [HeistElement]
    ) -> Int? {
        if let targetIndex = index(of: evidence.target, in: elements) {
            return targetIndex
        }
        let equalIndices = elements.indices.filter { elements[$0] == evidence.element }
        return equalIndices.count == 1 ? equalIndices[0] : nil
    }

    private static func index(of target: ElementTarget, in elements: [HeistElement]) -> Int? {
        switch target {
        case .predicate(let predicate, let ordinal):
            let matches = elements.indices.filter { predicate.matches(elements[$0]) }
            if let ordinal {
                guard matches.indices.contains(ordinal) else { return nil }
                return matches[ordinal]
            }
            return matches.count == 1 ? matches[0] : nil
        }
    }

    private static func inferredExpectation(actionResult: ActionResult) -> WaitStep? {
        guard actionResult.settled != false,
              let target = minimumTarget(actionResult: actionResult),
              let trace = actionResult.accessibilityTrace,
              let before = trace.captures.first,
              let after = trace.captures.last,
              before.hash != after.hash
        else { return nil }

        if case .screenChanged? = trace.endpointDeltaProjection {
            return WaitStep(predicate: .changed(.screen()), timeout: 10)
        }

        let beforeElements = before.interface.projectedElements
        let afterElements = after.interface.projectedElements
        guard let beforeIndex = index(of: target, in: beforeElements) else { return nil }
        let beforeElement = beforeElements[beforeIndex]
        guard let afterIndex = index(of: target, in: afterElements) else {
            return WaitStep(predicate: .state(.absentTarget(target)), timeout: 10)
        }
        return currentStateExpectation(
            target: target,
            before: beforeElement,
            after: afterElements[afterIndex]
        ).map { WaitStep(predicate: $0, timeout: 10) }
    }

    private static func currentStateExpectation(
        target: ElementTarget,
        before: HeistElement,
        after: HeistElement
    ) -> AccessibilityPredicate? {
        guard case .predicate(var predicate, nil) = target else { return nil }
        if before.value != after.value, let value = after.value, !value.isEmpty {
            predicate.value = value
            return .state(.present(predicate))
        }

        if before.traits.contains(.selected) != after.traits.contains(.selected) {
            return .state(.present(traitStatePredicate(
                base: predicate,
                trait: .selected,
                isPresent: after.traits.contains(.selected)
            )))
        }

        if before.traits.contains(.notEnabled) != after.traits.contains(.notEnabled) {
            return .state(.present(traitStatePredicate(
                base: predicate,
                trait: .notEnabled,
                isPresent: after.traits.contains(.notEnabled)
            )))
        }

        return nil
    }

    private static func traitStatePredicate(
        base: ElementPredicate,
        trait: HeistTrait,
        isPresent: Bool
    ) -> ElementPredicate {
        var predicate = base
        if isPresent {
            predicate.traits = orderedUnique(predicate.traits + [trait])
            predicate.excludeTraits.removeAll { $0 == trait }
        } else {
            predicate.excludeTraits = orderedUnique(predicate.excludeTraits + [trait])
            predicate.traits.removeAll { $0 == trait }
        }
        return predicate
    }

    private static func orderedUnique(_ traits: [HeistTrait]) -> [HeistTrait] {
        AccessibilityPolicy.orderedMatcherTraits(Array(Set(traits)))
    }
}

extension FenceResponse {
    struct HeistRecordingReceipt {
        let actionResult: ActionResult
        let expectation: ExpectationResult?

        var shouldRecord: Bool {
            actionResult.success && expectation?.met != false
        }
    }

    var heistRecordingReceipt: HeistRecordingReceipt? {
        guard case .action(_, let result, let expectation) = self else { return nil }
        return HeistRecordingReceipt(actionResult: result, expectation: expectation)
    }
}
