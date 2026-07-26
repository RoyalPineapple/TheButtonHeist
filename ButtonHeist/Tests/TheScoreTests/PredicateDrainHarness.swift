import AccessibilitySnapshotModel
import ButtonHeistTestSupport
import Foundation
import ThePlans
import XCTest
@testable import TheScore

/// A rig for asking one question: hand an `Expectation` a run of ticks, and see
/// what it did with them.
///
/// Everything the drain can be asked is here — any predicates, in any order,
/// against any of the five ticks, holding any elements. Nothing about a
/// particular assertion is baked in, so a new claim about the algebra is a
/// literal rather than a new test method.
///
/// Two things are read back, and both matter. `isMet` is the verdict. `owed` is
/// what the run would tell a user it is still waiting for, which is the only way
/// to see *how far* a half-satisfied pair got — a verdict of "no" cannot tell a
/// pair that never started from one that is one leg in.
enum Drain {

    /// One thing that can arrive, mirroring the five ways to move an
    /// `Expectation` forward.
    ///
    /// `empty` is not a separate mechanism — a screen change is every element
    /// going away, a moment of nothing, then elements arriving, and this is that
    /// moment. It is here as its own case only because writing `.tree([])` at
    /// every boundary hides what the boundary is.
    enum Tick {
        case tree([TestInterfaceNode])
        case empty
        case screen(String)
        case spoken(String)
        case still

        /// Elements by label alone, for the many claims that need nothing else.
        static func labels(_ labels: [String]) -> Self {
            .tree(labels.map { testElement(label: $0) })
        }
    }

    /// Feed `ticks` to `predicates` and report what happened.
    ///
    /// The trailing `still` that ends every real run is *not* added here.
    /// Settlement is half of `isMet`, so appending one silently would make every
    /// claim about stillness unstateable — a run that never went quiet is a real
    /// run, and rows say so by leaving `.still` off.
    static func run(
        _ predicates: [AccessibilityPredicate],
        through ticks: [Tick]
    ) throws -> Outcome {
        var expectation = Expectation(try predicates.map { try $0.resolve(in: .empty) })
        for tick in ticks {
            switch tick {
            case .tree(let nodes):
                expectation.snapshot(makeTestInterface(nodes: nodes))
            case .empty:
                expectation.empty(at: Date(timeIntervalSince1970: 0))
            case .screen(let id):
                expectation.screenChanged(ScreenFacts(idAfter: id))
            case .spoken(let text):
                expectation.announcement(text)
            case .still:
                expectation.noChange()
            }
        }
        return Outcome(isMet: expectation.isMet, outstanding: expectation.outstanding)
    }

    /// What a run came to.
    struct Outcome {
        let isMet: Bool
        let outstanding: [String]

        /// What is owed, with the settlement gate dropped.
        ///
        /// The gate is in `outstanding` on every tick that was not stillness, so
        /// leaving it in makes every count off by one depending on how the run
        /// ended. Claims about the gate read `isMet`; claims about predicates
        /// read this.
        var owed: [String] {
            outstanding.filter { $0 != "the tree to stop changing" }
        }
    }
}

/// One closed statement about the algebra: these predicates, these ticks, this
/// verdict.
///
/// `owed` is optional because most claims are about the verdict alone. Set it
/// when the claim is about *position* — that a pair is one leg in, or that a
/// slot survived, or that nothing was consumed. A verdict cannot say those.
struct DrainClaim {
    let number: Int
    let says: String
    let predicates: [AccessibilityPredicate]
    let ticks: [Drain.Tick]
    let holds: Bool
    let owed: [String]?

    init(
        _ number: Int,
        _ says: String,
        _ predicates: [AccessibilityPredicate],
        _ ticks: [Drain.Tick],
        holds: Bool,
        owed: [String]? = nil
    ) {
        self.number = number
        self.says = says
        self.predicates = predicates
        self.ticks = ticks
        self.holds = holds
        self.owed = owed
    }
}

extension XCTestCase {

    /// Check every claim, reporting each failure against the claim that made it.
    ///
    /// One loop rather than one test per claim: a table where a shape with no row
    /// is a visible hole only works if adding a row costs a line.
    func check(
        _ claims: [DrainClaim],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        for claim in claims {
            let outcome = try Drain.run(claim.predicates, through: claim.ticks)
            XCTAssertEqual(
                outcome.isMet, claim.holds,
                "claim \(claim.number): \(claim.says) — owed: \(outcome.owed)",
                file: file, line: line
            )
            if let expected = claim.owed {
                XCTAssertEqual(
                    outcome.owed, expected,
                    "claim \(claim.number): \(claim.says) — owed the wrong thing",
                    file: file, line: line
                )
            }
        }
    }
}
