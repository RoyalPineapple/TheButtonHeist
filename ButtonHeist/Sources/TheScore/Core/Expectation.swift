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
    private var pending: [PendingPredicate]

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
        pending = authored.flatMap(\.pendingPredicates)
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
        pending.map(\.description) + (isStill ? [] : [Self.gate.description])
    }

    /// How many predicates are still outstanding, settlement included.
    package var outstandingCount: Int { outstanding.count }

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

    /// A tick walks the list from the front and stops at the first no, then
    /// meets the gate at the end.
    ///
    /// A predicate that does not read this kind of tick is never asked — an
    /// unspoken announcement is not a refusal, so the walk carries on past it
    /// and the graph predicate behind it still gets its turn. Everything that
    /// *is* asked answers plainly: yes takes it off the list, no ends the walk
    /// and leaves the rest for a later tick.
    ///
    /// One tick can therefore satisfy several consecutive predicates, which is
    /// what keeps the verdict independent of how finely the tripwire sampled.
    /// "Satisfied" is not a flag; it means gone from the list.
    private mutating func evaluate(_ tick: Tick) {
        pending = Self.draining(pending, tick)
        isStill = Self.gate.admits(tick)
    }

    /// The list with this tick's answers removed from the front.
    ///
    /// Three cases and no state: a predicate outside the tick's lane has no
    /// opinion and passes through, one that answers is dropped, and the first
    /// that refuses ends the walk with everything from it onward intact.
    private static func draining(
        _ pending: [PendingPredicate],
        _ tick: Tick
    ) -> [PendingPredicate] {
        guard let next = pending.first else { return [] }
        let rest = { draining(Array(pending.dropFirst()), tick) }
        guard next.reads(tick) else { return [next] + rest() }
        guard next.matches(tick) else { return pending }
        return rest()
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
        case (.noChange, .noChange):
            return true
        default:
            preconditionFailure("\(tick.kind) asked of a predicate that does not read it")
        }
    }
}

extension ResolvedAccessibilityPredicate {
    /// This predicate as the things an expectation waits for.
    ///
    /// Everything but `changed` is itself, once. A delta composes into the
    /// presence predicates that make it a change, so an assertion list expands
    /// to twice its length.
    var pendingPredicates: [PendingPredicate] {
        switch self {
        case .exists, .missing:
            return [.graph(self)]
        case .announcement(let predicate):
            return [.announcement(predicate)]
        case .changed(.elements(let assertions)):
            return assertions.flatMap(\.composed).map(PendingPredicate.graph)
        case .changed(.screen(let predicate)):
            return [.screenChange(predicate)]
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
