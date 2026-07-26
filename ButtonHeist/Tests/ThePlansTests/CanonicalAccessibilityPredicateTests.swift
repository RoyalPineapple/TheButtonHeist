import Foundation
import Testing
@testable import ThePlans

@Suite("Canonical Accessibility Predicate")
struct CanonicalAccessibilityPredicateTests {
    /// A screen predicate carries a match and never an assertion list, so its
    /// wire shape has no `assertions` key to be empty. The unnamed form asks
    /// only that a boundary happened, so it carries no `match` either.
    @Test("screen JSON carries the arrived-at match and no assertion list")
    func screenJSON() throws {
        #expect(try json(AccessibilityPredicate.screenChanged) == #"{"scope":"screen","type":"changed"}"#)
        #expect(
            try json(AccessibilityPredicate.screenChanged("Settings")) ==
            #"{"match":{"mode":"exact","value":"Settings"},"scope":"screen","type":"changed"}"#
        )
    }

    @Test("elements JSON uses one canonical target and assertion language")
    func elementsJSON() throws {
        let predicate = AccessibilityPredicate.elementsChanged([
            .exists(.label("Current")),
            .missing(.label("Gone")),
            .appeared(.label("New")),
            .disappeared(.label("Old")),
            .updated(.identifier("count"), .value(before: "1", after: "2")),
        ])

        let decoded = try JSONDecoder().decode(
            AccessibilityPredicate.self,
            from: JSONEncoder().encode(predicate)
        )
        #expect(decoded == predicate)
    }

    @Test("concrete assertion types share the canonical wire codec")
    func assertionJSON() throws {
        let root = AccessibilityPredicate.missing(.label("Loading"))
        let condition = PresenceCondition.missing(.label("Loading"))
        let elementPresence = ElementAssertion.missing(.label("Loading"))
        let elementUpdate = ElementAssertion.updated(
            .identifier("count"),
            .value(before: "1", after: "2")
        )

        let presenceJSON = #"{"target":{"checks":[{"kind":"label","match":{"mode":"exact","value":"Loading"}}]},"type":"missing"}"#
        #expect(try json(root) == presenceJSON)
        #expect(try json(condition) == presenceJSON)
        #expect(try json(elementPresence) == presenceJSON)
        #expect(try JSONDecoder().decode(
            AccessibilityPredicate.self,
            from: JSONEncoder().encode(root)
        ) == root)
        #expect(try JSONDecoder().decode(
            PresenceCondition.self,
            from: JSONEncoder().encode(condition)
        ) == condition)
        #expect(try JSONDecoder().decode(
            ElementAssertion.self,
            from: JSONEncoder().encode(elementPresence)
        ) == elementPresence)
        #expect(try JSONDecoder().decode(
            ElementAssertion.self,
            from: JSONEncoder().encode(elementUpdate)
        ) == elementUpdate)
    }

    @Test("announcement JSON is canonical and root only")
    func announcementJSON() throws {
        let any = AccessibilityPredicate.announcement
        let matching = AccessibilityPredicate.announcement(.contains("processed"))

        #expect(try json(any) == #"{"type":"announcement"}"#)
        #expect(
            try json(matching) ==
            #"{"match":{"mode":"contains","value":"processed"},"type":"announcement"}"#
        )
        #expect(
            try JSONDecoder().decode(
                AccessibilityPredicate.self,
                from: Data(#"{"match":{"mode":"contains","value":"processed"},"type":"announcement"}"#.utf8)
            ) == matching
        )
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                PresenceCondition.self,
                from: Data(#"{"type":"announcement"}"#.utf8)
            )
        }
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                ElementAssertion.self,
                from: Data(#"{"type":"announcement"}"#.utf8)
            )
        }
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                AccessibilityPredicate.self,
                from: Data(#"{"type":"announcement","target":{"ref":"row"}}"#.utf8)
            )
        }
    }

    @Test("branch presence projects through distinct authored and resolved types")
    func presenceConditionRootPredicate() throws {
        let condition = PresenceCondition.exists(.label("Receipt"))
        let root = AccessibilityPredicate.exists(.label("Receipt"))
        let resolvedCondition: ResolvedPresenceCondition = try condition.resolve(in: .empty)
        let resolvedRoot: ResolvedAccessibilityPredicate = try root.resolve(in: .empty)

        #expect(condition.rootPredicate == root)
        #expect(resolvedCondition.rootPredicate == resolvedRoot)
    }

    @Test("container-only targets use the canonical target slot")
    func containerTargetJSON() throws {
        let predicate = AccessibilityPredicate.exists(
            .container(.identifier("Checkout"), ordinal: 1)
        )
        let data = try JSONEncoder().encode(predicate)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let target = try #require(object["target"] as? [String: Any])

        let expectedJSON = #"{"target":{"container":{"checks":["# +
            #"{"kind":"identifier","match":{"mode":"exact","value":"Checkout"}}]},"# +
            #""ordinal":1},"type":"exists"}"#
        #expect(try json(predicate) == expectedJSON)
        #expect(object["type"] as? String == "exists")
        #expect(target["container"] != nil)
        #expect(target["ordinal"] as? Int == 1)
        #expect(predicate.description.contains("ordinal: 1"))
        #expect(try JSONDecoder().decode(AccessibilityPredicate.self, from: data) == predicate)
    }

    @Test(
        "malformed changed JSON is rejected",
        arguments: [
            #"{"type":"changed","scope":"screen","unexpected":true}"#,
            #"{"type":"changed","scope":"invalid","assertions":[]}"#,
            #"{"type":"changed","scope":"elements","assertions":[{"type":"updated","# +
                #""target":{"checks":[{"identifier":{"mode":"exact","value":"count"}}]},"# +
                #""property":"value","after":{"mode":"exact","value":"2"}}]}"#,
            #"{"type":"changed","scope":"elements","assertions":["# +
                #"{"type":"changed","scope":"screen"}]}"#,
            #"{"type":"exists","target":{"container":{"checks":["# +
                #"{"kind":"semantic","semantic":{"kind":"identifier","# +
                #""match":{"mode":"exact","value":"Checkout"}}}]},"ordinal":-1}}"#,
            #"{"type":"exists","target":{"container":{"checks":["# +
                #"{"kind":"semantic","semantic":{"kind":"identifier","# +
                #""match":{"mode":"exact","value":"Checkout"}}}]},"# +
                #""target":{"checks":["# +
                #"{"kind":"label","match":{"mode":"exact","value":"Pay"}}]},"ordinal":1}}"#,
        ]
    )
    func rejectsMalformedJSON(source: String) {
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(
                AccessibilityPredicate.self,
                from: Data(source.utf8)
            )
        }
    }

    /// Both screen spellings round-trip: bare `.screen()` for any boundary, and
    /// `.screen("Name")` for the arrived-at screen. The element question that
    /// used to ride inside `.screen([...])` is a sibling predicate now, so it
    /// round-trips through its own `WaitFor`.
    @Test("source parser and renderer use only changed screen spelling")
    func sourceRoundTrip() throws {
        let source = """
        HeistPlan {
            WaitFor(.screenChanged)
            WaitFor(.screenChanged("Receipt"))
            WaitFor(.exists(.container(.identifier("Checkout"), ordinal: 1)))
        }
        """
        let plan = try HeistSourceCompilation.compile(source)
        let expected = try HeistPlan(body: [
            .wait(WaitStep(predicate: .screenChanged, timeout: defaultWaitTimeout)),
            .wait(WaitStep(predicate: .screenChanged("Receipt"), timeout: defaultWaitTimeout)),
            .wait(WaitStep(
                predicate: .exists(.container(.identifier("Checkout"), ordinal: 1)),
                timeout: defaultWaitTimeout
            )),
        ])

        #expect(plan == expected)
        #expect(try plan.canonicalSwiftDSL().contains(".screenChanged"))
        #expect(try plan.canonicalSwiftDSL().contains(".screenChanged(\"Receipt\")"))
        #expect(try plan.canonicalSwiftDSL().contains(".container(.identifier(\"Checkout\"), ordinal: 1)"))
    }

    private func json(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try #require(String(data: encoder.encode(value), encoding: .utf8))
    }
}
