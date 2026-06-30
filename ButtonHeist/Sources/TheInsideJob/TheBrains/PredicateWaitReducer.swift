#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
import TheScore

struct PredicateWaitReducer: Sendable, Equatable {
    let step: ResolvedWaitStep
    let timeout: Double
    let allowsTransitionFinalStateWarning: Bool

    func reduce(
        _ state: PredicateWaitState,
        event: PredicateWaitEvent
    ) -> PredicateWaitState {
        switch event {
        case .baseline(let observation):
            return state.recordingBaseline(observation)
        case .observation(let observation):
            return state.recording(observation)
        }
    }

    func decision(
        _ state: PredicateWaitState,
        timedOutWhenUnmatched: Bool = true
    ) -> PredicateWaitDecision {
        if state.evaluation.met {
            return .satisfied(state, warning: nil)
        }
        if allowsTransitionFinalStateWarning,
           state.changeReadiness.canEvaluateFinalStateWarning,
           let warning = finalStateSatisfiedTransitionWarning(for: step.predicate, state: state) {
            return .satisfied(state, warning: warning)
        }
        return timedOutWhenUnmatched ? .failed(state) : .poll(state)
    }

    func decision(
        after event: PredicateWaitEvent,
        reducing state: PredicateWaitState,
        timedOutWhenUnmatched: Bool = true
    ) -> PredicateWaitDecision {
        decision(
            reduce(state, event: event),
            timedOutWhenUnmatched: timedOutWhenUnmatched
        )
    }

    private func finalStateSatisfiedTransitionWarning(
        for predicate: AccessibilityPredicate,
        state: PredicateWaitState
    ) -> HeistPredicateWarning? {
        if let element = predicate.singleAppearedElementMatcher {
            return presenceFinalStateWarning(
                for: predicate,
                state: state,
                element: element,
                expectedPresence: true
            )
        }

        if let element = predicate.singleDisappearedElementMatcher {
            return presenceFinalStateWarning(
                for: predicate,
                state: state,
                element: element,
                expectedPresence: false
            )
        }

        if let update = predicate.singleUpdatedElementWithDestination {
            return updateFinalStateWarning(
                for: predicate,
                state: state,
                update: update
            )
        }

        return nil
    }

    private func presenceFinalStateWarning(
        for predicate: AccessibilityPredicate,
        state: PredicateWaitState,
        element: ElementPredicate,
        expectedPresence: Bool
    ) -> HeistPredicateWarning? {
        guard let baselineElements = state.changeBaseline?.capture?.interface.projectedElements else {
            return nil
        }

        let timing: FinalStateSatisfactionTiming
        let evidence: String
        if let baselineEvidence = Self.presenceEvidence(of: element, in: baselineElements),
           expectedPresence {
            timing = .baseline
            evidence = baselineEvidence
        } else if !expectedPresence,
                  !Self.isPresent(element, in: baselineElements) {
            timing = .baseline
            evidence = Self.warningSubject(for: element)
        } else if let finalElements = state.finalElements,
                  let finalEvidence = Self.presenceEvidence(of: element, in: finalElements),
                  expectedPresence {
            timing = .afterObservation
            evidence = finalEvidence
        } else if let finalElements = state.finalElements,
                  !expectedPresence,
                  !Self.isPresent(element, in: finalElements) {
            timing = .afterObservation
            evidence = Self.warningSubject(for: element)
        } else {
            return nil
        }

        let subject = Self.warningSubject(for: element)
        let stateDescription = expectedPresence ? "present" : "absent"
        let transitionDescription = expectedPresence ? "appearance" : "disappearance"
        let timingDescription = timing == .baseline
            ? "was already \(stateDescription) when the wait began"
            : "satisfied the \(stateDescription) final state without an observed transition"
        let message = "\(subject) \(timingDescription), so no \(transitionDescription) was observed. "
            + "The final state satisfied the wait."
        return HeistPredicateWarning(
            code: "transition_not_observed_final_state_satisfied",
            predicate: predicate.description,
            impliedPredicate: AccessibilityPredicate.state(expectedPresence ? .exists(element) : .missing(element)).description,
            finalStateTiming: timing.rawValue,
            evidence: evidence,
            message: message
        )
    }

    private func updateFinalStateWarning(
        for predicate: AccessibilityPredicate,
        state: PredicateWaitState,
        update: ElementUpdatePredicate
    ) -> HeistPredicateWarning? {
        guard let baselineElements = state.changeBaseline?.capture?.interface.projectedElements
        else { return nil }

        let timing: FinalStateSatisfactionTiming
        let evidence: String
        if let baselineEvidence = Self.updateFinalStateEvidence(update, in: baselineElements) {
            timing = .baseline
            evidence = baselineEvidence
        } else if let finalElements = state.finalElements,
                  let finalEvidence = Self.updateFinalStateEvidence(update, in: finalElements) {
            timing = .afterObservation
            evidence = finalEvidence
        } else {
            return nil
        }

        let timingDescription = timing == .baseline
            ? "was already satisfied when the wait began"
            : "became satisfied without an observed matching transition"
        let message = "The destination update state \(timingDescription), so no update transition was observed. "
            + "The final state satisfied the wait."
        return HeistPredicateWarning(
            code: "transition_not_observed_final_state_satisfied",
            predicate: predicate.description,
            impliedPredicate: Self.impliedUpdateFinalStateDescription(update),
            finalStateTiming: timing.rawValue,
            evidence: evidence,
            message: message
        )
    }

    private static func updateFinalStateEvidence(
        _ update: ElementUpdatePredicate,
        in elements: [HeistElement]
    ) -> String? {
        guard let change = update.change?.destinationChange else { return nil }
        let candidates = update.element.map {
            ElementMatchSet(elements: elements).matching($0).elements
        } ?? elements

        for element in candidates
        where Self.destinationPropertyChange(for: change.property, in: element)?.satisfies(change) == true {
            return Self.warningEvidence(for: element)
        }
        return nil
    }

    private static func isPresent(_ predicate: ElementPredicate, in elements: [HeistElement]) -> Bool {
        !ElementMatchSet(elements: elements).matching(predicate).isEmpty
    }

    private static func presenceEvidence(of predicate: ElementPredicate, in elements: [HeistElement]) -> String? {
        ElementMatchSet(elements: elements).matching(predicate).elements.first.map(warningEvidence(for:))
    }

    private static func warningEvidence(for element: HeistElement) -> String {
        if let label = element.label, !label.isEmpty {
            return "label=\(label)"
        }
        if let identifier = element.identifier, !identifier.isEmpty {
            return "identifier=\(identifier)"
        }
        return "description=\(element.description)"
    }

    private static func impliedUpdateFinalStateDescription(_ update: ElementUpdatePredicate) -> String? {
        guard let destinationChange = update.change?.destinationChange else { return nil }
        let subject = update.element.map { "element=\($0)" } ?? "element=any"
        return ScoreDescription.call("destination_state", [
            subject,
            "change=\(destinationChange)",
        ])
    }

    private static func destinationPropertyChange(
        for property: ElementProperty,
        in element: HeistElement
    ) -> PropertyChange? {
        switch property {
        case .label, .identifier:
            return nil
        case .value:
            return ValueProperty.value(in: element).map { .value(old: nil, new: $0) }
        case .traits:
            return TraitsProperty.value(in: element).map { .traits(old: nil, new: $0) }
        case .hint:
            return HintProperty.value(in: element).map { .hint(old: nil, new: $0) }
        case .actions:
            return ActionsProperty.value(in: element).map { .actions(old: nil, new: $0) }
        case .frame:
            return FrameProperty.value(in: element).map { .frame(old: nil, new: $0) }
        case .activationPoint:
            return ActivationPointProperty.value(in: element).map { .activationPoint(old: nil, new: $0) }
        case .customContent:
            return CustomContentProperty.value(in: element).map { .customContent(old: nil, new: $0) }
        case .rotors:
            return RotorsProperty.value(in: element).map { .rotors(old: nil, new: $0) }
        }
    }

    private static func warningSubject(for predicate: ElementPredicate) -> String {
        for check in predicate.checks {
            if case .label(.exact(let label)) = check, !label.isEmpty {
                return label
            }
        }
        return "The element"
    }
}

enum PredicateWaitState: Sendable, Equatable {
    case unobserved(ExpectationResult)
    case observed(PredicateWaitSnapshot)

    init(predicate: AccessibilityPredicate) {
        self = .unobserved(ExpectationResult(
            met: false,
            predicate: predicate,
            actual: "no settled semantic observation available"
        ))
    }

    var evaluation: ExpectationResult {
        switch self {
        case .unobserved(let expectation):
            return expectation
        case .observed(let snapshot):
            return snapshot.expectation
        }
    }

    var lastTrace: AccessibilityTrace? {
        guard case .observed(let snapshot) = self else { return nil }
        return snapshot.observation.trace
    }

    var lastObservationSummary: String? {
        guard case .observed(let snapshot) = self else { return nil }
        return snapshot.observation.summary
    }

    var lastVisibleFingerprint: PredicateVisibleFingerprint {
        guard case .observed(let snapshot) = self else { return .unknown }
        return snapshot.observation.visibleFingerprint
    }

    var observedSequence: SettledObservationSequence? {
        guard case .observed(let snapshot) = self else { return nil }
        return snapshot.observation.sequence
    }

    var changeBaseline: WaitChangeBaseline? {
        guard case .observed(let snapshot) = self else { return nil }
        return snapshot.changeReadiness.baseline
    }

    var changeReadiness: PredicateChangeReadiness {
        guard case .observed(let snapshot) = self else { return .notRequired }
        return snapshot.changeReadiness
    }

    var observedChangeAfterBaseline: Bool {
        guard case .observed(let snapshot) = self else { return false }
        return snapshot.changeReadiness.observedChangeAfterBaseline
    }

    var finalElements: [HeistElement]? {
        lastTrace?.captures.last?.interface.projectedElements
    }

    func recording(_ snapshot: PredicateWaitSnapshot) -> PredicateWaitState {
        .observed(snapshot)
    }

    func recordingBaseline(_ snapshot: PredicateWaitSnapshot) -> PredicateWaitState {
        .observed(snapshot)
    }
}

struct PredicateWaitSnapshot: Sendable, Equatable {
    let observation: PredicateWaitObservation
    let expectation: ExpectationResult
    let changeReadiness: PredicateChangeReadiness
}

struct WaitChangeBaseline: Sendable, Equatable {
    let sequence: SettledObservationSequence
    let capture: AccessibilityTrace.Capture?

    var hash: String? {
        capture?.hash
    }

    init(sequence: SettledObservationSequence, capture: AccessibilityTrace.Capture?) {
        self.sequence = sequence
        self.capture = capture
    }
}

struct PredicateObservedChange: Sendable, Equatable {
    let baseline: WaitChangeBaseline
    let observedSequence: SettledObservationSequence

    init?(
        baseline: WaitChangeBaseline,
        observedSequence: SettledObservationSequence
    ) {
        guard observedSequence > baseline.sequence else { return nil }
        self.baseline = baseline
        self.observedSequence = observedSequence
    }
}

enum PredicateChangeReadiness: Sendable, Equatable {
    case notRequired
    case baselineOnly(WaitChangeBaseline)
    case observedTransition(PredicateObservedChange)
    case unavailableTrace(PredicateObservedChange)

    var baseline: WaitChangeBaseline? {
        switch self {
        case .notRequired:
            return nil
        case .baselineOnly(let baseline):
            return baseline
        case .observedTransition(let transition),
             .unavailableTrace(let transition):
            return transition.baseline
        }
    }

    var observedChangeAfterBaseline: Bool {
        switch self {
        case .observedTransition, .unavailableTrace:
            return true
        case .notRequired, .baselineOnly:
            return false
        }
    }

    var canEvaluateFinalStateWarning: Bool {
        switch self {
        case .notRequired, .baselineOnly, .observedTransition, .unavailableTrace:
            return true
        }
    }
}

struct PredicateWaitObservation: Sendable, Equatable {
    let trace: AccessibilityTrace?
    let summary: String
    let visibleFingerprint: PredicateVisibleFingerprint
    let sequence: SettledObservationSequence
}

enum PredicateWaitEvent: Sendable, Equatable {
    case baseline(PredicateWaitSnapshot)
    case observation(PredicateWaitSnapshot)
}

enum PredicateWaitDecision: Sendable, Equatable {
    case poll(PredicateWaitState)
    case satisfied(PredicateWaitState, warning: HeistPredicateWarning?)
    case failed(PredicateWaitState)

    var state: PredicateWaitState {
        switch self {
        case .poll(let state),
             .satisfied(let state, _),
             .failed(let state):
            return state
        }
    }

    var isSatisfied: Bool {
        guard case .satisfied = self else { return false }
        return true
    }
}

enum PredicateVisibleFingerprint: Sendable, Equatable {
    case unknown
    case known(String)

    init(_ rawValue: String?) {
        if let rawValue {
            self = .known(rawValue)
        } else {
            self = .unknown
        }
    }

    func replacingUnknown(with fallback: PredicateVisibleFingerprint) -> PredicateVisibleFingerprint {
        switch self {
        case .known:
            return self
        case .unknown:
            return fallback
        }
    }
}

private enum FinalStateSatisfactionTiming: String {
    case baseline
    case afterObservation = "after_observation"
}

private extension AccessibilityPredicate {
    var singleAppearedElementMatcher: ElementPredicate? {
        guard case .changePredicate(.elementsScope(let assertions)) = self,
              assertions.count == 1,
              case .appearedElement(let element) = assertions[0] else {
            return nil
        }
        return element
    }

    var singleDisappearedElementMatcher: ElementPredicate? {
        guard case .changePredicate(.elementsScope(let assertions)) = self,
              assertions.count == 1,
              case .disappearedElement(let element) = assertions[0] else {
            return nil
        }
        return element
    }

    var singleUpdatedElementWithDestination: ElementUpdatePredicate? {
        guard case .changePredicate(.elementsScope(let assertions)) = self,
              assertions.count == 1,
              case .updatedElement(let update) = assertions[0],
              update.change?.destinationChange != nil else {
            return nil
        }
        return update
    }
}

private extension AnyPropertyChange {
    var destinationChange: AnyPropertyChange? {
        switch self {
        case .value(let change):
            return change.destinationOnlyChange.map { .value($0) }
        case .traits(let change):
            return change.destinationOnlyChange.map { .traits($0) }
        case .hint(let change):
            return change.destinationOnlyChange.map { .hint($0) }
        case .actions(let change):
            return change.destinationOnlyChange.map { .actions($0) }
        case .frame(let change):
            return change.destinationOnlyChange.map { .frame($0) }
        case .activationPoint(let change):
            return change.destinationOnlyChange.map { .activationPoint($0) }
        case .customContent(let change):
            return change.destinationOnlyChange.map { .customContent($0) }
        case .rotors(let change):
            return change.destinationOnlyChange.map { .rotors($0) }
        }
    }
}

private extension ElementPropertyChange {
    var destinationOnlyChange: ElementPropertyChange<P>? {
        guard before == nil, let after else { return nil }
        return ElementPropertyChange(after: after)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
