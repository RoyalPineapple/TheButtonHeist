#if canImport(UIKit)
#if DEBUG
import Foundation
import UIKit

import AccessibilitySnapshotParser
import ButtonHeistSupport

/// Result of running the multi-cycle AX-tree settle loop.
enum SettleOutcome: Equatable, Sendable {

    /// The AX tree stopped changing: two consecutive readings came back equal.
    case settled(timeMs: Int)

    /// The hard timeout elapsed while the tree was still changing.
    case timedOut(timeMs: Int)

    /// The loop's structured-concurrency context was cancelled (e.g. the
    /// session was torn down mid-action). Distinct from `.timedOut` so the
    /// caller can short-circuit the rest of the action pipeline rather than
    /// continue parsing/exploring on a dead session.
    case cancelled(timeMs: Int)

    /// The clock stopped: the tripwire pulse is not running, so no further
    /// observation can arrive. A stopped clock is not a slow app, and the
    /// caller cannot fix it by waiting longer.
    case clockUnavailable(timeMs: Int)

    var timeMs: Int {
        switch self {
        case .settled(let ms), .timedOut(let ms), .cancelled(let ms), .clockUnavailable(let ms):
            return ms
        }
    }

    /// True when the response represents a UI state we believe in:
    /// the loop reached multi-cycle stability.
    var didSettleCleanly: Bool {
        switch self {
        case .settled: return true
        case .timedOut, .cancelled, .clockUnavailable: return false
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
        case .clockUnavailable(let timeMs):
            return "display clock unavailable after \(timeMs)ms"
        }
    }
}

// MARK: - Settle Loop Machine

struct SettleObservationSample: Equatable, Sendable {
    let fingerprint: Int
}

struct SettleLoopMachine: Equatable {
    struct State: Equatable, Sendable {
        fileprivate var tripwireBaseline: TheTripwire.TripwireSignal
        private var previousFingerprint: Int?

        init(tripwireBaseline: TheTripwire.TripwireSignal) {
            self.tripwireBaseline = tripwireBaseline
            self.previousFingerprint = nil
        }

        /// One no-change is the whole settle rule.
        ///
        /// Two consecutive equal fingerprints mean the tree stopped moving, and
        /// there is nothing a third look can add that the second did not
        /// already say. Counting cycles was a way of buying confidence that the
        /// predicates now provide directly: what the caller asked for either
        /// happened or the timeout says it never will.
        fileprivate mutating func observe(_ observation: SettleObservationSample) -> Bool {
            let unchanged = previousFingerprint == observation.fingerprint
            previousFingerprint = observation.fingerprint
            return unchanged
        }

        fileprivate mutating func observe(_ signal: TheTripwire.TripwireSignal) -> Bool {
            let previous = tripwireBaseline
            guard signal != previous else { return false }

            tripwireBaseline = signal
            guard signal.requiresSettleBaselineReset(from: previous) else { return false }

            previousFingerprint = nil
            return true
        }
    }

    enum Event: Equatable, Sendable {
        case observation(SettleObservationSample, elapsedMs: Int)
        case tripwireSignal(TheTripwire.TripwireSignal)
    }

    enum Decision: Equatable, Sendable {
        case continuePolling
        /// The screen was replaced, so the reading the loop was comparing
        /// against belongs to a screen that is gone. It is dropped and the next
        /// observation becomes the first of the new comparison.
        case baselineReset
        case terminal(SettleOutcome)
    }

    func reduce(_ state: State, event: Event) -> SettleLoopTransition {
        var state = state
        let decision: Decision
        switch event {
        case .observation(let observation, let elapsedMs):
            decision = state.observe(observation)
                ? .terminal(.settled(timeMs: elapsedMs))
                : .continuePolling
        case .tripwireSignal(let signal):
            decision = state.observe(signal) ? .baselineReset : .continuePolling
        }
        return SettleLoopTransition(state: state, decision: decision)
    }
}

struct SettleLoopTransition: Equatable, Sendable {
    let state: SettleLoopMachine.State
    let decision: SettleLoopMachine.Decision
}

@MainActor
struct SettleSessionFinalObservation {
    let observation: InterfaceObservation

    var tree: InterfaceTree { observation.tree }
}

// MARK: - SettleSession

/// Accessibility-tree settle loop.
///
/// Samples the parsed AX tree on the shared UI tick and settles on one
/// no-change: two consecutive readings that come back equal. Values on elements
/// carrying `UIAccessibilityTraits.updatesFrequently` are masked so spinners
/// don't block semantic settle; their geometry never is.
///
/// **One clock, one comparison, one event.** The tripwire tick is the only time
/// source and the AX-tree diff is the only evidence. There is no cycle count to
/// tune: counting repetitions was buying confidence that the caller's
/// predicates now supply directly, and a third identical reading never said
/// anything the second had not.
///
/// The loop seeds `previousFingerprint` from a synchronous parse *before* the
/// first tick, so a static screen settles on the first tick rather than
/// spending one to discover what it already knew.
///
/// Dependencies are injected as closures so unit tests can drive the loop
/// against a scripted sequence of parse results without standing up a
/// live UIKit hierarchy.
///
/// `@MainActor` justification: drives a MainActor-bound parse loop and stores
/// `@MainActor`-typed provider closures.
@MainActor struct SettleSession {

    /// Poll interval between AX-tree fingerprint checks. 100 ms is roughly
    /// six display frames at 60 Hz — long enough that a parse + fingerprint
    /// + sleep cycle stays well under one frame of main-actor budget on real
    /// devices, short enough that settle latency is dominated by waiting for
    /// the app rather than by the poll itself. This is the poll cadence
    /// VoiceOver itself uses for similar idle-checks, which is why agents
    /// driving the same AX surface feel "in sync" at this rate.
    static let defaultCycleIntervalMs: Int = 100

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
    typealias ObservationYield = @MainActor (Duration) async -> TheTripwire.TickWaitOutcome
    typealias Clock = @MainActor () -> RuntimeElapsed.Instant

    let parseProvider: ParseProvider
    let tripwireSignalProvider: TripwireSignalProvider
    let observationYield: ObservationYield
    let clock: Clock
    let timeoutMs: Int

    init(
        parseProvider: @escaping ParseProvider,
        tripwireSignalProvider: @escaping TripwireSignalProvider,
        observationYield: @escaping ObservationYield,
        clock: @escaping Clock = { RuntimeElapsed.now },
        timeoutMs: Int = SettleSession.defaultTimeoutMs
    ) {
        self.parseProvider = parseProvider
        self.tripwireSignalProvider = tripwireSignalProvider
        self.observationYield = observationYield
        self.clock = clock
        self.timeoutMs = timeoutMs
    }

    /// Sleep-driven wiring for unit tests that script parse results instead of
    /// standing up a live UIKit hierarchy.
    init(
        parseProvider: @escaping ParseProvider,
        tripwireSignalProvider: @escaping TripwireSignalProvider,
        sleeper: @escaping Sleeper = { _ = await Task.cancellableSleep(nanoseconds: $0) },
        cycleIntervalMs: Int = SettleSession.defaultCycleIntervalMs,
        timeoutMs: Int = SettleSession.defaultTimeoutMs
    ) {
        self.init(
            parseProvider: parseProvider,
            tripwireSignalProvider: tripwireSignalProvider,
            observationYield: { _ in
                await sleeper(UInt64(cycleIntervalMs) * 1_000_000)
                return Task.isCancelled ? .cancelled : .observed
            },
            timeoutMs: timeoutMs
        )
    }

    /// Live wiring against the real vault/tripwire. `demand` only chooses how
    /// hard the loop drives the shared tick; the settle rule is the same
    /// either way.
    static func live(
        vault: TheVault,
        tripwire: TheTripwire,
        timeoutMs: Int = SettleSession.defaultTimeoutMs,
        demand: TheTripwire.TickDemand = .ambient
    ) -> SettleSession {
        SettleSession(
            parseProvider: { vault.refreshLiveCapture() },
            tripwireSignalProvider: { tripwire.tripwireSignal() },
            observationYield: { timeout in
                await tripwire.waitForNextTick(timeout: timeout, demand: demand)
            },
            timeoutMs: timeoutMs
        )
    }

    /// A programmatic viewport transition settles by the same rule as anything
    /// else; it only asks the tick harder, because nothing else is driving it.
    static func viewportTransition(
        vault: TheVault,
        tripwire: TheTripwire,
        timeoutMs: Int
    ) -> SettleSession {
        live(vault: vault, tripwire: tripwire, timeoutMs: timeoutMs, demand: .immediate)
    }

    /// Result of the loop.
    struct Result: Sendable {
        let outcome: SettleOutcome
        /// Exact final semantic observation admitted by the settle loop.
        let finalObservation: SettleSessionFinalObservation?
        /// Full tripwire signal paired with the final observed generation.
        let tripwireSignal: TheTripwire.TripwireSignal
        /// What the last comparison saw. On a clean settle this reads
        /// `unchanged`; otherwise it names the fields that changed.
        let delta: SettleDelta

        init(
            outcome: SettleOutcome,
            finalObservation: SettleSessionFinalObservation?,
            tripwireSignal: TheTripwire.TripwireSignal,
            delta: SettleDelta = .baseline
        ) {
            precondition(
                !outcome.didSettleCleanly || finalObservation != nil,
                "settled settle outcome requires a final observation"
            )
            self.outcome = outcome
            self.finalObservation = finalObservation
            self.tripwireSignal = tripwireSignal
            self.delta = delta
        }
    }

    /// Run the settle loop from the full tripwire signal the run starts with.
    /// A visible window/navigation/key change means the screen was replaced, so
    /// the loop drops the reading it was comparing against and proves the tree
    /// that arrived is stable before returning.
    func run(
        start: RuntimeElapsed.Instant,
        baselineTripwireSignal: TheTripwire.TripwireSignal
    ) async -> Result {
        return await SettleLoopRunner(
            parseProvider: parseProvider,
            tripwireSignalProvider: tripwireSignalProvider,
            observationYield: observationYield,
            clock: clock,
            timeoutMs: timeoutMs,
            initial: SettleLoopMachine.State(tripwireBaseline: baselineTripwireSignal)
        ).run(start: start)
    }

    static func result(
        outcome: SettleOutcome,
        state: SettleLoopMachine.State,
        observations: SettleObservationLedger
    ) -> Result {
        Result(
            outcome: outcome,
            finalObservation: observations.currentGenerationLastObservation.map {
                SettleSessionFinalObservation(observation: $0.observation)
            },
            tripwireSignal: state.tripwireBaseline,
            delta: observations.latestDelta
        )
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
