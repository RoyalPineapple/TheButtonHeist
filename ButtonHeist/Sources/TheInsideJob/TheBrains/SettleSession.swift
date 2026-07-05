#if canImport(UIKit)
#if DEBUG
import Foundation
import UIKit

import AccessibilitySnapshotParser
import ButtonHeistSupport

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

struct SettleLoopMachine: SimpleStateMachine, Equatable {
    // Rationale: settle state is driven by the main-actor settle loop and stores captured UIKit evidence.
    // swiftlint:disable:next agent_unchecked_sendable_no_comment
    enum State: Equatable, @unchecked Sendable {
        case consecutiveCycles(ConsecutiveCycleState)
        case quietWindow(QuietWindowState)

        init(consecutiveCyclesRequired required: Int, tripwireBaseline: TheTripwire.TripwireSignal) {
            self = .consecutiveCycles(ConsecutiveCycleState(
                required: required,
                progress: SettleLoopProgress(tripwireBaseline: tripwireBaseline)
            ))
        }

        init(quietWindowMilliseconds milliseconds: Int, tripwireBaseline: TheTripwire.TripwireSignal) {
            self = .quietWindow(QuietWindowState(
                milliseconds: milliseconds,
                progress: SettleLoopProgress(tripwireBaseline: tripwireBaseline)
            ))
        }

        var events: [SettleEvent] {
            progress.events
        }

        var currentGenerationLastObservation: SettleRecordedObservation? {
            progress.currentGenerationLastObservation
        }

        var elementsByKey: [TimelineKey: AccessibilityElement] {
            progress.elementsByKey
        }

        var instabilityDescription: String? {
            progress.instabilityDescription
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

    // Rationale: settle events are created and consumed by the main-actor settle loop.
    // swiftlint:disable:next agent_unchecked_sendable_no_comment
    enum Event: Equatable, @unchecked Sendable {
        case observation(SettleRecordedObservation, elapsedMs: Int)
        case tripwireSignal(TheTripwire.TripwireSignal)
        case yieldFailed(SettleLoopYieldFailure, elapsedMs: Int)
        case timeout(elapsedMs: Int)
    }

    // Rationale: settle effects are returned to the main-actor settle loop driver.
    // swiftlint:disable:next agent_unchecked_sendable_no_comment
    enum Effect: Equatable, @unchecked Sendable {
        case continuePolling
        case terminal(Terminal)
    }

    // Rationale: terminal settle outcomes carry captured observations consumed on the main actor.
    // swiftlint:disable:next agent_unchecked_sendable_no_comment
    enum Terminal: Equatable, @unchecked Sendable {
        case settled(SettleRecordedObservation, timeMs: Int)
        case timedOut(timeMs: Int)
        case cancelled(timeMs: Int)
        case yieldFailed(timeMs: Int)
    }

    enum Rejection: Equatable, Sendable {}

    // Rationale: cycle state is private to the main-actor settle loop driver.
    // swiftlint:disable:next agent_unchecked_sendable_no_comment
    struct ConsecutiveCycleState: Equatable, @unchecked Sendable {
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

    // Rationale: quiet-window state is private to the main-actor settle loop driver.
    // swiftlint:disable:next agent_unchecked_sendable_no_comment
    struct QuietWindowState: Equatable, @unchecked Sendable {
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
        _ observation: SettleRecordedObservation,
        elapsedMs: Int,
        state: State
    ) -> SettleLoopTransition {
        switch state {
        case .consecutiveCycles(var cycleState):
            cycleState.progress.captureTimeline(from: observation)
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
                effect: .terminal(.settled(observation, timeMs: elapsedMs))
            )

        case .quietWindow(var quietState):
            quietState.progress.captureTimeline(from: observation)
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
                effect: .terminal(.settled(observation, timeMs: elapsedMs))
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
        .changed(to: state, effects: [effect])
    }
}

// Rationale: progress stores captured parser evidence but never leaves the main-actor settle driver.
// swiftlint:disable:next agent_unchecked_sendable_no_comment
private struct SettleLoopProgress: Equatable, @unchecked Sendable {
    var tripwireBaseline: TheTripwire.TripwireSignal
    var events: [SettleEvent]
    var currentGenerationLastObservation: SettleRecordedObservation?
    var elementsByKey: [TimelineKey: AccessibilityElement]
    var instabilityDescription: String?

    init(tripwireBaseline: TheTripwire.TripwireSignal) {
        self.tripwireBaseline = tripwireBaseline
        self.events = []
        self.currentGenerationLastObservation = nil
        self.elementsByKey = [:]
        self.instabilityDescription = nil
    }

    mutating func captureTimeline(from observation: SettleRecordedObservation) {
        currentGenerationLastObservation = observation
        elementsByKey = observation.elementsByKey
        instabilityDescription = observation.instabilityDescription
    }

    mutating func recordTripwireBaselineReset(
        from previous: TheTripwire.TripwireSignal,
        to signal: TheTripwire.TripwireSignal
    ) {
        events.append(.tripwireSignalChanged(from: previous, to: signal))
        currentGenerationLastObservation = nil
    }
}

typealias SettleLoopTransition = StateChange<
    SettleLoopMachine.State,
    SettleLoopMachine.Effect,
    SettleLoopMachine.Rejection
>

extension StateChange
where State == SettleLoopMachine.State,
      Effect == SettleLoopMachine.Effect,
      Rejection == SettleLoopMachine.Rejection {
    var settleState: SettleLoopMachine.State {
        state
    }

    var settleEffect: SettleLoopMachine.Effect {
        guard let effect = singleEffect else {
            preconditionFailure("SettleLoopMachine must emit exactly one effect per input.")
        }
        return effect
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
/// **Settle signal boundary.** SettleSession is the legacy fixed-cadence AX
/// quiet loop for passive observation. Active heists/actions use
/// `SemanticQuietSettleSession` below, which watches the same AX semantics
/// through the Stash parser at frame cadence. `TheTripwire.waitForAllClear`
/// watches CALayers and is deliberately blind to the AX tree; "no layer
/// motion" and "AX tree stable" disagree on every spinner-driven loading
/// state. `SettleSwipeLoopState` (Navigation.swift) is also AX-tree driven
/// but interleaves parse with frame yields and exposes a `moved` latch — its
/// termination is per-swipe, not per-action.
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
@MainActor struct SettleSession { // swiftlint:disable:this agent_main_actor_value_type

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

    typealias ParseProvider = @MainActor () -> Screen?
    typealias TripwireSignalProvider = @MainActor () -> TheTripwire.TripwireSignal
    typealias Sleeper = @Sendable (UInt64) async throws -> Void

    let parseProvider: ParseProvider
    let tripwireSignalProvider: TripwireSignalProvider
    let sleeper: Sleeper
    let cyclesRequired: Int
    let cycleIntervalMs: Int
    let timeoutMs: Int

    init(
        parseProvider: @escaping ParseProvider,
        tripwireSignalProvider: @escaping TripwireSignalProvider,
        sleeper: @escaping Sleeper = { try await Task.sleep(nanoseconds: $0) },
        cyclesRequired: Int = SettleSession.defaultCyclesRequired,
        cycleIntervalMs: Int = SettleSession.defaultCycleIntervalMs,
        timeoutMs: Int = SettleSession.defaultTimeoutMs
    ) {
        self.parseProvider = parseProvider
        self.tripwireSignalProvider = tripwireSignalProvider
        self.sleeper = sleeper
        self.cyclesRequired = cyclesRequired
        self.cycleIntervalMs = cycleIntervalMs
        self.timeoutMs = timeoutMs
    }

    /// Live wiring against the real stash/tripwire. The default `sleeper`
    /// is `Task.sleep(nanoseconds:)`, which throws `CancellationError`
    /// when the surrounding task is cancelled — that propagates to
    /// `SettleOutcome.cancelled`.
    static func live(
        stash: TheStash,
        tripwire: TheTripwire,
        timeoutMs: Int = SettleSession.defaultTimeoutMs
    ) -> SettleSession {
        SettleSession(
            parseProvider: { stash.semanticObservationForSettle() },
            tripwireSignalProvider: { tripwire.tripwireSignal() },
            timeoutMs: timeoutMs
        )
    }

    /// Result of the loop, exposed so the caller can compute transients.
    struct Outcome {
        let outcome: SettleOutcome
        /// Lightweight signals observed during the loop. These explain why
        /// the settle baseline was reset, but the final `outcome` still owns
        /// whether the AX tree became stable.
        let events: [SettleEvent]
        /// Last parsed screen observed by the settle loop. On `.settled`, this
        /// is the AX tree whose fingerprint completed the stability proof.
        let finalScreen: Screen?
        /// Every `(key, element)` pair observed in any cycle of the loop.
        /// Includes spinner cycles and other intermediate states.
        let elementsByKey: [TimelineKey: AccessibilityElement]
        /// Compact explanation of the most recent semantic instability when
        /// the loop exits without a clean settle.
        let instabilityDescription: String?

        init(
            outcome: SettleOutcome,
            events: [SettleEvent],
            finalScreen: Screen?,
            elementsByKey: [TimelineKey: AccessibilityElement],
            instabilityDescription: String? = nil
        ) {
            precondition(
                !outcome.didSettleCleanly || finalScreen != nil,
                "settled settle outcome requires a final screen"
            )
            self.outcome = outcome
            self.events = events
            self.finalScreen = finalScreen
            self.elementsByKey = elementsByKey
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
        let cycleNs = UInt64(cycleIntervalMs) * 1_000_000
        return await SettleLoopRunner(
            parseProvider: parseProvider,
            tripwireSignalProvider: tripwireSignalProvider,
            observationYield: { try await sleeper(cycleNs) },
            clock: { CFAbsoluteTimeGetCurrent() },
            timeoutMs: timeoutMs,
            initial: SettleLoopMachine.State(
                consecutiveCyclesRequired: cyclesRequired,
                tripwireBaseline: baselineTripwireSignal
            )
        ).run(start: start)
    }

    static func outcome(for transition: SettleLoopTransition) -> Outcome? {
        switch transition.settleEffect {
        case .continuePolling:
            return nil
        case .terminal(let terminal):
            return outcome(for: terminal, state: transition.settleState)
        }
    }

    private static func outcome(
        for terminal: SettleLoopMachine.Terminal,
        state: SettleLoopMachine.State
    ) -> Outcome {
        switch terminal {
        case .settled(let observation, let timeMs):
            return Outcome(
                outcome: .settled(timeMs: timeMs),
                events: state.events,
                finalScreen: observation.screen,
                elementsByKey: state.elementsByKey
            )
        case .timedOut(let timeMs), .yieldFailed(let timeMs):
            return Outcome(
                outcome: .timedOut(timeMs: timeMs),
                events: state.events,
                finalScreen: state.currentGenerationLastObservation?.screen,
                elementsByKey: state.elementsByKey,
                instabilityDescription: state.instabilityDescription
            )
        case .cancelled(let timeMs):
            return Outcome(
                outcome: .cancelled(timeMs: timeMs),
                events: state.events,
                finalScreen: state.currentGenerationLastObservation?.screen,
                elementsByKey: state.elementsByKey,
                instabilityDescription: state.instabilityDescription
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
        let deadline = start + Double(timeoutMs) / 1_000
        var observations = SettleObservationLedger()
        var driver = StateDriver(
            initial: initial,
            machine: SettleLoopMachine()
        )

        if let initial = parseProvider() {
            let transition = driver.send(
                .observation(observations.record(initial), elapsedMs: elapsedMs(since: start)),
            )
            if let outcome = SettleSession.outcome(for: transition) {
                return outcome
            }
        }

        while clock() < deadline {
            do {
                try await observationYield()
            } catch is CancellationError {
                let transition = driver.send(
                    .yieldFailed(.cancellation, elapsedMs: elapsedMs(since: start))
                )
                return SettleSession.outcome(for: transition)!
            } catch {
                let transition = driver.send(
                    .yieldFailed(.error, elapsedMs: elapsedMs(since: start))
                )
                return SettleSession.outcome(for: transition)!
            }

            let eventCount = driver.state.events.count
            let tripwireTransition = driver.send(.tripwireSignal(tripwireSignalProvider()))
            if let outcome = SettleSession.outcome(for: tripwireTransition) {
                return outcome
            }
            if driver.state.events.count > eventCount {
                continue
            }

            guard let parse = parseProvider() else { continue }
            let observationTransition = driver.send(
                .observation(observations.record(parse), elapsedMs: elapsedMs(since: start))
            )
            if let outcome = SettleSession.outcome(for: observationTransition) {
                return outcome
            }
        }

        let transition = driver.send(.timeout(elapsedMs: elapsedMs(since: start)))
        return SettleSession.outcome(for: transition)!
    }

    @MainActor
    private func elapsedMs(since start: CFAbsoluteTime) -> Int {
        max(0, Int((clock() - start) * 1_000))
    }
}

/// Accessibility-tree settle loop driven by the semantic observation stream.
///
/// This uses the same parser/Stash path as normal observations, but samples at
/// the caller-provided frame cadence and declares settle once the semantic
/// fingerprint has remained unchanged for a quiet wall-clock window.
@MainActor struct SemanticQuietSettleSession { // swiftlint:disable:this agent_main_actor_value_type
    static let defaultQuietWindowMs: Int = 60

    typealias ParseProvider = @MainActor () -> Screen?
    typealias TripwireSignalProvider = @MainActor () -> TheTripwire.TripwireSignal
    typealias ObservationYield = @MainActor () async throws -> Void
    typealias Clock = @MainActor () -> CFAbsoluteTime

    let parseProvider: ParseProvider
    let tripwireSignalProvider: TripwireSignalProvider
    let observationYield: ObservationYield
    let clock: Clock
    let quietWindowMs: Int
    let timeoutMs: Int

    init(
        parseProvider: @escaping ParseProvider,
        tripwireSignalProvider: @escaping TripwireSignalProvider,
        observationYield: @escaping ObservationYield,
        clock: @escaping Clock = { CFAbsoluteTimeGetCurrent() },
        quietWindowMs: Int = SemanticQuietSettleSession.defaultQuietWindowMs,
        timeoutMs: Int = SettleSession.defaultTimeoutMs
    ) {
        self.parseProvider = parseProvider
        self.tripwireSignalProvider = tripwireSignalProvider
        self.observationYield = observationYield
        self.clock = clock
        self.quietWindowMs = quietWindowMs
        self.timeoutMs = timeoutMs
    }

    static func live(
        stash: TheStash,
        tripwire: TheTripwire,
        quietWindowMs: Int = SemanticQuietSettleSession.defaultQuietWindowMs,
        timeoutMs: Int = SettleSession.defaultTimeoutMs
    ) -> SemanticQuietSettleSession {
        SemanticQuietSettleSession(
            parseProvider: { stash.semanticObservationForSettle() },
            tripwireSignalProvider: { tripwire.tripwireSignal() },
            observationYield: { await tripwire.yieldRealFrames(1) },
            quietWindowMs: quietWindowMs,
            timeoutMs: timeoutMs
        )
    }

    func run(
        start: CFAbsoluteTime,
        baselineTripwireSignal: TheTripwire.TripwireSignal
    ) async -> SettleSession.Outcome {
        await SettleLoopRunner(
            parseProvider: parseProvider,
            tripwireSignalProvider: tripwireSignalProvider,
            observationYield: observationYield,
            clock: clock,
            timeoutMs: timeoutMs,
            initial: SettleLoopMachine.State(
                quietWindowMilliseconds: quietWindowMs,
                tripwireBaseline: baselineTripwireSignal
            )
        ).run(start: start)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
