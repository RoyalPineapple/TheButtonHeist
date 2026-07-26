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

    /// The three ticks a screen replacement is, in causal order.
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
