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

    @Test func `server phase writes stay in lifecycle runtime owners`() throws {
        let observed = try sourceAssignmentCounts(
            identifier: "serverPhase",
            relativeRoot: "ButtonHeist/Sources/TheInsideJob",
            excluding: [
                "ButtonHeist/Sources/TheInsideJob/Server/SimpleSocketServer.swift",
            ]
        )

        #expect(
            observed == [
                "ButtonHeist/Sources/TheInsideJob/InsideJobAppLifecycle.swift": 2,
                "ButtonHeist/Sources/TheInsideJob/InsideJobRuntimeLease.swift": 1,
                "ButtonHeist/Sources/TheInsideJob/InsideJobTransportRuntime.swift": 3,
            ],
            "Unexpected TheInsideJob serverPhase writes: \(observed)"
        )
    }

    @Test func `tls activity writes stay in runtime activation and token cleanup`() throws {
        let observed = try sourceAssignmentCounts(
            identifier: "tlsActive",
            relativeRoot: "ButtonHeist/Sources/TheInsideJob"
        )

        #expect(
            observed == [
                "ButtonHeist/Sources/TheInsideJob/InsideJobRuntimeLease.swift": 1,
                "ButtonHeist/Sources/TheInsideJob/InsideJobTransportRuntime.swift": 2,
            ],
            "Unexpected TheInsideJob tlsActive writes: \(observed)"
        )
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

private func sourceAssignmentCounts(
    identifier: String,
    relativeRoot: String,
    excluding excludedPaths: Set<String> = []
) throws -> [String: Int] {
    let repoRoot = repositoryRoot()
    let root = repoRoot.appendingPathComponent(relativeRoot)
    let escapedIdentifier = NSRegularExpression.escapedPattern(for: identifier)
    let regex = try NSRegularExpression(pattern: #"(?<![A-Za-z0-9_])\#(escapedIdentifier)\s*="#)
    guard let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
    ) else {
        return [:]
    }

    var counts: [String: Int] = [:]
    for case let url as URL in enumerator where url.pathExtension == "swift" {
        let relativePath = url.path.replacingOccurrences(of: repoRoot.path + "/", with: "")
        guard !excludedPaths.contains(relativePath) else { continue }

        let source = try String(contentsOf: url, encoding: .utf8)
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        let matchCount = regex.numberOfMatches(in: source, range: range)
        if matchCount > 0 {
            counts[relativePath] = matchCount
        }
    }
    return counts
}
