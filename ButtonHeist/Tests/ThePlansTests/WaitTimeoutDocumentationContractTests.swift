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
    let canonicalRangeStatement = """
    Timeouts MUST be finite and satisfy
    `0 < value <= configuredMaximum`.
    """

    #expect(
        specification.contains(canonicalRangeStatement),
        "\(specificationURL.path) must contain \(String(reflecting: canonicalRangeStatement))"
    )
}
