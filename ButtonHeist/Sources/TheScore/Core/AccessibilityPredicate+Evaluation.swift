import ThePlans
import Foundation

extension AccessibilityTrace {
    /// This trace's captures as the tick log they came from.
    ///
    /// A reconstruction, and the only one: the live run's log is not persisted
    /// yet, so a stored trace rebuilds it from the captures. Each capture's
    /// interface is a tick, and a replacement edge is the three ordered ticks a
    /// replacement is.
    ///
    /// The rebuild carries the readings the run took. A stored trace is asked
    /// only whether its predicates hold, which is what those readings answer.
    ///
    /// When the live log is durable this becomes a read instead of a rebuild,
    /// and the classification below goes away — settlement already knew.
    var tickLog: TickLog {
        var log = TickLog()
        var previous: Capture?
        for capture in captures {
            if let previous,
               AccessibilityObservationChangeReducer.reduce(between: previous, and: capture) == .screenChanged {
                log.append(contentsOf: TickLog.replacement(
                    screen: ScreenFacts(idAfter: InterfaceSummary.screenName(for: capture.interface)),
                    arriving: capture
                ))
            } else {
                log.append(.elementsChanged(capture))
            }
            previous = capture
        }
        return log
    }
}

package extension ResolvedAccessibilityPredicate {
    /// Answer this predicate by folding the trace's tick log.
    ///
    /// One algebra, fed from history instead of the wire: the same fold a live
    /// run performs, over the same tick vocabulary.
    func evaluate(in evidence: AccessibilityTraceEvidence) -> PredicateEvaluationResult {
        let expectation = Expectation([self]).folding(evidence.trace.tickLog.ticks)
        return PredicateEvaluationResult(
            met: expectation.isMet,
            actual: expectation.isMet ? nil : expectation.outstanding.map(\.description).joined(separator: "; ")
        )
    }

    func validate(against result: ActionResult) -> PredicateEvaluationResult {
        guard let evidence = result.traceEvidence else {
            return PredicateEvaluationResult(met: false, actual: "no observed accessibility trace")
        }
        return evaluate(in: evidence)
    }
}
