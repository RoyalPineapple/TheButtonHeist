import BumperBowlingCore
import BumperBowlingTestSupport
import Testing

@Suite("Any normalization boundary")
struct AnyBoundaryRuleTests {
    @Test
    func arbitraryProductionAPIsCannotExposeAny() throws {
        let path: RelativeFilePath = "ButtonHeist/Sources/TheInsideJob/UntypedValue.swift"
        let report = try evaluateButtonHeistRules(
            path: path,
            component: .runtime,
            source: "func render(_ value: Any) {}"
        )

        #expect(report.violations.count == 1)
        #expect(report.contains(ViolationMatcher(id: "buttonheist.any_boundary", path: path)))
    }

    @Test
    func namedSystemBoundariesNormalizeAnyImmediately() throws {
        let fixtures = [
            "private typealias FoundationFileAttributeDictionary = [String: Any]",
            "enum HeistValuePayloadDecoder { static func expectedDescription(for type: Any.Type) {} }",
            "enum FoundationInfoPlistProjection { static func value(from object: Any) {} }",
        ]

        for (index, source) in fixtures.enumerated() {
            let report = try evaluateButtonHeistRules(
                path: RelativeFilePath("ButtonHeist/Sources/TheInsideJob/Boundary\(index).swift"),
                component: .runtime,
                source: source
            )
            #expect(report.violations.isEmpty)
        }
    }
}
