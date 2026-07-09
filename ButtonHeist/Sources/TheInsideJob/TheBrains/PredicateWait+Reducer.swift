#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
import TheScore

extension PredicateWait {
    internal struct Reducer: Sendable, Equatable {
        private let step: ResolvedWaitStep
        private let timeout: Double
        private let allowsTransitionFinalStateWarning: Bool

        internal init(
            step: ResolvedWaitStep,
            timeout: Double,
            allowsTransitionFinalStateWarning: Bool
        ) {
            self.step = step
            self.timeout = timeout
            self.allowsTransitionFinalStateWarning = allowsTransitionFinalStateWarning
        }

        internal func reduce(
            _ state: State,
            event: Event
        ) -> State {
            switch event {
            case .baseline(let observation):
                return state.recordingBaseline(observation)
            case .observation(let observation):
                return state.recording(observation)
            }
        }

        internal func decision(
            _ state: State,
            timedOutWhenUnmatched: Bool = true
        ) -> Decision {
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

        internal func decision(
            after event: Event,
            reducing state: State,
            timedOutWhenUnmatched: Bool = true
        ) -> Decision {
            decision(
                reduce(state, event: event),
                timedOutWhenUnmatched: timedOutWhenUnmatched
            )
        }

        private func finalStateSatisfiedTransitionWarning(
            for predicate: AccessibilityPredicate,
            state: State
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
            state: State,
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
            state: State,
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
                ElementMatchGraph(elements: elements).resolve($0).elements
            } ?? elements

            for element in candidates
            where Self.destinationPropertyChange(for: change.property, in: element)?.satisfies(change) == true {
                return Self.warningEvidence(for: element)
            }
            return nil
        }

        private static func isPresent(_ predicate: ElementPredicate, in elements: [HeistElement]) -> Bool {
            !ElementMatchGraph(elements: elements).resolve(predicate).isEmpty
        }

        private static func presenceEvidence(of predicate: ElementPredicate, in elements: [HeistElement]) -> String? {
            ElementMatchGraph(elements: elements).resolve(predicate).elements.first.map(warningEvidence(for:))
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

    internal enum State: Sendable, Equatable {
        case unobserved(ExpectationResult)
        case observed(Snapshot)

        internal init(predicate: AccessibilityPredicate) {
            self = .unobserved(ExpectationResult(
                met: false,
                predicate: predicate,
                actual: "no settled semantic observation available"
            ))
        }

        internal var evaluation: ExpectationResult {
            switch self {
            case .unobserved(let expectation):
                return expectation
            case .observed(let snapshot):
                return snapshot.expectation
            }
        }

        internal var lastTrace: AccessibilityTrace? {
            guard case .observed(let snapshot) = self else { return nil }
            return snapshot.observation.trace
        }

        internal var lastObservationSummary: String? {
            guard case .observed(let snapshot) = self else { return nil }
            return snapshot.observation.summary
        }

        internal var lastVisibleFingerprint: PredicateVisibleFingerprint {
            guard case .observed(let snapshot) = self else { return .unknown }
            return snapshot.observation.visibleFingerprint
        }

        internal var observedSequence: SettledObservationSequence? {
            guard case .observed(let snapshot) = self else { return nil }
            return snapshot.observation.sequence
        }

        internal var changeBaseline: WaitChangeBaseline? {
            guard case .observed(let snapshot) = self else { return nil }
            return snapshot.changeReadiness.baseline
        }

        internal var changeReadiness: PredicateChangeReadiness {
            guard case .observed(let snapshot) = self else { return .notRequired }
            return snapshot.changeReadiness
        }

        internal var observedChangeAfterBaseline: Bool {
            guard case .observed(let snapshot) = self else { return false }
            return snapshot.changeReadiness.observedChangeAfterBaseline
        }

        internal var finalElements: [HeistElement]? {
            lastTrace?.captures.last?.interface.projectedElements
        }

        internal func recording(_ snapshot: Snapshot) -> State {
            .observed(snapshot)
        }

        internal func recordingBaseline(_ snapshot: Snapshot) -> State {
            .observed(snapshot)
        }
    }

    internal struct Snapshot: Sendable, Equatable {
        internal let observation: WaitObservation
        internal let expectation: ExpectationResult
        internal let changeReadiness: PredicateChangeReadiness

        internal init(
            observation: WaitObservation,
            expectation: ExpectationResult,
            changeReadiness: PredicateChangeReadiness
        ) {
            self.observation = observation
            self.expectation = expectation
            self.changeReadiness = changeReadiness
        }
    }

    internal struct WaitObservation: Sendable, Equatable {
        internal let trace: AccessibilityTrace?
        internal let summary: String
        internal let visibleFingerprint: PredicateVisibleFingerprint
        internal let sequence: SettledObservationSequence

        internal init(
            trace: AccessibilityTrace?,
            summary: String,
            visibleFingerprint: PredicateVisibleFingerprint,
            sequence: SettledObservationSequence
        ) {
            self.trace = trace
            self.summary = summary
            self.visibleFingerprint = visibleFingerprint
            self.sequence = sequence
        }
    }

    internal enum Event: Sendable, Equatable {
        case baseline(Snapshot)
        case observation(Snapshot)
    }

    internal enum Decision: Sendable, Equatable {
        case poll(State)
        case satisfied(State, warning: HeistPredicateWarning?)
        case failed(State)

        internal var state: State {
            switch self {
            case .poll(let state),
                 .satisfied(let state, _),
                 .failed(let state):
                return state
            }
        }

        internal var isSatisfied: Bool {
            guard case .satisfied = self else { return false }
            return true
        }
    }

    private enum FinalStateSatisfactionTiming: String {
        case baseline
        case afterObservation = "after_observation"
    }
}

internal struct WaitChangeBaseline: Sendable, Equatable {
    internal let sequence: SettledObservationSequence
    internal let capture: AccessibilityTrace.Capture?

    internal var hash: String? {
        capture?.hash
    }

    internal init(sequence: SettledObservationSequence, capture: AccessibilityTrace.Capture?) {
        self.sequence = sequence
        self.capture = capture
    }
}

extension WaitChangeBaseline {
    internal init(event: SettledSemanticObservationEvent) {
        self.init(sequence: event.sequence, capture: event.trace.captures.last)
    }

    internal init?(previousOf event: SettledSemanticObservationEvent) {
        guard let previous = event.previous,
              previous.sequence < event.sequence,
              let capture = event.trace.captures.first
        else { return nil }
        self.init(sequence: previous.sequence, capture: capture)
    }
}

extension PredicateWait {
    internal struct ObservedChange: Sendable, Equatable {
        internal let baseline: WaitChangeBaseline
        internal let observedSequence: SettledObservationSequence

        internal init?(
            baseline: WaitChangeBaseline,
            observedSequence: SettledObservationSequence
        ) {
            guard observedSequence > baseline.sequence else { return nil }
            self.baseline = baseline
            self.observedSequence = observedSequence
        }
    }
}

internal enum PredicateChangeReadiness: Sendable, Equatable {
    case notRequired
    case baselineOnly(WaitChangeBaseline)
    case observedTransition(PredicateWait.ObservedChange)
    case unavailableTrace(PredicateWait.ObservedChange)

    internal var baseline: WaitChangeBaseline? {
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

    internal var observedChangeAfterBaseline: Bool {
        switch self {
        case .observedTransition, .unavailableTrace:
            return true
        case .notRequired, .baselineOnly:
            return false
        }
    }

    internal var canEvaluateFinalStateWarning: Bool {
        switch self {
        case .notRequired, .baselineOnly, .observedTransition, .unavailableTrace:
            return true
        }
    }
}

internal enum PredicateVisibleFingerprint: Sendable, Equatable {
    case unknown
    case known(String)

    internal init(_ rawValue: String?) {
        if let rawValue {
            self = .known(rawValue)
        } else {
            self = .unknown
        }
    }

    internal func replacingUnknown(with fallback: PredicateVisibleFingerprint) -> PredicateVisibleFingerprint {
        switch self {
        case .known:
            return self
        case .unknown:
            return fallback
        }
    }
}

extension AccessibilityPredicate {
    fileprivate var singleAppearedElementMatcher: ElementPredicate? {
        guard case .changePredicate(.elementsScope(let assertions)) = self,
              assertions.count == 1,
              case .appearedElement(let element) = assertions[0] else {
            return nil
        }
        return element
    }

    fileprivate var singleDisappearedElementMatcher: ElementPredicate? {
        guard case .changePredicate(.elementsScope(let assertions)) = self,
              assertions.count == 1,
              case .disappearedElement(let element) = assertions[0] else {
            return nil
        }
        return element
    }

    fileprivate var singleUpdatedElementWithDestination: ElementUpdatePredicate? {
        guard case .changePredicate(.elementsScope(let assertions)) = self,
              assertions.count == 1,
              case .updatedElement(let update) = assertions[0],
              update.change?.destinationChange != nil else {
            return nil
        }
        return update
    }
}

extension AnyPropertyChange {
    fileprivate var destinationChange: AnyPropertyChange? {
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

extension ElementPropertyChange {
    fileprivate var destinationOnlyChange: ElementPropertyChange<P>? {
        guard before == nil, let after else { return nil }
        return ElementPropertyChange(after: after)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
