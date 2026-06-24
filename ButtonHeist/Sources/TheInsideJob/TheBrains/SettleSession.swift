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
enum SettleEvent: Equatable {
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
        let deadline = start + Double(timeoutMs) / 1000

        var observations = SettleObservationLedger()
        var stableCycles = 0
        var tripwireBaseline = baselineTripwireSignal
        var events: [SettleEvent] = []
        var lastScreen: Screen?

        // Seed the baseline fingerprint synchronously so the first
        // post-sleep parse can already count as stable cycle 1. Without
        // this seed, a static screen pays cyclesRequired+1 cycles.
        var previousFingerprint: Int? = {
            guard let initial = parseProvider() else { return nil }
            lastScreen = initial
            return observations.record(initial)
        }()

        while CFAbsoluteTimeGetCurrent() < deadline {
            do {
                try await sleeper(cycleNs)
            } catch is CancellationError {
                return Outcome(
                    outcome: .cancelled(timeMs: Self.elapsedMs(since: start)),
                    events: events,
                    finalScreen: lastScreen,
                    elementsByKey: observations.elementsByKey,
                    instabilityDescription: observations.latestChangeDescription
                )
            } catch {
                return Outcome(
                    outcome: .timedOut(timeMs: Self.elapsedMs(since: start)),
                    events: events,
                    finalScreen: lastScreen,
                    elementsByKey: observations.elementsByKey,
                    instabilityDescription: observations.latestChangeDescription
                )
            }

            let nowTripwireSignal = tripwireSignalProvider()
            if nowTripwireSignal != tripwireBaseline {
                events.append(.tripwireSignalChanged(
                    from: tripwireBaseline,
                    to: nowTripwireSignal
                ))
                tripwireBaseline = nowTripwireSignal
                stableCycles = 0
                guard let parse = parseProvider() else {
                    previousFingerprint = nil
                    continue
                }
                lastScreen = parse
                previousFingerprint = observations.record(parse)
                continue
            }

            guard let parse = parseProvider() else { continue }
            lastScreen = parse

            let fingerprint = observations.record(parse)
            if let previousFingerprint, fingerprint == previousFingerprint {
                stableCycles += 1
                if stableCycles >= cyclesRequired {
                    return Outcome(
                        outcome: .settled(timeMs: Self.elapsedMs(since: start)),
                        events: events,
                        finalScreen: parse,
                        elementsByKey: observations.elementsByKey
                    )
                }
            } else {
                stableCycles = 0
            }
            previousFingerprint = fingerprint
        }

        return Outcome(
            outcome: .timedOut(timeMs: Self.elapsedMs(since: start)),
            events: events,
            finalScreen: lastScreen,
            elementsByKey: observations.elementsByKey,
            instabilityDescription: observations.latestChangeDescription
        )
    }

    private static func elapsedMs(since start: CFAbsoluteTime) -> Int {
        Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
    }

    static func transientElements(
        seenByKey: [TimelineKey: AccessibilityElement],
        baseline: [AccessibilityElement],
        final: [AccessibilityElement]
    ) -> [AccessibilityElement] {
        SettleTimeline.transientElements(seenByKey: seenByKey, baseline: baseline, final: final)
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
        let deadline = start + Double(timeoutMs) / 1_000
        let quietWindowSeconds = Double(quietWindowMs) / 1_000

        var observations = SettleObservationLedger()
        var tripwireBaseline = baselineTripwireSignal
        var events: [SettleEvent] = []
        var lastScreen: Screen?
        var previousFingerprint: Int?
        var quietStartedAt: CFAbsoluteTime?

        func elapsedMs() -> Int {
            max(0, Int((clock() - start) * 1_000))
        }

        func record(_ screen: Screen) -> Bool {
            lastScreen = screen
            let fingerprint = observations.record(screen)
            let now = clock()
            if fingerprint == previousFingerprint {
                let stableSince = quietStartedAt ?? now
                quietStartedAt = stableSince
                return now - stableSince >= quietWindowSeconds
            }
            previousFingerprint = fingerprint
            quietStartedAt = now
            return false
        }

        if let initial = parseProvider(), record(initial) {
            return SettleSession.Outcome(
                outcome: .settled(timeMs: elapsedMs()),
                events: events,
                finalScreen: initial,
                elementsByKey: observations.elementsByKey
            )
        }

        while clock() < deadline {
            do {
                try await observationYield()
            } catch is CancellationError {
                return SettleSession.Outcome(
                    outcome: .cancelled(timeMs: elapsedMs()),
                    events: events,
                    finalScreen: lastScreen,
                    elementsByKey: observations.elementsByKey,
                    instabilityDescription: observations.latestChangeDescription
                )
            } catch {
                return SettleSession.Outcome(
                    outcome: .timedOut(timeMs: elapsedMs()),
                    events: events,
                    finalScreen: lastScreen,
                    elementsByKey: observations.elementsByKey,
                    instabilityDescription: observations.latestChangeDescription
                )
            }

            let nowTripwireSignal = tripwireSignalProvider()
            if nowTripwireSignal != tripwireBaseline {
                events.append(.tripwireSignalChanged(
                    from: tripwireBaseline,
                    to: nowTripwireSignal
                ))
                tripwireBaseline = nowTripwireSignal
                previousFingerprint = nil
                quietStartedAt = nil
            }

            guard let parse = parseProvider() else { continue }
            if record(parse) {
                return SettleSession.Outcome(
                    outcome: .settled(timeMs: elapsedMs()),
                    events: events,
                    finalScreen: parse,
                    elementsByKey: observations.elementsByKey
                )
            }
        }

        return SettleSession.Outcome(
            outcome: .timedOut(timeMs: elapsedMs()),
            events: events,
            finalScreen: lastScreen,
            elementsByKey: observations.elementsByKey,
            instabilityDescription: observations.latestChangeDescription
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
