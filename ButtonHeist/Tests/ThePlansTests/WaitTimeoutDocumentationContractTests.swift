import Foundation
import Testing

@testable import ThePlans

@Test func timeoutDocumentationRequiresStrictlyPositiveValues() throws {
    let specificationURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("docs/HEIST-LANGUAGE-SPEC.md")
    let specification = try String(contentsOf: specificationURL, encoding: .utf8)
    let strictRangeClaim = "`0 < value <= configuredMaximum`"

    #expect(
        specification.contains(strictRangeClaim),
        "\(specificationURL.path) must state the timeout range as \(strictRangeClaim)"
    )

    let claimsAdmittingZero = [
        "timeout: 0",
        "timeout of `0`",
        "zero timeout",
        "0 <= value",
        "0 ≤ value",
        "value >= 0",
        "value ≥ 0",
        "non-negative timeout",
        "nonnegative timeout",
    ]
    for claim in claimsAdmittingZero {
        #expect(
            !specification.localizedCaseInsensitiveContains(claim),
            "\(specificationURL.path) must not admit the timeout claim \(String(reflecting: claim))"
        )
    }

    let negativeBoundary = -Double.leastNonzeroMagnitude
    #expect(
        throws: WaitTimeoutError.self,
        "WaitTimeout must reject the negative boundary \(negativeBoundary)"
    ) {
        try WaitTimeout(validatingSeconds: negativeBoundary)
    }
    #expect(
        throws: WaitTimeoutError.self,
        "WaitTimeout must reject the zero boundary 0"
    ) {
        try WaitTimeout(validatingSeconds: 0)
    }

    let positiveBoundary = Double.leastNonzeroMagnitude
    let admitted = try WaitTimeout(validatingSeconds: positiveBoundary)
    #expect(
        admitted.seconds == positiveBoundary,
        "WaitTimeout must admit the smallest strictly positive boundary \(positiveBoundary)"
    )
}
