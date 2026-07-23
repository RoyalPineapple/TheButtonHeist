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
            (
                RelativeFilePath("ButtonHeist/Sources/TheInsideJob/Boundary0.swift"),
                "private typealias FoundationFileAttributeDictionary = [String: Any]"
            ),
            (
                RelativeFilePath("ButtonHeist/Sources/TheInsideJob/Boundary1.swift"),
                "enum HeistValuePayloadDecoder { static func expectedDescription(for type: Any.Type) {} }"
            ),
            (
                RelativeFilePath("ButtonHeist/Sources/TheInsideJob/Lifecycle/StartupConfiguration.swift"),
                "func decodeFoundationInfoPlistValue(_ object: Any) {}"
            ),
        ]

        for (path, source) in fixtures {
            let report = try evaluateButtonHeistRules(
                path: path,
                component: .runtime,
                source: source
            )
            #expect(report.violations.isEmpty)
        }
    }

    @Test
    func boundaryFunctionNameDoesNotExemptOtherFiles() throws {
        let path: RelativeFilePath = "ButtonHeist/Sources/TheInsideJob/OtherDecoder.swift"
        let report = try evaluateButtonHeistRules(
            path: path,
            component: .runtime,
            source: "func decodeFoundationInfoPlistValue(_ object: Any) {}"
        )

        #expect(report.contains(ViolationMatcher(id: "buttonheist.any_boundary", path: path)))
    }
}
