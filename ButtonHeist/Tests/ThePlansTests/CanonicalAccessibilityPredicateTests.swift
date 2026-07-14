import Foundation
import Testing
@testable import ThePlans

@Suite("Canonical Accessibility Predicate")
struct CanonicalAccessibilityPredicateTests {
    @Test("screen JSON includes required empty assertions")
    func screenJSON() throws {
        let predicate = AccessibilityPredicate.changed(.screen())
        #expect(try json(predicate) == #"{"assertions":[],"scope":"screen","type":"changed"}"#)
    }

    @Test("elements JSON uses one canonical target and assertion language")
    func elementsJSON() throws {
        let predicate = AccessibilityPredicate.changed(.elements([
            .exists(.label("Current")),
            .missing(.label("Gone")),
            .appeared(.label("New")),
            .disappeared(.label("Old")),
            .updated(.identifier("count"), .value(before: "1", after: "2")),
        ]))

        let decoded = try JSONDecoder().decode(
            AccessibilityPredicate.self,
            from: JSONEncoder().encode(predicate)
        )
        #expect(decoded == predicate)
    }

    @Test("concrete assertion types share the canonical wire codec")
    func assertionJSON() throws {
        let root = AccessibilityPredicate.missing(.label("Loading"))
        let screen = ChangeDeclaration.ScreenAssertion.missing(.label("Loading"))
        let elementPresence = ChangeDeclaration.ElementAssertion.missing(.label("Loading"))
        let elementUpdate = ChangeDeclaration.ElementAssertion.updated(
            .identifier("count"),
            .value(before: "1", after: "2")
        )

        let presenceJSON = #"{"target":{"checks":[{"kind":"label","match":{"mode":"exact","value":"Loading"}}]},"type":"missing"}"#
        #expect(try json(root) == presenceJSON)
        #expect(try json(screen) == presenceJSON)
        #expect(try json(elementPresence) == presenceJSON)
        #expect(try JSONDecoder().decode(
            AccessibilityPredicate.self,
            from: JSONEncoder().encode(root)
        ) == root)
        #expect(try JSONDecoder().decode(
            ChangeDeclaration.ScreenAssertion.self,
            from: JSONEncoder().encode(screen)
        ) == screen)
        #expect(try JSONDecoder().decode(
            ChangeDeclaration.ElementAssertion.self,
            from: JSONEncoder().encode(elementPresence)
        ) == elementPresence)
        #expect(try JSONDecoder().decode(
            ChangeDeclaration.ElementAssertion.self,
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
                ChangeDeclaration.ScreenAssertion.self,
                from: Data(#"{"type":"announcement"}"#.utf8)
            )
        }
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                ChangeDeclaration.ElementAssertion.self,
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

    @Test("screen presence projects through distinct authored and resolved types")
    func screenAssertionRootPredicate() throws {
        let assertion = ChangeDeclaration.ScreenAssertion.exists(.label("Receipt"))
        let root = AccessibilityPredicate.exists(.label("Receipt"))
        let resolvedAssertion: ResolvedScreenAssertion = try assertion.resolve(in: .empty)
        let resolvedRoot: ResolvedAccessibilityPredicate = try root.resolve(in: .empty)

        #expect(assertion.rootPredicate == root)
        #expect(resolvedAssertion.rootPredicate == resolvedRoot)
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
        #expect(predicate.description.contains("ordinal=1"))
        #expect(try JSONDecoder().decode(AccessibilityPredicate.self, from: data) == predicate)
    }

    @Test(
        "malformed changed JSON is rejected",
        arguments: [
            #"{"type":"changed","scope":"screen"}"#,
            #"{"type":"changed","scope":"screen","assertions":[],"unexpected":true}"#,
            #"{"type":"changed","scope":"invalid","assertions":[]}"#,
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
    func rejectsMalformedJSON(source: String) {
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(
                AccessibilityPredicate.self,
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

    private func json(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try #require(String(data: encoder.encode(value), encoding: .utf8))
    }
}
