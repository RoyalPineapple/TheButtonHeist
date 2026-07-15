#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
import TheScore

extension PredicateWait {
    internal struct Reducer: Sendable, Equatable {
        internal init() {}

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
                return .satisfied(state)
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

        internal var observedSequence: SettledObservationSequence? {
            guard case .observed(let snapshot) = self else { return nil }
            return snapshot.observation.sequence
        }

        internal var changeBaseline: SettledCapture? {
            guard case .observed(let snapshot) = self else { return nil }
            return snapshot.baseline
        }

        internal var observedChangeAfterBaseline: Bool {
            guard case .observed(let snapshot) = self,
                  let baseline = snapshot.baseline,
                  let window = snapshot.window
            else { return false }
            return window.current.cursor.sequence > baseline.cursor.sequence
        }

        internal var observationWindow: ObservationWindow? {
            guard case .observed(let snapshot) = self else { return nil }
            return snapshot.window
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
        internal let baseline: SettledCapture?
        internal let window: ObservationWindow?

        internal init(
            observation: WaitObservation,
            expectation: ExpectationResult,
            baseline: SettledCapture?,
            window: ObservationWindow?
        ) {
            self.observation = observation
            self.expectation = expectation
            self.baseline = baseline
            self.window = window
        }
    }

    internal struct WaitObservation: Sendable, Equatable {
        internal let trace: AccessibilityTrace?
        internal let summary: String
        internal let sequence: SettledObservationSequence

        internal init(
            trace: AccessibilityTrace?,
            summary: String,
            sequence: SettledObservationSequence
        ) {
            self.trace = trace
            self.summary = summary
            self.sequence = sequence
        }
    }

    internal enum Event: Sendable, Equatable {
        case baseline(Snapshot)
        case observation(Snapshot)
    }

    internal enum Decision: Sendable, Equatable {
        case poll(State)
        case satisfied(State)
        case failed(State)

        internal var state: State {
            switch self {
            case .poll(let state),
                 .satisfied(let state),
                 .failed(let state):
                return state
            }
        }

        internal var isSatisfied: Bool {
            guard case .satisfied = self else { return false }
            return true
        }
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
