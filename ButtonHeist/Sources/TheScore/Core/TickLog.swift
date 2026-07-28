import Foundation
import ThePlans

/// The ordered ticks a run observed.
///
/// A recording of the past, appended to as the run goes and read once it is
/// over. A log holds only values, so folding one needs no actor and no main
/// thread.
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

    /// Every announcement this log observed, in the order it observed them.
    ///
    /// An announcement is a tick in its own right, so this is where one is
    /// recorded. Reading it back off the captures instead only finds the ones
    /// that happened to arrive while a reading was being folded in, which is a
    /// question about timing rather than about what was announced.
    package var announcements: [String] {
        ticks.compactMap { tick in
            guard case .announcement(let text) = tick else { return nil }
            return text
        }
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
