import ButtonHeistTestSupport
import Foundation
import Testing

@Suite struct ElementUpdatePredicateSourceShapeTests {
    private let repository = SourceShapeRepository(filePath: #filePath)

    @Test func `property update matching is dispatched through typed witnesses`() throws {
        let source = try repository.requiredFile(relativePath: "ButtonHeist/Sources/TheScore/TreeChangeModels.swift")
        let expectedChangeWitness =
            #"\bstatic\s+func\s+expectedChange\s*\(\s*from\s+change\s*:\s*AnyPropertyChange\s*\)\s*->\s*ElementPropertyChange<Self>[?]"#

        #expect(
            try source.containsMatch(expectedChangeWitness),
            "Property value kinds should provide the typed witness that extracts matching expected changes."
        )
        #expect(
            try source.containsMatch(#"\bguard\s+let\s+expected\s*=\s*P[.]expectedChange\s*\(\s*from\s*:\s*expected\s*\)"#),
            "Observed property changes should ask their generic property witness for the matching expected change."
        )
        #expect(
            try !source.containsMatch(#"\bpackage\s+func\s+satisfies\s*\([^)]*AnyPropertyChange[^)]*\)\s*->\s*Bool\s*\{\s*switch\s+expected\b"#),
            "PropertyChange.satisfies should not be a loose switch table over expected property/value cases."
        )
        #expect(
            try !source.containsMatch(#"\bprivate\s+func\s+satisfies\s*\([^)]*ElementPropertyChange<"#),
            "Per-property satisfies overloads reintroduce manual property/value compatibility dispatch."
        )
        #expect(
            !source.contents.contains("as? ElementPropertyChange"),
            "Property/value compatibility should be represented by typed witnesses, not runtime downcasts."
        )
    }

    @Test func `text property value kinds share one matcher witness`() throws {
        let source = try repository.requiredFile(relativePath: "ButtonHeist/Sources/TheScore/TreeChangeModels.swift")

        #expect(
            try source.containsMatch(#"\bprotocol\s+ElementTextPropertyValueKind\s*:\s*ElementPropertyValueKind\b"#),
            "Text-backed properties should share one canonical value-kind witness."
        )
        #expect(
            try source.matches(
                of: #"\bextension\s+(?:ValueProperty|LabelProperty|IdentifierProperty|HintProperty)\s*:\s*ElementTextPropertyValueKind\b"#
            ).count == 4,
            "Every text-backed property kind should use the shared value-kind witness."
        )
        #expect(
            try source.matches(
                of: #"guard\s+let\s+value\s+else\s*\{\s*return\s+false\s*\}\s*return\s+checker[.]matches\s*\(\s*value\s*\)"#,
                options: [.dotMatchesLineSeparators]
            ).count == 1,
            "Text property matching should have one canonical implementation."
        )
        #expect(
            try source.matches(of: #"[.]text\s*\(\s*value\s*\)"#).count == 1,
            "Text property erasure should have one canonical implementation."
        )
    }

    @Test func `updated element evaluation uses matched update projection`() throws {
        let source = try repository.requiredFile(
            relativePath: "ButtonHeist/Sources/TheScore/AccessibilityPredicate+Evaluation.swift"
        )

        #expect(
            try source.containsMatch(#"\bprivate\s+struct\s+MatchedElementUpdate\b"#),
            "Updated-element filtering should produce a named matched-update record."
        )
        #expect(
            try source.containsMatch(#"\bfunc\s+matching\s*\(\s*_\s+predicate\s*:\s*ElementUpdatePredicate\s*\)\s*->\s*MatchedElementUpdate[?]"#),
            "ElementUpdate should own its element/property matching projection."
        )
        #expect(
            try !source.containsMatch(#"\bvar\s+targetChanges\s*=\s*edit[.]changes\b"#),
            "The evaluator loop should not rebuild property-filtering state inline."
        )
        #expect(
            try !source.containsMatch(#"\bprivate\s+static\s+func\s+propertyChange\b"#),
            "Property-change matching should use the typed PropertyChange witness directly."
        )
    }

    @Test func `nested custom content and rotor strings use string matcher helpers`() throws {
        let source = try repository.requiredFile(relativePath: "ButtonHeist/Sources/TheScore/TreeChangeModels.swift")

        #expect(try source.containsMatch(#"\bprivate\s+extension\s+Optional\s+where\s+Wrapped\s*==\s*StringMatch<String>\s*\{"#))
        #expect(try source.containsMatch(#"\bprivate\s+extension\s+Collection\s+where\s+Element\s*==\s*String\s*\{"#))
        #expect(try source.containsMatch(#"\bprivate\s+extension\s+CustomContentMatch\s+where\s+Value\s*==\s*String\s*\{"#))
        #expect(
            try !source.containsMatch(#"checker[.]label[.]map\s*\{\s*\$0[.]matches\s*\(\s*content[.]label\s*\)"#),
            "Custom-content labels should use the shared optional StringMatch helper."
        )
        #expect(
            try !source.containsMatch(#"checker[.]value[.]map\s*\{\s*\$0[.]matches\s*\(\s*content[.]value\s*\)"#),
            "Custom-content values should use the shared optional StringMatch helper."
        )
        #expect(
            try !source.containsMatch(#"rotorNames[.]contains\s*\{\s*match[.]matches\s*\(\s*\$0\s*\)"#),
            "Rotor names should use the shared collection StringMatch helper."
        )
    }
}
