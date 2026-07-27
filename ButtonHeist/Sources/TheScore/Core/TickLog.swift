import Foundation
import ThePlans

/// The ordered ticks a run observed.
///
/// This is the durable artifact of a settlement run, and everything downstream
/// is derived from it rather than recomputed beside it:
///
/// - **Predicate state** is `Expectation.folding(log)`, never stored: given the
///   same log it always folds to the same answer.
/// - **Diffs for output** are read off the log. The ticks already say what
///   changed; comparing captures again to rediscover it is the old model.
///
/// A log holds only values, so folding one needs no actor and no main thread.
///
/// Ticks only. Node counts, first-responder movement and screen identity are
/// metadata a report derives from the log's endpoints, not state the log
/// carries: no predicate reads them and nothing branches on them.
package struct TickLog: Sendable, Equatable {
    package private(set) var ticks: [Tick]

    package init(_ ticks: [Tick] = []) {
        self.ticks = ticks
    }

    /// Appends a tick, coalescing runs of stillness.
    ///
    /// A second `.noChange` in a row is the same fact restated: the tree was
    /// already still, and nothing about the timeline changes by saying so
    /// again. Every other tick carries a reading, so none of them coalesce.
    package mutating func append(_ tick: Tick) {
        guard !(tick == .noChange && ticks.last == .noChange) else { return }
        ticks.append(tick)
    }

    package mutating func append(contentsOf newTicks: some Sequence<Tick>) {
        for tick in newTicks {
            append(tick)
        }
    }

    /// Each adjacent pair of ticks, in order.
    ///
    /// Comparing consecutive ticks is the whole of deriving what changed, so it
    /// is one primitive rather than a walk rewritten per consumer.
    package var steps: [TickStep] {
        zip(ticks, ticks.dropFirst()).map(TickStep.init)
    }

    /// The three ticks a screen replacement is, in causal order.
    ///
    /// The old screen's nodes depart, the screen identity moves, the new
    /// screen's nodes arrive. Both legs are whole graphs because identity does
    /// not survive a boundary: a control that looks the same on both sides is a
    /// new object, not the old one persisting.
    ///
    /// Order carries the meaning. A two-legged step does not read its after leg
    /// until the before leg drained, so `disappeared(X)` reads the departure and
    /// `appeared(X)` reads the arrival — the stitch sits between them so neither
    /// leg can match on the wrong side of it.
    ///
    /// The departure leg is an empty tree rather than the previous capture. A
    /// run does not necessarily hold the departing screen's last reading — on a
    /// boundary the arriving admission is often the run's first — so the leg
    /// that a `missing` half drains on has to be stated here rather than assumed
    /// to be already in the log.
    package static func replacement(
        screen: ScreenFacts,
        arriving capture: AccessibilityTrace.Capture
    ) -> [Tick] {
        [
            .elementsChanged(.empty(at: capture.interface.timestamp)),
            .screenChanged(screen),
            .elementsChanged(capture),
        ]
    }

    /// The captures this log read, in order, as a trace.
    ///
    /// The trace is a projection of the log rather than a second record kept
    /// beside it: every capture a run admitted is already a tick, so the
    /// artifact is a filter, not an accumulation. Screen, announcement and
    /// stillness ticks carry no capture and drop out.
    ///
    /// So does the empty tree a replacement opens with. It is a predicate
    /// device, not a reading anyone took, so it is not evidence and does not
    /// belong in the record of what was observed.
    package var trace: AccessibilityTrace? {
        ticks.reduce(into: nil) { trace, tick in
            guard case .elementsChanged(let capture) = tick,
                  !capture.interface.tree.isEmpty
            else { return }
            trace = trace?.appending(
                capture.interface,
                context: capture.context,
                transition: capture.transition
            ) ?? AccessibilityTrace(capture: capture)
        }
    }
}

/// Two adjacent ticks, which is what "what changed" is a question about.
///
/// A single tick is a reading; a change needs two. The answers come from the
/// ticks themselves rather than from comparing the trees again.
package struct TickStep: Sendable, Equatable {
    package let before: Tick
    package let after: Tick

    package init(_ before: Tick, _ after: Tick) {
        self.before = before
        self.after = after
    }

    /// Whether the screen identity moved across this step.
    ///
    /// True on the step that lands on the boundary marker, so the marker is
    /// attributed to the step that crossed it rather than the one after.
    package var crossesScreenBoundary: Bool {
        after.kind == .screenChanged
    }

    /// The trees this step compares, when it compares trees at all.
    ///
    /// A step touching the screen or announcement lanes has no element question
    /// in it, so there is nothing to diff and this is nil rather than an empty
    /// pair — absence of a comparison, not a comparison that found nothing.
    package var interfaces: (before: Interface, after: Interface)? {
        guard let before = before.interface, let after = after.interface else { return nil }
        return (before, after)
    }

    /// What entered, left, and changed across this step.
    ///
    /// The only place a tree is compared to another tree. Steps that name no
    /// element question are empty rather than absent, so callers fold them in
    /// without a special case.
    package var elementEdits: ElementEdits {
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
    package var elementSetChanged: Bool {
        guard let interfaces else { return false }
        return AccessibilityTraceElementDiff.pairingKeyMultisetDiffers(
            beforeRecords: interfaces.before.projectedElementRecords.map(ElementDiffRecord.init),
            afterRecords: interfaces.after.projectedElementRecords.map(ElementDiffRecord.init)
        )
    }
}
