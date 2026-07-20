import Foundation
import Testing

@Test func timeoutDocumentationRequiresStrictlyPositiveValues() throws {
    let specificationURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("docs/HEIST-LANGUAGE-SPEC.md")
    let specification = try String(contentsOf: specificationURL, encoding: .utf8)
    let violation = timeoutDocumentationViolation(in: specification)

    #expect(
        violation == nil,
        "\(specificationURL.path) violates the timeout contract: \(String(describing: violation))"
    )
}

@Test func timeoutDocumentationValidationRejectsContradictoryClaims() {
    let fixtures = [
        TimeoutDocumentationFixture(
            document: "WaitFor(.exists(.label(\"Done\")), timeout: 0)",
            contradiction: .zeroValuedExample
        ),
        TimeoutDocumentationFixture(
            document: "A timeout of zero is valid for bounded waits.",
            contradiction: .zeroIsValid
        ),
        TimeoutDocumentationFixture(
            document: "A timeout of zero executes the bounded wait once.",
            contradiction: .zeroExecutesOnce
        ),
        TimeoutDocumentationFixture(
            document: "Timeouts satisfy `0 <= value <= configuredMaximum`.",
            contradiction: .nonStrictLowerBound
        ),
    ]

    for fixture in fixtures {
        #expect(
            timeoutDocumentationViolation(in: fixture.document) == fixture.contradiction,
            "Expected diagnostic identifying \(fixture.contradiction)"
        )
    }

    #expect(timeoutDocumentationViolation(in: "Timeouts satisfy `0 < value <= configuredMaximum`.") == nil)
}

private struct TimeoutDocumentationFixture {
    let document: String
    let contradiction: TimeoutDocumentationContradiction
}

private enum TimeoutDocumentationContradiction: String, CustomStringConvertible {
    case zeroValuedExample = "zero-valued bounded-wait example"
    case zeroIsValid = "guidance claiming zero is valid"
    case zeroExecutesOnce = "guidance claiming zero executes once"
    case nonStrictLowerBound = "non-strict lower-bound claim"
    case missingStrictLowerBound = "missing strict lower-bound claim"

    var description: String { rawValue }
}

private func timeoutDocumentationViolation(
    in document: String
) -> TimeoutDocumentationContradiction? {
    let normalized = document.lowercased()
    let compact = normalized.split(whereSeparator: \Character.isWhitespace).joined(separator: " ")

    if normalized.range(
        of: #"timeout\s*:\s*0(?:\.0+)?\s*[,)]"#,
        options: .regularExpression
    ) != nil {
        return .zeroValuedExample
    }
    if normalized.range(
        of: #"zero\s+is\s+(?:valid|accepted|allowed|permitted)"#,
        options: .regularExpression
    ) != nil {
        return .zeroIsValid
    }
    if normalized.range(
        of: #"zero[^.\n]{0,80}executes?[^.\n]{0,80}\bonce\b"#,
        options: .regularExpression
    ) != nil {
        return .zeroExecutesOnce
    }
    if compact.contains("0 <= value <= configuredmaximum") {
        return .nonStrictLowerBound
    }
    guard compact.contains("0 < value <= configuredmaximum") else {
        return .missingStrictLowerBound
    }
    return nil
}
