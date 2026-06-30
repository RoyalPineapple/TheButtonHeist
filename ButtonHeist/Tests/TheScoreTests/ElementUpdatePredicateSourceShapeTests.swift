import ButtonHeistTestSupport
import Foundation
import Testing

@Suite struct ElementUpdatePredicateSourceShapeTests {
    private let repository = SourceShapeRepository(filePath: #filePath)

    @Test func `property update matching is dispatched through typed witnesses`() throws {
        let source = try repository.requiredFile(relativePath: "ButtonHeist/Sources/TheScore/TreeChangeModels.swift")

        #expect(
            try source.containsMatch(#"\bprivate\s+struct\s+ObservedPropertyChangeSatisfier<\s*P\s*:\s*ElementPropertyValueKind\s*>"#),
            "Observed property changes should preserve their typed value witness while matching expected changes."
        )
        #expect(
            source.contents.contains("let expected = expected as? ElementPropertyChange<P>"),
            "Expected property changes should only satisfy an observed change after the generic property witness lines up."
        )
        #expect(
            try !source.containsMatch(#"\bpackage\s+func\s+satisfies\s*\([^)]*AnyPropertyChange[^)]*\)\s*->\s*Bool\s*\{\s*switch\s+expected\b"#),
            "PropertyChange.satisfies should not be a loose switch table over expected property/value cases."
        )
        #expect(
            try !source.containsMatch(#"\bprivate\s+func\s+satisfies\s*\([^)]*ElementPropertyChange<"#),
            "Per-property satisfies overloads reintroduce manual property/value compatibility dispatch."
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
