import TheScore

enum HeistRecordingEffect {
    case ignore
    case discardDeferredSetup
    case deferUntilFinish([HeistStep])
    case appendReplacingDeferredSetup([HeistStep])
    case appendAfterDeferredSetup([HeistStep])
}

/// Projects a validated interaction response into a durable heist recording
/// effect.
///
/// Recording composition owns the evidence-to-step decision. It does not
/// dispatch commands, validate expectations, resolve targets, or write storage.
struct HeistRecordingComposition {
    let request: TheFence.ParsedRequest
    let actionResult: ActionResult?
    let expectation: ExpectationResult?

    func effect() throws -> HeistRecordingEffect {
        if request.command.viewportDebugCommand != nil {
            return .discardDeferredSetup
        }
        guard request.command.heistPrimitiveCommand != nil else {
            return .ignore
        }
        guard let actionResult, actionResult.success else {
            return HeistRecordingEffectPolicy.unrecordedSemanticEffect(for: request)
        }
        // The recorded expectation must not have failed.
        guard expectation?.met != false else {
            return HeistRecordingEffectPolicy.unrecordedSemanticEffect(for: request)
        }
        if request.expectationPayload.expectation != nil,
           expectation?.met != true {
            return HeistRecordingEffectPolicy.unrecordedSemanticEffect(for: request)
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
            return .appendAfterDeferredSetup([
                .wait(WaitStep(predicate: target.predicate, timeout: target.resolvedTimeout)),
            ])
        }

        if case .scrollToVisible = message {
            return .discardDeferredSetup
        }

        guard !HeistRecordingEffectPolicy.hasUnrecordableSemanticEvidence(
            message,
            actionResult: actionResult
        ) else {
            return .discardDeferredSetup
        }

        let normalizedCommand = RecordingActionNormalization.normalizedCommand(
            message,
            actionResult: actionResult
        )
        let recordedExpectation = RecordingExpectationInference.recordedExpectation(
            request: request,
            actionResult: actionResult,
            expectation: expectation
        )
        let step = HeistStep.action(try ActionStep(
            command: normalizedCommand,
            expectation: recordedExpectation
        ))
        return HeistRecordingEffectPolicy.recordedActionEffect(
            command: normalizedCommand,
            expectation: recordedExpectation,
            step: step
        )
    }
}

enum HeistRecordingEffectPolicy {
    static func unrecordedSemanticEffect(for request: TheFence.ParsedRequest) -> HeistRecordingEffect {
        request.discardsDeferredSetup ? .discardDeferredSetup : .ignore
    }

    static func recordedActionEffect(
        command: ClientMessage,
        expectation: WaitStep?,
        step: HeistStep
    ) -> HeistRecordingEffect {
        switch command {
        case .scroll, .scrollToEdge:
            return .discardDeferredSetup
        case .activate, .increment, .decrement, .performCustomAction, .rotor:
            return .appendReplacingDeferredSetup([step])
        case .typeText(let target) where target.elementTarget != nil:
            return .appendReplacingDeferredSetup([step])
        case .scrollToVisible:
            return .discardDeferredSetup
        case .oneFingerTap, .longPress, .swipe, .drag,
             .typeText, .editAction, .setPasteboard, .resignFirstResponder,
             .clientHello, .authenticate, .requestInterface, .ping, .status,
             .getPasteboard, .requestScreen, .wait, .heistPlan:
            return .appendAfterDeferredSetup([step])
        }
    }

    static func hasUnrecordableSemanticEvidence(
        _ message: ClientMessage,
        actionResult: ActionResult
    ) -> Bool {
        if message.requiresMinimumSemanticRecordingTarget {
            // A semantic action records a minimum durable target derived from
            // settled before-state evidence. A post-action state that never
            // settled is not durable proof, so the step is dropped rather than
            // recorded from the caller's raw input. Settled evidence that
            // cannot disambiguate the subject is dropped for the same reason.
            if actionResult.settled == false {
                return true
            }
            guard actionResult.subjectEvidence != nil,
                  actionResult.accessibilityTrace?.captures.first != nil
            else { return false }
            return RecordingTargetSelection.minimumTarget(actionResult: actionResult) == nil
        }
        guard actionResult.settled != false,
              let evidence = actionResult.subjectEvidence,
              actionResult.accessibilityTrace?.captures.first != nil
        else { return false }
        if case .oneFingerTap = message,
           RecordingTargetSelection.isActivatable(evidence.element) {
            return RecordingTargetSelection.minimumTarget(actionResult: actionResult) == nil
        }
        return false
    }
}

enum RecordingExpectationInference {
    static func recordedExpectation(
        request: TheFence.ParsedRequest,
        actionResult: ActionResult,
        expectation: ExpectationResult?
    ) -> WaitStep? {
        if let explicit = request.expectationPayload.expectation,
           expectation?.met == true {
            return WaitStep(
                predicate: explicit,
                timeout: request.expectationPayload.postActionValidationTimeout ?? 10
            )
        }
        return inferredExpectation(actionResult: actionResult)
    }

    private static func inferredExpectation(actionResult: ActionResult) -> WaitStep? {
        guard actionResult.settled != false,
              let target = RecordingTargetSelection.minimumTarget(actionResult: actionResult),
              let trace = actionResult.accessibilityTrace,
              let before = trace.captures.first,
              let after = trace.captures.last,
              before.hash != after.hash
        else { return nil }

        if case .screenChanged? = trace.endpointDelta {
            return WaitStep(predicate: .changed(.screen()), timeout: 10)
        }

        let beforeElements = before.interface.projectedElements
        let afterElements = after.interface.projectedElements
        guard let beforeIndex = RecordingTargetSelection.index(of: target, in: beforeElements) else { return nil }
        let beforeElement = beforeElements[beforeIndex]
        guard let afterIndex = RecordingTargetSelection.index(of: target, in: afterElements) else {
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

enum RecordingActionNormalization {
    static func normalizedCommand(
        _ message: ClientMessage,
        actionResult: ActionResult
    ) -> ClientMessage {
        switch message {
        case .activate(let target):
            return .activate(RecordingTargetSelection.normalizedTarget(target, actionResult: actionResult))
        case .increment(let target):
            return .increment(RecordingTargetSelection.normalizedTarget(target, actionResult: actionResult))
        case .decrement(let target):
            return .decrement(RecordingTargetSelection.normalizedTarget(target, actionResult: actionResult))
        case .performCustomAction(let target):
            return .performCustomAction(CustomActionTarget(
                elementTarget: RecordingTargetSelection.normalizedTarget(target.elementTarget, actionResult: actionResult),
                actionName: target.actionName
            ))
        case .rotor(let target):
            return .rotor(RotorTarget(
                elementTarget: RecordingTargetSelection.normalizedTarget(target.elementTarget, actionResult: actionResult),
                selection: target.selection,
                direction: target.direction
            ))
        case .oneFingerTap(let target):
            if let activationTarget = RecordingTargetSelection.activationTarget(actionResult: actionResult) {
                return .activate(activationTarget)
            }
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
                    RecordingTargetSelection.normalizedTarget($0, actionResult: actionResult)
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
            return .element(RecordingTargetSelection.normalizedTarget(target, actionResult: actionResult))
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
                RecordingTargetSelection.normalizedTarget(element, actionResult: actionResult),
                start: start,
                end: end
            )
        case .elementDirection(let element, let direction):
            selection = .elementDirection(
                RecordingTargetSelection.normalizedTarget(element, actionResult: actionResult),
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
                selection: .elementToPoint(
                    RecordingTargetSelection.normalizedTarget(element, actionResult: actionResult),
                    end: end
                ),
                duration: target.duration
            )
        case .pointToPoint:
            return target
        }
    }
}

enum RecordingTargetSelection {
    static func normalizedTarget(
        _ target: ElementTarget,
        actionResult: ActionResult
    ) -> ElementTarget {
        minimumTarget(actionResult: actionResult) ?? target
    }

    static func activationTarget(actionResult: ActionResult) -> ElementTarget? {
        guard let evidence = actionResult.subjectEvidence,
              isActivatable(evidence.element)
        else { return nil }
        return minimumTarget(actionResult: actionResult)
    }

    static func isActivatable(_ element: HeistElement) -> Bool {
        element.actions.contains(.activate)
            || element.traits.contains { AccessibilityPolicy.interactiveTraits.contains($0) }
    }

    static func minimumTarget(actionResult: ActionResult) -> ElementTarget? {
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

    static func index(of target: ElementTarget, in elements: [HeistElement]) -> Int? {
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
}

private extension TheFence.ParsedRequest {
    var discardsDeferredSetup: Bool {
        executableMessages?.contains { $0.discardsDeferredSetup } == true
    }
}

private extension ClientMessage {
    var discardsDeferredSetup: Bool {
        requiresMinimumSemanticRecordingTarget
    }

    var requiresMinimumSemanticRecordingTarget: Bool {
        switch self {
        case .activate, .increment, .decrement, .performCustomAction, .rotor:
            return true
        case .typeText(let target):
            return target.elementTarget != nil
        case .oneFingerTap, .longPress, .swipe, .drag, .scroll, .scrollToVisible,
             .scrollToEdge, .editAction, .setPasteboard, .resignFirstResponder,
             .clientHello, .authenticate, .requestInterface, .ping, .status,
             .getPasteboard, .requestScreen, .wait, .heistPlan:
            return false
        }
    }
}
