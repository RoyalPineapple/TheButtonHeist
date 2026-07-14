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
                ContainerPredicateCheck.self,
                from: Data(#"{"kind":"rowCount","value":-1}"#.utf8)
            )
        }
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                ContainerPredicateCheck.self,
                from: Data(#"{"kind":"columnCount","value":-1}"#.utf8)
            )
        }
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                ContainerPredicateCheck.self,
                from: Data(#"{"kind":"actions","values":[]}"#.utf8)
            )
        }
    }

    @Test("removed duplicate wire spellings are rejected")
    func removedWireSpellings() {
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                ContainerPredicate.self,
                from: Data(#"{"identifier":"orders"}"#.utf8)
            )
        }
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                ContainerPredicateCheck.self,
                from: Data(
                    (#"{"kind":"semantic","semantic":{"kind":"identifier","# +
                        #""match":{"mode":"exact","value":"orders"}}}"#).utf8
                )
            )
        }
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                ContainerPredicateCheck.self,
                from: Data(#"{"kind":"type","type":"scrollable"}"#.utf8)
            )
        }
    }

    @Test("container check kinds reject payload keys owned by other kinds", arguments: [
        #"{"kind":"identifier","match":{"mode":"exact","value":"orders"},"semantic":{"kind":"label","match":{"mode":"exact","value":"Orders"}}}"#,
        #"{"kind":"semantic","semantic":{"kind":"label","match":{"mode":"exact","value":"Orders"}},"match":{"mode":"exact","value":"orders"}}"#,
        #"{"kind":"scrollable","value":true,"type":"none"}"#,
        #"{"kind":"actions","values":["activate"],"value":true}"#,
    ])
    func rejectsCrossKindPayloadKeys(source: String) {
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                ContainerPredicateCheck.self,
                from: Data(source.utf8)
            )
        }
    }

    @Test("semantic fields belong only to semantic roles")
    func semanticRole() throws {
        let semantic = ContainerPredicateFacts(
            role: .semanticGroup(label: "Checkout", value: "Ready")
        )
        let list = ContainerPredicateFacts(role: .list)

        #expect(try ContainerPredicate.label("Checkout").resolve(in: .empty).matches(semantic))
        #expect(try ContainerPredicate.value("Ready").resolve(in: .empty).matches(semantic))
        #expect(!(try ContainerPredicate.label("Checkout").resolve(in: .empty).matches(list)))
        #expect(!(try ContainerPredicate.value("Ready").resolve(in: .empty).matches(list)))
    }

    @Test("identifier and scrollability are orthogonal to role")
    func orthogonalFacts() throws {
        let facts = ContainerPredicateFacts(
            role: .list,
            identifier: "orders",
            isScrollable: true
        )

        #expect(try ContainerPredicate.identifier("orders").resolve(in: .empty).matches(facts))
        #expect(try ContainerPredicate.type(.list).resolve(in: .empty).matches(facts))
        #expect(try ContainerPredicate.scrollable(true).resolve(in: .empty).matches(facts))
    }
}
