import Foundation
import Testing
@testable import ThePlans

@Suite("Canonical Accessibility Predicate")
struct CanonicalAccessibilityPredicateTests {
    @Test("screen JSON includes required empty assertions")
    func screenJSON() throws {
        let predicate = AccessibilityPredicate<RootContext>.changed(.screen())
        #expect(try json(predicate) == #"{"assertions":[],"scope":"screen","type":"changed"}"#)
    }

    @Test("elements JSON uses one canonical target and assertion language")
    func elementsJSON() throws {
        let predicate = AccessibilityPredicate<RootContext>.changed(.elements([
            .exists(.label("Current")),
            .missing(.label("Gone")),
            .appeared(.label("New")),
            .disappeared(.label("Old")),
            .updated(.identifier("count"), .value(before: "1", after: "2")),
        ]))

        let decoded = try JSONDecoder().decode(
            AccessibilityPredicate<RootContext>.self,
            from: JSONEncoder().encode(predicate)
        )
        #expect(decoded == predicate)
    }

    @Test("announcement JSON is canonical and root only")
    func announcementJSON() throws {
        let any = AccessibilityPredicate<RootContext>.announcement
        let matching = AccessibilityPredicate<RootContext>.announcement(.contains("processed"))

        #expect(try json(any) == #"{"type":"announcement"}"#)
        #expect(
            try json(matching) ==
            #"{"match":{"mode":"contains","value":"processed"},"type":"announcement"}"#
        )
        #expect(
            try JSONDecoder().decode(
                AccessibilityPredicate<RootContext>.self,
                from: Data(#"{"match":{"mode":"contains","value":"processed"},"type":"announcement"}"#.utf8)
            ) == matching
        )
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                AccessibilityPredicate<ScreenAssertionContext>.self,
                from: Data(#"{"type":"announcement"}"#.utf8)
            )
        }
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                AccessibilityPredicate<ElementsAssertionContext>.self,
                from: Data(#"{"type":"announcement"}"#.utf8)
            )
        }
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                AccessibilityPredicate<RootContext>.self,
                from: Data(#"{"type":"announcement","target":{"ref":"row"}}"#.utf8)
            )
        }
    }

    @Test("screen assertions widen to root without changing their node")
    func screenAssertionRootPredicate() {
        let assertion = AccessibilityPredicate<ScreenAssertionContext>.exists(.label("Receipt"))

        #expect(assertion.rootPredicate == AccessibilityPredicate<RootContext>.exists(.label("Receipt")))
        #expect(assertion.rootPredicate.node == assertion.node)
    }

    @Test("container-only targets use the canonical target slot")
    func containerTargetJSON() throws {
        let predicate = AccessibilityPredicate<RootContext>.exists(
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
        #expect(predicate.description.contains("ordinal=1"))
        #expect(try JSONDecoder().decode(AccessibilityPredicate<RootContext>.self, from: data) == predicate)
    }

    @Test(
        "legacy and malformed changed JSON is rejected",
        arguments: [
            #"{"type":"change"}"#,
            #"{"type":"change","scopes":[]}"#,
            #"{"type":"changed","scope":"screen"}"#,
            #"{"type":"changed","scope":"screen","assertions":[],"scopes":[]}"#,
            #"{"type":"changed","scope":"all","assertions":[]}"#,
            #"{"type":"changed","scopes":[{"type":"screen","assertions":[]}]}"#,
            #"{"type":"changed","scope":"screen","assertions":[{"type":"updated","# +
                #""target":{"checks":[{"identifier":{"mode":"exact","value":"count"}}]},"# +
                #""property":"value","after":{"mode":"exact","value":"2"}}]}"#,
            #"{"type":"changed","scope":"elements","assertions":["# +
                #"{"type":"changed","scope":"screen","assertions":[]}]}"#,
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
    func rejectsLegacyAndMalformedJSON(source: String) {
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(
                AccessibilityPredicate<RootContext>.self,
                from: Data(source.utf8)
            )
        }
    }

    @Test("source parser and renderer use only changed screen spelling")
    func sourceRoundTrip() throws {
        let source = """
        HeistPlan {
            WaitFor(.changed(.screen([.exists(.label("Receipt"))])))
            WaitFor(.exists(.container(.identifier("Checkout"), ordinal: 1)))
        }
        """
        let plan = try HeistPlanSourceCompiler().compile(source)
        let expected = try HeistPlan(body: [
            .wait(WaitStep(
                predicate: .changed(.screen([.exists(.label("Receipt"))])),
                timeout: defaultWaitTimeout
            )),
            .wait(WaitStep(
                predicate: .exists(.container(.identifier("Checkout"), ordinal: 1)),
                timeout: defaultWaitTimeout
            )),
        ])

        #expect(plan == expected)
        #expect(try plan.canonicalSwiftDSL().contains(".changed(.screen([.exists(.label(\"Receipt\"))]))"))
        #expect(try plan.canonicalSwiftDSL().contains(".container(.identifier(\"Checkout\"), ordinal: 1)"))
    }

    @Test("source parser rejects old and combined spellings", arguments: [
        "WaitFor(.change(.screen()))",
        "WaitFor(.screenChanged)",
        "WaitFor(.changed())",
        "WaitFor(.changed(.screen(), .elements()))",
        "WaitFor(.changed(.all(.screen(), .elements())))",
        "WaitFor(.exists(.container(.identifier(\"Checkout\"), 1)))",
        "WaitFor(.exists(.target(.container(.identifier(\"Checkout\")), ordinal: 1)))",
    ])
    func rejectsOldSource(source: String) {
        #expect(throws: (any Error).self) {
            _ = try HeistPlanSourceCompiler().compile(source)
        }
    }

    private func json(_ predicate: AccessibilityPredicate<RootContext>) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try #require(String(data: encoder.encode(predicate), encoding: .utf8))
    }
}
