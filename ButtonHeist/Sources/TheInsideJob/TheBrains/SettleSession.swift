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
enum SettleOutcome: Equatable, Sendable {

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
    /// separately in `SettleSession.Result.events`; it is not itself
    /// stability criterion.
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

/// The settle loop has one reducer and one runner. This policy only selects
/// the stability criterion and sampling cadence used by that runner.
enum SettlePolicy: Equatable, Sendable {
    case consecutiveCycles(required: Int)
    case quietWindow(milliseconds: Int)
}

struct SettleObservationSample: Equatable, Sendable {
    let fingerprint: Int
}

private enum SettleLoopStability: Equatable, Sendable {
    case consecutiveCycles(required: Int, completed: Int)
    case quietWindow(milliseconds: Int, startedAtMs: Int?)

    init(policy: SettlePolicy) {
        switch policy {
        case .consecutiveCycles(let required):
            self = .consecutiveCycles(required: required, completed: 0)
        case .quietWindow(let milliseconds):
            self = .quietWindow(milliseconds: milliseconds, startedAtMs: nil)
        }
    }

    mutating func observe(repeatedFingerprint: Bool, elapsedMs: Int) -> Bool {
        switch self {
        case .consecutiveCycles(let required, let completed):
            let completed = repeatedFingerprint ? completed + 1 : 0
            self = .consecutiveCycles(required: required, completed: completed)
            return completed >= required

        case .quietWindow(let milliseconds, var startedAtMs):
            if !repeatedFingerprint {
                startedAtMs = elapsedMs
            }
            self = .quietWindow(milliseconds: milliseconds, startedAtMs: startedAtMs)
            return startedAtMs.map { elapsedMs - $0 >= milliseconds } ?? false
        }
    }

    mutating func reset() {
        switch self {
        case .consecutiveCycles(let required, _):
            self = .consecutiveCycles(required: required, completed: 0)
        case .quietWindow(let milliseconds, _):
            self = .quietWindow(milliseconds: milliseconds, startedAtMs: nil)
        }
    }
}

struct SettleLoopMachine: Equatable {
    struct State: Equatable, Sendable {
        fileprivate var tripwireBaseline: TheTripwire.TripwireSignal
        private(set) var events: [SettleEvent]
        private var stability: SettleLoopStability
        private var previousFingerprint: Int?

        init(policy: SettlePolicy, tripwireBaseline: TheTripwire.TripwireSignal) {
            self.tripwireBaseline = tripwireBaseline
            self.events = []
            self.stability = SettleLoopStability(policy: policy)
            self.previousFingerprint = nil
        }

        fileprivate mutating func observe(
            _ observation: SettleObservationSample,
            elapsedMs: Int
        ) -> Bool {
            let repeatedFingerprint = previousFingerprint == observation.fingerprint
            previousFingerprint = observation.fingerprint
            return stability.observe(
                repeatedFingerprint: repeatedFingerprint,
                elapsedMs: elapsedMs
            )
        }

        fileprivate mutating func observe(_ signal: TheTripwire.TripwireSignal) {
            let previous = tripwireBaseline
            guard signal != previous else { return }

            tripwireBaseline = signal
            guard signal.requiresSettleBaselineReset(from: previous) else { return }

            events.append(.tripwireSignalChanged(from: previous, to: signal))
            resetStability()
        }

        private mutating func resetStability() {
            previousFingerprint = nil
            stability.reset()
        }
    }

    enum Event: Equatable, Sendable {
        case observation(SettleObservationSample, elapsedMs: Int)
        case tripwireSignal(TheTripwire.TripwireSignal)
    }

    enum Decision: Equatable, Sendable {
        case continuePolling
        case terminal(SettleOutcome)
    }

    func reduce(_ state: State, event: Event) -> SettleLoopTransition {
        var state = state
        let decision: Decision
        switch event {
        case .observation(let observation, let elapsedMs):
            decision = state.observe(observation, elapsedMs: elapsedMs)
                ? .terminal(.settled(timeMs: elapsedMs))
                : .continuePolling
        case .tripwireSignal(let signal):
            state.observe(signal)
            decision = .continuePolling
        }
        return SettleLoopTransition(state: state, decision: decision)
    }
}

struct SettleLoopTransition: Equatable, Sendable {
    let state: SettleLoopMachine.State
    let decision: SettleLoopMachine.Decision
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
/// state. Viewport movement uses this same reducer with a two-cycle policy.
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

    static let minimumStableDurationSeconds = Double(
        defaultCyclesRequired * defaultCycleIntervalMs
    ) / 1_000

    /// Hard ceiling on how long the settle loop will wait for the AX tree
    /// to quiesce before giving up with `.timedOut`. 5 s is the longest
    /// any well-behaved iOS transition (push, modal, alert, tab switch)
    /// takes to settle in practice; anything longer is almost always a
    /// non-terminating animation (spinner not flagged `updatesFrequently`,
    /// a Lottie loop, a video) and the caller is better off accepting the
    /// last-seen snapshot than blocking the action pipeline further.
    static let defaultTimeoutMs: Int = 5_000

    /// Programmatic viewport movement normally proves itself after two
    /// run-loop turns. The shared semantic-observation budget also covers
    /// delayed SwiftUI accessibility updates without slowing the normal path.
    static let viewportTransitionTimeoutMs = Int(SemanticObservationTiming.defaultTimeout * 1_000)
    static let viewportTransitionMinimumBudgetMs = 32

    typealias ParseProvider = @MainActor () -> InterfaceObservation?
    typealias TripwireSignalProvider = @MainActor () -> TheTripwire.TripwireSignal
    typealias Sleeper = @Sendable (UInt64) async -> Void
    typealias ObservationYield = @MainActor () async -> Void
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
        sleeper: @escaping Sleeper = { _ = await Task.cancellableSleep(nanoseconds: $0) },
        cyclesRequired: Int = SettleSession.defaultCyclesRequired,
        cycleIntervalMs: Int = SettleSession.defaultCycleIntervalMs,
        timeoutMs: Int = SettleSession.defaultTimeoutMs
    ) {
        self.init(
            parseProvider: parseProvider,
            tripwireSignalProvider: tripwireSignalProvider,
            observationYield: {
                await sleeper(UInt64(cycleIntervalMs) * 1_000_000)
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
    /// stability criterion while this type continues to own the entire loop.
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
            { _ = await Task.cancellableSleep(
                nanoseconds: UInt64(SettleSession.defaultCycleIntervalMs) * 1_000_000
            ) }
        case .quietWindow:
            { await tripwire.yieldRealFrames(1) }
        }
        return SettleSession(
            parseProvider: { vault.refreshLiveCapture() },
            tripwireSignalProvider: { tripwire.tripwireSignal() },
            observationYield: observationYield,
            policy: policy,
            clock: { CFAbsoluteTimeGetCurrent() },
            timeoutMs: timeoutMs
        )
    }

    /// Minimal stability criterion for a programmatic viewport transition. UIKit receives
    /// two run-loop turns to lay out the new viewport, and the parser must
    /// return the same semantic fingerprint across both repeat captures.
    static func viewportTransition(
        vault: TheVault,
        tripwire: TheTripwire,
        timeoutMs: Int
    ) -> SettleSession {
        SettleSession(
            parseProvider: { vault.refreshLiveCapture() },
            tripwireSignalProvider: { tripwire.tripwireSignal() },
            observationYield: { await tripwire.yieldRealFrames(1) },
            policy: .consecutiveCycles(required: 2),
            clock: { CFAbsoluteTimeGetCurrent() },
            timeoutMs: timeoutMs
        )
    }

    /// Result of the loop, exposed so the caller can compute transients.
    struct Result: Sendable {
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
    func run(start: CFAbsoluteTime, baselineTripwireSignal: TheTripwire.TripwireSignal) async -> Result {
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

    static func result(
        outcome: SettleOutcome,
        state: SettleLoopMachine.State,
        observations: SettleObservationLedger
    ) -> Result {
        Result(
            outcome: outcome,
            events: state.events,
            finalObservation: observations.currentGenerationLastObservation.map {
                SettleSessionFinalObservation(observation: $0.observation)
            },
            elementsByKey: observations.elementsByKey,
            tripwireSignal: state.tripwireBaseline,
            instabilityDescription: outcome.didSettleCleanly
                ? nil
                : observations.latestChangeDescription
        )
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
    let parseProvider: SettleSession.ParseProvider
    let tripwireSignalProvider: SettleSession.TripwireSignalProvider
    let observationYield: SettleSession.ObservationYield
    let clock: SettleSession.Clock
    let timeoutMs: Int
    let initial: SettleLoopMachine.State

    @MainActor
    func run(start: CFAbsoluteTime) async -> SettleSession.Result {
        let deadline = SemanticObservationDeadline(start: start, timeoutMs: timeoutMs)
        var observations = SettleObservationLedger()
        let machine = SettleLoopMachine()
        var state = initial

        func reduce(_ event: SettleLoopMachine.Event) -> SettleLoopTransition {
            let transition = machine.reduce(state, event: event)
            state = transition.state
            return transition
        }

        func ingest(_ observation: InterfaceObservation) -> SettleSession.Result? {
            let recorded = observations.record(observation)
            let transition = reduce(
                .observation(
                    recorded.sample,
                    elapsedMs: deadline.elapsedMilliseconds(at: clock())
                )
            )
            guard case .terminal(let outcome) = transition.decision else { return nil }
            return SettleSession.result(
                outcome: outcome,
                state: transition.state,
                observations: observations
            )
        }

        func result(_ outcome: SettleOutcome) -> SettleSession.Result {
            return SettleSession.result(
                outcome: outcome,
                state: state,
                observations: observations
            )
        }

        if let initial = parseProvider() {
            if let outcome = ingest(initial) {
                return outcome
            }
        }

        while deadline.hasTimeRemaining(at: clock()) {
            await observationYield()
            if Task.isCancelled {
                return result(
                    .cancelled(timeMs: deadline.elapsedMilliseconds(at: clock()))
                )
            }

            let eventCount = state.events.count
            _ = reduce(.tripwireSignal(tripwireSignalProvider()))
            if state.events.count > eventCount {
                observations.resetCurrentGeneration()
                continue
            }

            guard let parse = parseProvider() else { continue }
            if let outcome = ingest(parse) {
                return outcome
            }
        }

        return result(.timedOut(timeMs: deadline.elapsedMilliseconds(at: clock())))
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
