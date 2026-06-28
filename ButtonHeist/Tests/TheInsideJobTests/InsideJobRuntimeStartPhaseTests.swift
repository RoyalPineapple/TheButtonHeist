import Foundation
import Testing

#if canImport(UIKit)
@testable import TheInsideJob
#endif

@Suite struct InsideJobRuntimeStartPhaseSourceTests {

    @Test func `startup and resume runtime phases are typed before diagnostics`() throws {
        let transportSource = try sourceFile(
            relativePath: "ButtonHeist/Sources/TheInsideJob/InsideJobTransportRuntime.swift"
        )
        let lifecycleSource = try sourceFile(
            relativePath: "ButtonHeist/Sources/TheInsideJob/InsideJobLifecycleState.swift"
        )
        let errorSource = try sourceFile(
            relativePath: "ButtonHeist/Sources/TheInsideJob/InsideJobStartupError.swift"
        )

        #expect(lifecycleSource.contains("enum InsideJobRuntimeStartPhase: Equatable, Sendable"))
        #expect(errorSource.contains("case tokenRequired(phase: InsideJobRuntimeStartPhase)"))

        let sources = [
            ("transport runtime", transportSource),
            ("lifecycle state", lifecycleSource),
            ("startup error", errorSource),
        ]
        for forbidden in [
            #"phase: String"#,
            #"phase: "startup""#,
            #"phase: "resume""#,
            #"case tokenRequired(phase: String)"#,
        ] {
            for (name, source) in sources {
                #expect(
                    !source.contains(forbidden),
                    "\(name) should use InsideJobRuntimeStartPhase instead of \(forbidden)"
                )
            }
        }
    }
}

#if canImport(UIKit)
@Suite struct InsideJobStartupErrorTests {

    @Test func `token requirement diagnostics render closed runtime phases`() {
        #expect(
            InsideJobStartupError
                .tokenRequired(phase: .startup)
                .errorDescription?
                .contains("during startup;") == true
        )
        #expect(
            InsideJobStartupError
                .tokenRequired(phase: .resume)
                .errorDescription?
                .contains("during resume;") == true
        )
    }
}
#endif

private func sourceFile(relativePath: String) throws -> String {
    try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
