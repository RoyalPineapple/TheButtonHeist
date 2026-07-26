import Foundation
import ThePlans

/// What the caller asked for, and what is still outstanding.
///
/// An expectation is a list of predicates in authored order. Ticks are handed to
/// it as they arrive, each one satisfying as many predicates off the front as it
/// can answer. When the list is empty the expectation is met; if the timeout
/// fires first, whatever is left is the failure. Nothing here decides that —
/// waiting and failing are the same state, and only the clock tells them apart.
package struct Expectation: Equatable {
    /// One step per authored assertion, each draining independently.
    private var pending: [PendingStep]

    /// The gate at the end of the pipe.
    ///
    /// A predicate like any other — same type, same lane, answered by the same
    /// verb — but held here rather than in `pending` because it is never
    /// authored, never constructed by a caller, and never drains. Every tick
    /// walks the list and then reaches it, unconditionally.
    ///
    /// Not draining is the point. Everything in the list is consumed by the
    /// tick that satisfies it, which is what makes a match a change. Stillness
    /// is the opposite: a run that went quiet and then carried on is not
    /// settled, so the gate answers afresh for every tick.
    private static let gate = PendingPredicate.noChange

    /// What the gate said about the most recent tick.
    private var isStill = false

    /// An expectation with nothing asked of it still waits for one thing.
    ///
    /// Authored predicates go in the list; settlement is always behind them. So
    /// an action with no expectation ends on the first stillness, which is the
    /// whole of what settling used to mean.
    package init(_ authored: [ResolvedAccessibilityPredicate] = []) {
        pending = authored.flatMap(\.pendingSteps)
    }

    /// True once everything asked for has happened *and* the tree went still.
    ///
    /// Both halves, and in that order: stillness while something is outstanding
    /// is a stall, not an ending.
    package var isMet: Bool { pending.isEmpty && isStill }

    /// What is still being waited on, in authored order, described for a human.
    ///
    /// This is not a list of failures until the timeout makes it one: waiting
    /// and failing are the same state, and only the clock tells them apart. The
    /// first entry is where the run got stuck; everything behind it was never
    /// asked.
    package var outstanding: [String] {
        pending.flatMap(\.descriptions) + (isStill ? [] : [Self.gate.description])
    }

    // MARK: - Ticks

    /// The tree, as it is now.
    package mutating func snapshot(_ interface: Interface) {
        evaluate(.snapshot(interface))
    }

    /// The old screen stopped answering: an empty tree, nothing more.
    ///
    /// Not a special kind of tick. It is a snapshot whose tree is empty, and
    /// the ordinary snapshot math already says the right thing about one —
    /// nothing is found, so every `missing` half drains and every `exists`
    /// refuses. That is the removals, and nobody enumerated them.
    ///
    /// Emitted the moment a screen change is detected, before exploration
    /// starts, because it needs no knowledge of where the run is going.
    package mutating func vacated(at timestamp: Date) {
        evaluate(.snapshot(Interface(timestamp: timestamp, tree: [])))
    }

    /// What the new screen is, classified from the visible hierarchy.
    ///
    /// This lands before exploration, not after: naming the screen needs only
    /// what is on it, and a caller waiting on `changed(.screen("Settings"))`
    /// should not also wait for every scroll container to be walked. Carries
    /// no tree, which is what keeps it a boundary rather than an observation.
    package mutating func screenChange(_ facts: ScreenFacts) {
        evaluate(.screenChange(facts))
    }

    /// Something was spoken.
    package mutating func announcement(_ text: String) {
        evaluate(.announcement(text))
    }

    /// Two consecutive snapshots came back equal: the tree stopped moving.
    ///
    /// Nothing in the list reads one of these, so it flows all the way through
    /// to settlement. A value that never stops climbing never produces one, so
    /// the run never ends and the timeout kills it, which is right: the app
    /// never stopped either.
    package mutating func noChange() {
        evaluate(.noChange)
    }

    // MARK: - Evaluating a tick

    /// Every step is offered the tick, then the gate answers last.
    ///
    /// One tick satisfies as much as it can — every step this tick answers
    /// advances, because a tick is one moment and everything true of that moment
    /// is true at once. "Satisfied" is not a flag; it means gone from the list.
    private mutating func evaluate(_ tick: Tick) {
        pending = pending.compactMap { $0.draining(tick) }
        isStill = Self.gate.admits(tick)
    }
}

/// One authored assertion, and how much of it is left.
///
/// A delta is not a primitive: `appeared(X)` is `missing(X)` then `exists(X)`,
/// and it means *appeared* only because the second half cannot be asked until
/// the first has drained. So a step is a short ordered run of presence
/// predicates, and it is a type rather than a nested array because the pairing
/// is the meaning — when only the first half has drained, the second has to keep
/// its own place, or a leftover `exists(X)` is indistinguishable from an
/// unrelated predicate that happened to land at that index.
///
/// Between steps there is nothing to order. Every element question is `exists`
/// or `missing` against one tree, so a snapshot answers as many steps as it can
/// at once: two assertions written side by side describe one frame, not a
/// sequence. `[appeared(Processing), disappeared(Submit)]` is one transition
/// seen twice.
///
/// The one thing a drained half leaves behind is a hash of what it matched, and
/// the next half must match something that hashes differently. That is the whole
/// of what makes a pair a *change* — not a baseline, not a diff record, not an
/// ordering rule the fold has to enforce.
///
/// One rule covers every pair. `appeared(X)` reads a tree without X and then one
/// with it, two readings, two hashes. `updated(X, v1, v2)` reads a tree where X
/// is v1 and then one where it is v2 — and if both halves are offered the same
/// tree, they are offered the same reading, so the second refuses. A change needs
/// two moments, and the hash is what says whether it got them.
struct PendingStep: Equatable {
    private let remaining: [PendingPredicate]
    private let matched: Int?

    init(_ remaining: [PendingPredicate], matched: Int? = nil) {
        self.remaining = remaining
        self.matched = matched
    }

    var descriptions: [String] {
        remaining.map(\.description)
    }

    /// This step with the tick's answers removed, or nil once nothing is left.
    ///
    /// A predicate outside the tick's lane has no opinion and passes through,
    /// one that answers is dropped, and the first that refuses ends the walk
    /// with everything from it onward intact.
    fileprivate func draining(_ tick: Tick) -> Self? {
        var carried = matched
        let next = Self.draining(remaining, tick, &carried)
        return next.isEmpty ? nil : Self(next, matched: carried)
    }

    private static func draining(
        _ remaining: [PendingPredicate],
        _ tick: Tick,
        _ matched: inout Int?
    ) -> [PendingPredicate] {
        guard let next = remaining.first else { return [] }
        guard next.reads(tick) else {
            var carried = matched
            let rest = draining(Array(remaining.dropFirst()), tick, &carried)
            matched = carried
            return [next] + rest
        }
        guard let hash = next.matching(tick), hash != matched else { return remaining }
        matched = hash
        return draining(Array(remaining.dropFirst()), tick, &matched)
    }
}

/// One piece of evidence, and the lane it answers.
///
/// The case is the lane: a predicate is answered by exactly one of these, and
/// the data that answers it is the case's payload. Internal because nobody
/// outside needs to name one — callers hand `Expectation` an interface, a
/// spoken string, or stillness, and it makes the tick itself.
///
/// A screen change is its own case because the system says a screen changed. We
/// never infer one by diffing two graphs across a boundary.
private enum Tick {
    case snapshot(Interface)
    case noChange
    case screenChange(ScreenFacts)
    case announcement(String)

    /// Which of the four this is, without the evidence it carries. A pending
    /// predicate reads exactly one kind, so this is the whole of the lane check
    /// — and none of them reads `noChange`, which is why one flows all the way
    /// through the list to settlement.
    enum Kind: Equatable {
        case snapshot
        case noChange
        case screenChange
        case announcement
    }

    var kind: Kind {
        switch self {
        case .snapshot: return .snapshot
        case .noChange: return .noChange
        case .screenChange: return .screenChange
        case .announcement: return .announcement
        }
    }

    /// Which reading this is, as one comparable value.
    ///
    /// A step keeps the reading its last half drained on and refuses a half that
    /// would drain on the same one, so this has to say whether two ticks are the
    /// same reading of the interface. For a snapshot that is the elements it
    /// projects: the semantic content, not the instant it was captured, because
    /// two captures of an unchanged screen are one reading however far apart they
    /// are. The others carry what they said, which is all there is of them.
    var reading: Int {
        var hasher = Hasher()
        switch self {
        case .snapshot(let interface):
            hasher.combine(interface.projectedElements)
        case .screenChange(let facts):
            hasher.combine(facts.idAfter)
        case .announcement(let spoken):
            hasher.combine(spoken)
        case .noChange:
            hasher.combine("noChange")
        }
        return hasher.finalize()
    }
}

/// One thing an expectation is still waiting for.
///
/// Almost all of these are an authored predicate, unchanged — a delta is not a
/// fourth kind of thing, it is the presence predicates it composes from, in
/// order. That is why nothing holds a baseline: a match is a change because the
/// predicate before it already drained.
///
/// The case is the *lane* — which of the four ticks may answer this. Every
/// element question is a graph predicate answered by a snapshot, whichever
/// screen it belongs to: a screen boundary is a sibling in the list, not a
/// different way of asking about elements.
struct PendingPredicate: Equatable {
    fileprivate enum Kind: Equatable {
        case graph(ResolvedAccessibilityPredicate)
        case screenChange(ResolvedScreenPredicate)
        case announcement(ResolvedAnnouncementPredicate)
        case anyChange
        case noChange
    }

    fileprivate let kind: Kind

    /// Answer this against the tree as it is.
    static func graph(_ predicate: ResolvedAccessibilityPredicate) -> Self {
        Self(kind: .graph(predicate))
    }

    /// Answer this with the facts the screen boundary carried. This asks
    /// nothing of any tree: elements are always element predicates, answered by
    /// the snapshots on either side.
    static func screenChange(_ predicate: ResolvedScreenPredicate) -> Self {
        Self(kind: .screenChange(predicate))
    }

    /// Answer this with what was spoken.
    static func announcement(_ predicate: ResolvedAnnouncementPredicate) -> Self {
        Self(kind: .announcement(predicate))
    }

    /// Any change at all, with no element named. Answered by any snapshot,
    /// because a snapshot tick is a change: the producer decided that before it
    /// ever became a tick.
    static var anyChange: Self {
        Self(kind: .anyChange)
    }

    /// The settlement gate. Never authored and never in the list: an
    /// expectation holds exactly one of these, at the end of the pipe.
    fileprivate static var noChange: Self {
        Self(kind: .noChange)
    }

    var description: String {
        switch kind {
        case .graph(let predicate): return predicate.description
        case .screenChange(let predicate): return predicate.description
        case .announcement(let predicate): return predicate.description
        case .anyChange: return "any element to change"
        case .noChange: return "the tree to stop changing"
        }
    }

    /// The one kind of tick this predicate reads.
    ///
    /// Each reads exactly one, which is what lets the walk decide whether to
    /// ask before asking — a predicate is never handed evidence it has no
    /// opinion about. Stillness is read by nothing here: it belongs to
    /// settlement, which the evaluation mechanics own rather than the list.
    private var lane: Tick.Kind {
        switch kind {
        case .graph: return .snapshot
        case .screenChange: return .screenChange
        case .announcement: return .announcement
        case .anyChange: return .snapshot
        case .noChange: return .noChange
        }
    }

    /// Whether this predicate has an opinion about this kind of evidence.
    fileprivate func reads(_ tick: Tick) -> Bool {
        lane == tick.kind
    }

    /// Whether this holds for `tick`, including ticks it does not read.
    ///
    /// The gate is asked about every tick, not only the ones in its lane, so it
    /// needs an answer for all four: anything that is not stillness is a no.
    fileprivate func admits(_ tick: Tick) -> Bool {
        reads(tick) && matches(tick)
    }

    /// What `tick` matched, hashed, or nil if it did not match.
    ///
    /// A step compares this against the hash its previous half left behind, and
    /// what it hashes is the *reading* the half was satisfied by. Two halves
    /// offered one tick are looking at one tree, so they read the same hash and
    /// the second refuses: one moment cannot be both sides of a change.
    fileprivate func matching(_ tick: Tick) -> Int? {
        guard matches(tick) else { return nil }
        return tick.reading
    }

    /// Whether `tick` satisfies this predicate.
    ///
    /// Only ever called when `reads(tick)`, so every case that could disagree
    /// has already been filtered out and the answer is a plain yes or no.
    fileprivate func matches(_ tick: Tick) -> Bool {
        switch (tick, kind) {
        case (.snapshot(let interface), .graph(let predicate)):
            return predicate.matches(interface)
        case (.screenChange(let facts), .screenChange(let predicate)):
            return predicate.matches(facts)
        case (.announcement(let spoken), .announcement(let predicate)):
            return predicate.matches(spoken)
        case (.snapshot, .anyChange):
            return true
        case (.noChange, .noChange):
            return true
        default:
            preconditionFailure("\(tick.kind) asked of a predicate that does not read it")
        }
    }
}

extension ResolvedAccessibilityPredicate {
    /// This predicate as the steps an expectation waits for.
    ///
    /// Everything but `changed(.elements)` is a step of one. An assertion list
    /// is one step *per assertion*, because a delta's two halves belong together
    /// and must drain in order, while two assertions written side by side were
    /// never a claim about which happens first.
    var pendingSteps: [PendingStep] {
        switch self {
        case .exists, .missing:
            return [PendingStep([.graph(self)])]
        case .announcement(let predicate):
            return [PendingStep([.announcement(predicate)])]
        case .changed(.elements(let assertions)):
            // Asserting nothing is the nullary delta — "elements changed, never
            // mind which". It names no element, so it has nothing to search for
            // and cannot compose into presence predicates; it is answerable
            // anyway, because a snapshot tick *is* a change now that the producer
            // decides change-from-stillness. Without this it would map to no
            // steps at all and a wait on it would return on the first stillness.
            guard !assertions.isEmpty else { return [PendingStep([.anyChange])] }
            return assertions.map { PendingStep($0.composed.map(PendingPredicate.graph)) }
        case .changed(.screen(let predicate)):
            return [PendingStep([.screenChange(predicate)])]
        }
    }

    /// Whether this predicate holds against the tree as it is now.
    ///
    /// Only presence asks the graph anything. Announcements go in their own
    /// lane, and a delta never reaches here — it composed away into the
    /// presence predicates above.
    func matches(_ interface: Interface) -> Bool {
        switch self {
        case .exists(let target): return target.found(in: interface)
        case .missing(let target): return !target.found(in: interface)
        case .announcement, .changed: return false
        }
    }

}
