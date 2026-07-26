import Foundation
import ThePlans

/// The ordered ticks a run observed.
///
/// This is the durable artifact of a settlement run, and everything downstream
/// is derived from it rather than recomputed beside it:
///
/// - **Predicate state** is `Expectation.folding(log)`. Not stored, not
///   synchronized, not raced — given the same log it always folds to the same
///   answer, so nothing needs to remember where a drain got to.
/// - **Diffs for output** are read off the log. The ticks already say what
///   changed; comparing captures again to rediscover it is the old model.
///
/// A log holds only values, so folding one needs no actor and no main thread.
/// The main actor's whole job is to observe the tree and append; every consumer
/// reads at its own pace, and none of them own anything the others need.
///
/// Ticks only. Node counts, first-responder movement and screen identity are not
/// part of the heist — no predicate reads them and nothing branches on them, so
/// they are metadata a report derives from the log's endpoints rather than state
/// the log carries. They are also end-state answers: every consumer of the old
/// per-edge digest collapsed it to first, last, or any, so computing one per edge
/// was work thrown away.
struct TickLog: Sendable, Equatable {
    private(set) var ticks: [Tick]

    init(_ ticks: [Tick] = []) {
        self.ticks = ticks
    }

    mutating func append(_ tick: Tick) {
        ticks.append(tick)
    }

    mutating func append(contentsOf newTicks: some Sequence<Tick>) {
        ticks.append(contentsOf: newTicks)
    }

    /// Each adjacent pair of ticks, in order.
    ///
    /// Comparing consecutive ticks is the whole of deriving what changed, so it
    /// is one primitive rather than a walk rewritten per consumer. A log of one
    /// tick has no pairs and nothing changed — which is the same statement.
    var steps: [TickStep] {
        zip(ticks, ticks.dropFirst()).map(TickStep.init)
    }

    /// The three ticks a screen replacement is, in causal order.
    ///
    /// Kept here rather than at the emitters so the order is written once.
    ///
    /// The old screen empties, the new one is named, its graph arrives. Ordered
    /// rather than simultaneous, because a two-legged step will not read its
    /// after leg until the before leg drained: the empty tree answers every
    /// `missing` half, and only then does the arriving graph answer the
    /// `exists` halves.
    static func replacement(
        emptiedAt timestamp: Date,
        screen: ScreenFacts,
        arriving interface: Interface
    ) -> [Tick] {
        [
            .elementsChanged(Interface(timestamp: timestamp, tree: [])),
            .screenChanged(screen),
            .elementsChanged(interface),
        ]
    }
}

/// Two adjacent ticks, which is what "what changed" is a question about.
///
/// A single tick is a reading; a change needs two. Every derivation that used to
/// re-classify a capture pair asks this instead, and the answers come from the
/// ticks themselves rather than from comparing the trees again:
///
/// - `crossesScreenBoundary` is the tick *kind*, not a computation. Settlement
///   already decided a replacement happened, and said so by emitting a
///   `screenChanged` tick; nothing needs to rediscover it.
/// - `interfaces` is the pair of trees when both sides are element ticks, which
///   is the only case an element diff is meaningful over.
struct TickStep: Sendable, Equatable {
    let before: Tick
    let after: Tick

    init(_ before: Tick, _ after: Tick) {
        self.before = before
        self.after = after
    }

    /// Whether the screen identity moved across this step.
    ///
    /// True on the step that lands on the boundary marker, so the marker is
    /// attributed to the step that crossed it rather than the one after.
    var crossesScreenBoundary: Bool {
        after.kind == .screenChanged
    }

    /// The trees this step compares, when it compares trees at all.
    ///
    /// A step touching the screen or announcement lanes has no element question
    /// in it, so there is nothing to diff and this is nil rather than an empty
    /// pair — absence of a comparison, not a comparison that found nothing.
    var interfaces: (before: Interface, after: Interface)? {
        guard case .elementsChanged(let before) = before,
              case .elementsChanged(let after) = after
        else { return nil }
        return (before, after)
    }

    /// What entered, left, and changed across this step.
    ///
    /// The one comparison a step supports, and the only place a tree is compared
    /// to another tree. Steps that name no element question have no edits, which
    /// is why this is empty rather than absent for them: the answer to "what
    /// elements changed here" is "none", and callers fold that in without a
    /// special case.
    var elementEdits: ElementEdits {
        guard let interfaces else { return ElementEdits() }
        return AccessibilityTraceElementDiff.projectElementEdits(
            beforeRecords: interfaces.before.projectedElementRecords.map(ElementDiffRecord.init),
            afterRecords: interfaces.after.projectedElementRecords.map(ElementDiffRecord.init)
        )
    }

    /// Whether the element set changed across this step, ignoring pairing.
    ///
    /// A move suppressed by pairing still changed the set, which is the question
    /// the report asks when the paired diff comes back empty.
    var elementSetChanged: Bool {
        guard let interfaces else { return false }
        return AccessibilityTraceElementDiff.pairingKeyMultisetDiffers(
            beforeRecords: interfaces.before.projectedElementRecords.map(ElementDiffRecord.init),
            afterRecords: interfaces.after.projectedElementRecords.map(ElementDiffRecord.init)
        )
    }
}
