import Foundation
import Testing
@testable import ThePlans

@Suite("Container predicate invariants")
struct ContainerPredicateInvariantTests {
    @Test("checks, counts, and required actions are structurally non-empty and non-negative")
    func structuralPayloads() throws {
        #expect(ContainerPredicateCount(exactly: -1) == nil)
        #expect(ContainerPredicateCount(exactly: 0) == ContainerPredicateCount(0))
        #expect(ContainerPredicateActions(Set<ElementAction>()) == nil)
        #expect(ContainerPredicateActions(Set([.custom("Archive")]))?.values == [.custom("Archive")])

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                ContainerPredicate.self,
                from: Data(#"{"checks":[]}"#.utf8)
            )
        }
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                ContainerPredicateCheck<String>.self,
                from: Data(#"{"kind":"rowCount","value":-1}"#.utf8)
            )
        }
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                ContainerPredicateCheck<String>.self,
                from: Data(#"{"kind":"actions","values":[]}"#.utf8)
            )
        }
    }

    @Test("removed duplicate wire spellings are rejected")
    func removedWireSpellings() {
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                ContainerPredicateCheck<String>.self,
                from: Data(
                    (#"{"kind":"semantic","semantic":{"kind":"identifier","# +
                        #""match":{"mode":"exact","value":"orders"}}}"#).utf8
                )
            )
        }
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                ContainerPredicateCheck<String>.self,
                from: Data(#"{"kind":"type","type":"scrollable"}"#.utf8)
            )
        }
    }

    @Test("semantic fields belong only to semantic roles")
    func semanticRole() {
        let semantic = ContainerPredicateFacts(
            role: .semanticGroup(label: "Checkout", value: "Ready")
        )
        let list = ContainerPredicateFacts(role: .list)

        #expect(ContainerPredicate.label("Checkout").matches(semantic))
        #expect(ContainerPredicate.value("Ready").matches(semantic))
        #expect(!ContainerPredicate.label("Checkout").matches(list))
        #expect(!ContainerPredicate.value("Ready").matches(list))
    }

    @Test("identifier and scrollability are orthogonal to role")
    func orthogonalFacts() {
        let facts = ContainerPredicateFacts(
            role: .list,
            identifier: "orders",
            isScrollable: true
        )

        #expect(ContainerPredicate.identifier("orders").matches(facts))
        #expect(ContainerPredicate.type(.list).matches(facts))
        #expect(ContainerPredicate.scrollable(true).matches(facts))
    }
}
