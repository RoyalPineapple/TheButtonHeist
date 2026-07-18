#if canImport(UIKit)
#if DEBUG
import Foundation
import UIKit

import AccessibilitySnapshotParser

// MARK: - Settle Event/Outcome

/// Signal observed while the AX-tree settle loop was waiting.
///
/// These are not settle outcomes and do not classify screen changes. They are
/// lightweight facts that tell the caller why the loop reset its baseline and
/// re-parsed before proving the post-transition AX tree became stable.
enum SettleEvent: Equatable, Sendable {
    case tripwireSignalChanged(
        from: TheTripwire.TripwireSignal,
        to: TheTripwire.TripwireSignal
    )
}

extension Array where Element == SettleEvent {
    var containsTripwireSignalChange: Bool {
        contains { event in
            if case .tripwireSignalChanged = event { return true }
            return false
        }
    }
}

/// Result of running the multi-cycle AX-tree settle loop.
enum SettleOutcome: Equatable {

    /// The AX tree reached `cyclesRequired` consecutive stable cycles.
    case settled(timeMs: Int)

    /// The hard timeout elapsed while the tree was still changing.
    case timedOut(timeMs: Int)

    /// The loop's structured-concurrency context was cancelled (e.g. the
    /// session was torn down mid-action). Distinct from `.timedOut` so the
    /// caller can short-circuit the rest of the action pipeline rather than
    /// continue parsing/exploring on a dead session.
    case cancelled(timeMs: Int)

    var timeMs: Int {
        switch self {
        case .settled(let ms), .timedOut(let ms), .cancelled(let ms):
            return ms
        }
    }

    /// True when the response represents a UI state we believe in —
    /// the loop reached multi-cycle stability. A Tripwire signal may have
    /// reset the baseline during the loop, but that event is tracked
    /// separately in `SettleSession.Outcome.events`; it is not itself
    /// stability proof.
    var didSettleCleanly: Bool {
        switch self {
        case .settled: return true
        case .timedOut, .cancelled: return false
        }
    }

    var outcomeDescription: String {
        switch self {
        case .settled(let timeMs):
            return "settled after \(timeMs)ms"
        case .timedOut(let timeMs):
            return "timed out after \(timeMs)ms"
        case .cancelled(let timeMs):
            return "cancelled after \(timeMs)ms"
        }
    }
}

// MARK: - Settle Loop Machine

enum SettleLoopYieldFailure: Equatable, Sendable {
    case cancellation
    case error
}

/// The settle loop has one reducer and one runner. This policy only selects
/// the stability proof and sampling cadence used by that runner.
enum SettlePolicy: Equatable, Sendable {
    case consecutiveCycles(required: Int)
    case quietWindow(milliseconds: Int)
}

struct SettleObservationSample: Equatable, Sendable {
    let fingerprint: Int
}

struct SettleLoopMachine: Equatable {
    enum State: Equatable, Sendable {
        case consecutiveCycles(ConsecutiveCycleState)
        case quietWindow(QuietWindowState)

        init(policy: SettlePolicy, tripwireBaseline: TheTripwire.TripwireSignal) {
            switch policy {
            case .consecutiveCycles(let required):
                self = .consecutiveCycles(ConsecutiveCycleState(
                    required: required,
                    progress: SettleLoopProgress(tripwireBaseline: tripwireBaseline)
                ))
            case .quietWindow(let milliseconds):
                self = .quietWindow(QuietWindowState(
                    milliseconds: milliseconds,
                    progress: SettleLoopProgress(tripwireBaseline: tripwireBaseline)
                ))
            }
        }

        var events: [SettleEvent] {
            progress.events
        }

        fileprivate var progress: SettleLoopProgress {
            switch self {
            case .consecutiveCycles(let state):
                return state.progress
            case .quietWindow(let state):
                return state.progress
            }
        }
    }

    enum Event: Equatable, Sendable {
        case observation(SettleObservationSample, elapsedMs: Int)
        case tripwireSignal(TheTripwire.TripwireSignal)
        case yieldFailed(SettleLoopYieldFailure, elapsedMs: Int)
        case timeout(elapsedMs: Int)
    }

    enum Effect: Equatable, Sendable {
        case continuePolling
        case terminal(Terminal)
    }

    enum Terminal: Equatable, Sendable {
        case settled(timeMs: Int)
        case timedOut(timeMs: Int)
        case cancelled(timeMs: Int)
        case yieldFailed(timeMs: Int)
    }

    struct ConsecutiveCycleState: Equatable, Sendable {
        let required: Int
        fileprivate var progress: SettleLoopProgress
        var previousFingerprint: Int?
        var stableCycles: Int

        fileprivate init(required: Int, progress: SettleLoopProgress) {
            self.required = required
            self.progress = progress
            self.previousFingerprint = nil
            self.stableCycles = 0
        }
    }

    struct QuietWindowState: Equatable, Sendable {
        let milliseconds: Int
        fileprivate var progress: SettleLoopProgress
        var previousFingerprint: Int?
        var quietStartedAtMs: Int?

        fileprivate init(milliseconds: Int, progress: SettleLoopProgress) {
            self.milliseconds = milliseconds
            self.progress = progress
            self.previousFingerprint = nil
            self.quietStartedAtMs = nil
        }
    }

    func advance(_ state: State, with event: Event) -> SettleLoopTransition {
        switch event {
        case .observation(let observation, let elapsedMs):
            return record(observation, elapsedMs: elapsedMs, state: state)
        case .tripwireSignal(let signal):
            return recordTripwireSignal(signal, state: state)
        case .yieldFailed(.cancellation, let elapsedMs):
            return change(to: state, effect: .terminal(.cancelled(timeMs: elapsedMs)))
        case .yieldFailed(.error, let elapsedMs):
            return change(to: state, effect: .terminal(.yieldFailed(timeMs: elapsedMs)))
        case .timeout(let elapsedMs):
            return change(to: state, effect: .terminal(.timedOut(timeMs: elapsedMs)))
        }
    }

    private func record(
        _ observation: SettleObservationSample,
        elapsedMs: Int,
        state: State
    ) -> SettleLoopTransition {
        switch state {
        case .consecutiveCycles(var cycleState):
            if cycleState.previousFingerprint == observation.fingerprint {
                cycleState.stableCycles += 1
            } else {
                cycleState.previousFingerprint = observation.fingerprint
                cycleState.stableCycles = 0
            }

            let nextState = State.consecutiveCycles(cycleState)
            guard cycleState.stableCycles >= cycleState.required else {
                return change(to: nextState, effect: .continuePolling)
            }
            return change(
                to: nextState,
                effect: .terminal(.settled(timeMs: elapsedMs))
            )

        case .quietWindow(var quietState):
            if quietState.previousFingerprint != observation.fingerprint {
                quietState.previousFingerprint = observation.fingerprint
                quietState.quietStartedAtMs = elapsedMs
            }

            let nextState = State.quietWindow(quietState)
            guard let quietStartedAtMs = quietState.quietStartedAtMs,
                  elapsedMs - quietStartedAtMs >= quietState.milliseconds else {
                return change(to: nextState, effect: .continuePolling)
            }
            return change(
                to: nextState,
                effect: .terminal(.settled(timeMs: elapsedMs))
            )
        }
    }

    private func recordTripwireSignal(
        _ signal: TheTripwire.TripwireSignal,
        state: State
    ) -> SettleLoopTransition {
        let previous = state.progress.tripwireBaseline
        guard signal != previous else {
            return change(to: state, effect: .continuePolling)
        }

        switch state {
        case .consecutiveCycles(var cycleState):
            cycleState.progress.tripwireBaseline = signal
            guard signal.requiresSettleBaselineReset(from: previous) else {
                return change(to: .consecutiveCycles(cycleState), effect: .continuePolling)
            }
            cycleState.progress.recordTripwireBaselineReset(from: previous, to: signal)
            cycleState.previousFingerprint = nil
            cycleState.stableCycles = 0
            return change(to: .consecutiveCycles(cycleState), effect: .continuePolling)

        case .quietWindow(var quietState):
            quietState.progress.tripwireBaseline = signal
            guard signal.requiresSettleBaselineReset(from: previous) else {
                return change(to: .quietWindow(quietState), effect: .continuePolling)
            }
            quietState.progress.recordTripwireBaselineReset(from: previous, to: signal)
            quietState.previousFingerprint = nil
            quietState.quietStartedAtMs = nil
            return change(to: .quietWindow(quietState), effect: .continuePolling)
        }
    }

    private func change(to state: State, effect: Effect) -> SettleLoopTransition {
        SettleLoopTransition(state: state, effect: effect)
    }
}

private struct SettleLoopProgress: Equatable, Sendable {
    var tripwireBaseline: TheTripwire.TripwireSignal
    var events: [SettleEvent]

    init(tripwireBaseline: TheTripwire.TripwireSignal) {
        self.tripwireBaseline = tripwireBaseline
        self.events = []
    }

    mutating func recordTripwireBaselineReset(
        from previous: TheTripwire.TripwireSignal,
        to signal: TheTripwire.TripwireSignal
    ) {
        events.append(.tripwireSignalChanged(from: previous, to: signal))
    }
}

struct SettleLoopTransition: Equatable, Sendable {
    let state: SettleLoopMachine.State
    let effect: SettleLoopMachine.Effect
}

@MainActor
final class SettleSessionFinalObservation {
    let observation: InterfaceObservation

    var tree: InterfaceTree { observation.tree }

    init(observation: InterfaceObservation) {
        self.observation = observation
    }
}

// MARK: - SettleSession

/// Multi-cycle accessibility-tree settle loop with inline transient capture.
///
/// Polls the parsed AX tree at fixed intervals. Returns `.settled` after
/// `cyclesRequired` consecutive identical fingerprints — with elements
/// carrying `UIAccessibilityTraits.updatesFrequently` masked out so spinners
/// don't block settle. CALayer animations are *not* consulted: a UI is
/// settled from a screen-reader user's perspective once the AX tree stops
/// changing, regardless of ongoing visual motion (analog clocks, animated
/// gradients, Lottie loops).
///
/// **Settle signal boundary.** SettleSession watches settled AX semantics for
/// both passive observation and active heists. Its policy selects consecutive
/// fingerprint cycles or a quiet wall-clock window; the reducer and runner are
/// shared. `TheTripwire.waitForAllClear`
/// watches CALayers and is deliberately blind to the AX tree; "no layer
/// motion" and "AX tree stable" disagree on every spinner-driven loading
/// state. Viewport movement uses this same reducer with a one-cycle policy.
///
/// The loop seeds `previousFingerprint` from a synchronous parse *before*
/// the first sleep, so a static screen settles after exactly
/// `cyclesRequired` cycles (300 ms with the default 3 × 100 ms), not
/// `cyclesRequired + 1`.
///
/// During the loop, every observed `AccessibilityElement` is keyed by
/// `TimelineKey` and accumulated into `elementsByKey`. After settle, the
/// caller subtracts baseline ∪ final keys to compute transient elements
/// (those that came and went mid-action) — no separate timeline class
/// needed. Owns no state across calls.
///
/// Dependencies are injected as closures so unit tests can drive the loop
/// against a scripted sequence of parse results without standing up a
/// live UIKit hierarchy.
///
/// `@MainActor` justification: drives a MainActor-bound parse loop and stores
/// `@MainActor`-typed provider closures.
@MainActor struct SettleSession {

    /// Number of consecutive identical-fingerprint cycles required before the
    /// AX tree is considered stable. Three is the smallest value that filters
    /// out the typical "one frame of churn between two stable states" pattern
    /// produced by UIKit animations finishing on a frame boundary, while
    /// keeping the best-case settle to `3 × cycleInterval` (~300 ms).
    static let defaultCyclesRequired: Int = 3

    /// Poll interval between AX-tree fingerprint checks. 100 ms is roughly
    /// six display frames at 60 Hz — long enough that a parse + fingerprint
    /// + sleep cycle stays well under one frame of main-actor budget on real
    /// devices, short enough that settle latency is dominated by the
    /// `cyclesRequired × interval` floor rather than per-cycle wait. This is
    /// the poll cadence VoiceOver itself uses for similar idle-checks, which
    /// is why agents driving the same AX surface feel "in sync" at this rate.
    static let defaultCycleIntervalMs: Int = 100

    /// Hard ceiling on how long the settle loop will wait for the AX tree
    /// to quiesce before giving up with `.timedOut`. 5 s is the longest
    /// any well-behaved iOS transition (push, modal, alert, tab switch)
    /// takes to settle in practice; anything longer is almost always a
    /// non-terminating animation (spinner not flagged `updatesFrequently`,
    /// a Lottie loop, a video) and the caller is better off accepting the
    /// last-seen snapshot than blocking the action pipeline further.
    static let defaultTimeoutMs: Int = 5_000

    /// Programmatic viewport movement should normally prove itself after one
    /// run-loop turn. This ceiling allows brief layout churn without turning
    /// page-by-page discovery into action settlement.
    static let viewportTransitionTimeoutMs: Int = 250

    typealias ParseProvider = @MainActor () -> InterfaceObservation?
    typealias TripwireSignalProvider = @MainActor () -> TheTripwire.TripwireSignal
    typealias Sleeper = @Sendable (UInt64) async throws -> Void
    typealias ObservationYield = @MainActor () async throws -> Void
    typealias Clock = @MainActor () -> CFAbsoluteTime

    let parseProvider: ParseProvider
    let tripwireSignalProvider: TripwireSignalProvider
    let observationYield: ObservationYield
    let policy: SettlePolicy
    let clock: Clock
    let timeoutMs: Int

    private init(
        parseProvider: @escaping ParseProvider,
        tripwireSignalProvider: @escaping TripwireSignalProvider,
        observationYield: @escaping ObservationYield,
        policy: SettlePolicy,
        clock: @escaping Clock,
        timeoutMs: Int
    ) {
        self.parseProvider = parseProvider
        self.tripwireSignalProvider = tripwireSignalProvider
        self.observationYield = observationYield
        self.policy = policy
        self.clock = clock
        self.timeoutMs = timeoutMs
    }

    init(
        parseProvider: @escaping ParseProvider,
        tripwireSignalProvider: @escaping TripwireSignalProvider,
        sleeper: @escaping Sleeper = { try await Task.sleep(nanoseconds: $0) },
        cyclesRequired: Int = SettleSession.defaultCyclesRequired,
        cycleIntervalMs: Int = SettleSession.defaultCycleIntervalMs,
        timeoutMs: Int = SettleSession.defaultTimeoutMs
    ) {
        self.init(
            parseProvider: parseProvider,
            tripwireSignalProvider: tripwireSignalProvider,
            observationYield: {
                try await sleeper(UInt64(cycleIntervalMs) * 1_000_000)
            },
            policy: .consecutiveCycles(required: cyclesRequired),
            clock: { CFAbsoluteTimeGetCurrent() },
            timeoutMs: timeoutMs
        )
    }

    init(
        parseProvider: @escaping ParseProvider,
        tripwireSignalProvider: @escaping TripwireSignalProvider,
        observationYield: @escaping ObservationYield,
        clock: @escaping Clock,
        quietWindowMs: Int,
        timeoutMs: Int
    ) {
        self.init(
            parseProvider: parseProvider,
            tripwireSignalProvider: tripwireSignalProvider,
            observationYield: observationYield,
            policy: .quietWindow(milliseconds: quietWindowMs),
            clock: clock,
            timeoutMs: timeoutMs
        )
    }

    /// Live wiring against the real vault/tripwire. The policy selects the
    /// stability proof while this type continues to own the entire loop.
    static func live(
        vault: TheVault,
        tripwire: TheTripwire,
        timeoutMs: Int = SettleSession.defaultTimeoutMs,
        policy: SettlePolicy = .consecutiveCycles(
            required: SettleSession.defaultCyclesRequired
        )
    ) -> SettleSession {
        let observationYield: ObservationYield = switch policy {
        case .consecutiveCycles:
            { try await Task.sleep(nanoseconds: UInt64(SettleSession.defaultCycleIntervalMs) * 1_000_000) }
        case .quietWindow:
            { await tripwire.yieldRealFrames(1) }
        }
        return SettleSession(
            parseProvider: { vault.semanticObservationForSettle() },
            tripwireSignalProvider: { tripwire.tripwireSignal() },
            observationYield: observationYield,
            policy: policy,
            clock: { CFAbsoluteTimeGetCurrent() },
            timeoutMs: timeoutMs
        )
    }

    /// Minimal proof for a programmatic viewport transition. UIKit receives
    /// one run-loop turn to lay out the new viewport, then the parser must
    /// return the same semantic fingerprint on consecutive captures.
    static func viewportTransition(
        vault: TheVault,
        tripwire: TheTripwire,
        timeoutMs: Int
    ) -> SettleSession {
        SettleSession(
            parseProvider: { vault.semanticObservationForSettle() },
            tripwireSignalProvider: { tripwire.tripwireSignal() },
            observationYield: { await tripwire.yieldRealFrames(1) },
            policy: .consecutiveCycles(required: 1),
            clock: { CFAbsoluteTimeGetCurrent() },
            timeoutMs: timeoutMs
        )
    }

    /// Result of the loop, exposed so the caller can compute transients.
    struct Outcome: Sendable {
        let outcome: SettleOutcome
        /// Lightweight signals observed during the loop. These explain why
        /// the settle baseline was reset, but the final `outcome` still owns
        /// whether the AX tree became stable.
        let events: [SettleEvent]
        /// Exact final semantic observation admitted by the settle loop.
        let finalObservation: SettleSessionFinalObservation?
        /// Every `(key, element)` pair observed in any cycle of the loop.
        /// Includes spinner cycles and other intermediate states.
        let elementsByKey: [TimelineKey: AccessibilityElement]
        /// Full tripwire signal paired with the final observed generation.
        let tripwireSignal: TheTripwire.TripwireSignal
        /// Compact explanation of the most recent semantic instability when
        /// the loop exits without a clean settle.
        let instabilityDescription: String?

        init(
            outcome: SettleOutcome,
            events: [SettleEvent],
            finalObservation: SettleSessionFinalObservation?,
            elementsByKey: [TimelineKey: AccessibilityElement],
            tripwireSignal: TheTripwire.TripwireSignal,
            instabilityDescription: String? = nil
        ) {
            precondition(
                !outcome.didSettleCleanly || finalObservation != nil,
                "settled settle outcome requires a final observation"
            )
            self.outcome = outcome
            self.events = events
            self.finalObservation = finalObservation
            self.elementsByKey = elementsByKey
            self.tripwireSignal = tripwireSignal
            self.instabilityDescription = instabilityDescription
        }
    }

    /// Run the settle loop with the full tripwire signal captured before the
    /// action. Visible window/navigation/key changes reset the settle baseline,
    /// then the loop proves the post-transition AX tree is stable before
    /// returning. The returned events record any Tripwire signals observed along
    /// the way so callers can suppress transition transients without treating
    /// the signal itself as a screen-change classification.
    func run(start: CFAbsoluteTime, baselineTripwireSignal: TheTripwire.TripwireSignal) async -> Outcome {
        return await SettleLoopRunner(
            parseProvider: parseProvider,
            tripwireSignalProvider: tripwireSignalProvider,
            observationYield: observationYield,
            clock: clock,
            timeoutMs: timeoutMs,
            initial: SettleLoopMachine.State(
                policy: policy,
                tripwireBaseline: baselineTripwireSignal
            )
        ).run(start: start)
    }

    static func outcome(
        for transition: SettleLoopTransition,
        observations: SettleObservationLedger
    ) -> Outcome? {
        switch transition.effect {
        case .continuePolling:
            return nil
        case .terminal(let terminal):
            return outcome(for: terminal, state: transition.state, observations: observations)
        }
    }

    private static func outcome(
        for terminal: SettleLoopMachine.Terminal,
        state: SettleLoopMachine.State,
        observations: SettleObservationLedger
    ) -> Outcome {
        switch terminal {
        case .settled(let timeMs):
            return Outcome(
                outcome: .settled(timeMs: timeMs),
                events: state.events,
                finalObservation: observations.currentGenerationLastObservation.map {
                    SettleSessionFinalObservation(observation: $0.observation)
                },
                elementsByKey: observations.elementsByKey,
                tripwireSignal: state.progress.tripwireBaseline
            )
        case .timedOut(let timeMs), .yieldFailed(let timeMs):
            return Outcome(
                outcome: .timedOut(timeMs: timeMs),
                events: state.events,
                finalObservation: observations.currentGenerationLastObservation.map {
                    SettleSessionFinalObservation(observation: $0.observation)
                },
                elementsByKey: observations.elementsByKey,
                tripwireSignal: state.progress.tripwireBaseline,
                instabilityDescription: observations.latestChangeDescription
            )
        case .cancelled(let timeMs):
            return Outcome(
                outcome: .cancelled(timeMs: timeMs),
                events: state.events,
                finalObservation: observations.currentGenerationLastObservation.map {
                    SettleSessionFinalObservation(observation: $0.observation)
                },
                elementsByKey: observations.elementsByKey,
                tripwireSignal: state.progress.tripwireBaseline,
                instabilityDescription: observations.latestChangeDescription
            )
        }
    }

    static func transientElements(
        seenByKey: [TimelineKey: AccessibilityElement],
        baseline: [AccessibilityElement],
        final: [AccessibilityElement]
    ) -> [AccessibilityElement] {
        SettleTimeline.transientElements(seenByKey: seenByKey, baseline: baseline, final: final)
    }
}

private struct SettleLoopRunner {
    typealias ObservationYield = @MainActor () async throws -> Void
    typealias Clock = @MainActor () -> CFAbsoluteTime

    let parseProvider: SettleSession.ParseProvider
    let tripwireSignalProvider: SettleSession.TripwireSignalProvider
    let observationYield: ObservationYield
    let clock: Clock
    let timeoutMs: Int
    let initial: SettleLoopMachine.State

    @MainActor
    func run(start: CFAbsoluteTime) async -> SettleSession.Outcome {
        let deadline = SemanticObservationDeadline(start: start, timeoutMs: timeoutMs)
        var observations = SettleObservationLedger()
        let machine = SettleLoopMachine()
        var state = initial
        var terminalObservationOutcome: SettleSession.Outcome?

        func send(_ event: SettleLoopMachine.Event) -> SettleLoopTransition {
            let transition = machine.advance(state, with: event)
            state = transition.state
            return transition
        }

        func ingest(_ observation: InterfaceObservation) -> SettleSession.Outcome? {
            let recorded = observations.record(observation)
            let transition = send(
                .observation(
                    recorded.sample,
                    elapsedMs: deadline.elapsedMilliseconds(at: clock())
                )
            )
            terminalObservationOutcome = SettleSession.outcome(
                for: transition,
                observations: observations
            )
            return terminalObservationOutcome
        }

        if let initial = parseProvider() {
            if let outcome = ingest(initial) {
                return outcome
            }
        }

        while deadline.hasTimeRemaining(at: clock()) {
            do {
                try await observationYield()
            } catch is CancellationError {
                let transition = send(
                    .yieldFailed(.cancellation, elapsedMs: deadline.elapsedMilliseconds(at: clock()))
                )
                return SettleSession.outcome(for: transition, observations: observations)!
            } catch {
                let transition = send(
                    .yieldFailed(.error, elapsedMs: deadline.elapsedMilliseconds(at: clock()))
                )
                return SettleSession.outcome(for: transition, observations: observations)!
            }

            let eventCount = state.events.count
            let tripwireTransition = send(.tripwireSignal(tripwireSignalProvider()))
            if let outcome = SettleSession.outcome(for: tripwireTransition, observations: observations) {
                return outcome
            }
            if state.events.count > eventCount {
                observations.resetCurrentGeneration()
                continue
            }

            guard let parse = parseProvider() else { continue }
            if let outcome = ingest(parse) {
                return outcome
            }
        }

        let transition = send(.timeout(elapsedMs: deadline.elapsedMilliseconds(at: clock())))
        return SettleSession.outcome(for: transition, observations: observations)!
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
