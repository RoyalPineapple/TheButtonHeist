import BumperBowlingCore
import BumperBowlingTestSupport
import Testing

@Suite("Checked concurrency policy")
struct CheckedConcurrencyRuleTests {
    @Test
    func preconcurrencyEscapeHatchesAreRejected() throws {
        let path: RelativeFilePath = "ButtonHeist/Sources/TheInsideJob/LegacyImport.swift"
        let report = try evaluate(
            path: path,
            source: "@preconcurrency import Foundation"
        )

        #expect(report.violations.count == 1)
        #expect(report.contains(ViolationMatcher(
            id: "buttonheist.checked_concurrency",
            path: path
        )))
    }

    @Test
    func unsafeNonisolatedStateIsRejectedOutsideTheSPIBoundary() throws {
        let path: RelativeFilePath = "ButtonHeist/Sources/TheInsideJob/UnsafeState.swift"
        let report = try evaluate(
            path: path,
            source: "enum State { nonisolated(unsafe) static var shared = 0 }"
        )

        #expect(report.violations.count == 1)
        #expect(report.contains(ViolationMatcher(
            id: "buttonheist.checked_concurrency",
            path: path
        )))
    }

    @Test
    func checkedCodeRemainsValid() throws {
        let report = try evaluate(
            path: "ButtonHeist/Sources/TheInsideJob/CheckedState.swift",
            source: "enum State { static let callback: @Sendable () -> Void = {} }"
        )

        #expect(report.violations.isEmpty)
    }

    private func evaluate(path: RelativeFilePath, source: String) throws -> RuleReport {
        try evaluateButtonHeistRules(path: path, component: .runtime, source: source)
    }
}
