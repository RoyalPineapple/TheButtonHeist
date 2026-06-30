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

    @Test func `startup and resume resources share transport setup and callback wiring`() throws {
        let source = try sourceFile(
            relativePath: "ButtonHeist/Sources/TheInsideJob/InsideJobTransportRuntime.swift"
        )

        #expect(sourceOccurrenceCount("startRuntimeResources(", in: source) == 3)
        #expect(sourceOccurrenceCount("phase: .startup", in: source) == 1)
        #expect(sourceOccurrenceCount("phase: .resume", in: source) == 1)
        #expect(sourceOccurrenceCount("transportFactory(token, runtimeConfiguration.allowedScopes)", in: source) == 1)
        #expect(sourceOccurrenceCount("installTransportOverflowHandler(transport)", in: source) == 1)
        #expect(sourceOccurrenceCount("await getaway.wireTransport(transport)", in: source) == 1)
        #expect(sourceOccurrenceCount("try await transport.start(", in: source) == 1)
        #expect(sourceOccurrenceCount("cleanupFailedTransportStartup(transport)", in: source) == 1)
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
                "ButtonHeist/Sources/TheInsideJob/InsideJobAppLifecycle.swift": 3,
                "ButtonHeist/Sources/TheInsideJob/InsideJobRuntimeResources.swift": 1,
                "ButtonHeist/Sources/TheInsideJob/InsideJobTransportRuntime.swift": 4,
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
                "ButtonHeist/Sources/TheInsideJob/InsideJobRuntimeResources.swift": 1,
                "ButtonHeist/Sources/TheInsideJob/InsideJobTransportRuntime.swift": 2,
            ],
            "Unexpected TheInsideJob tlsActive writes: \(observed)"
        )
    }

    @Test func `runtime lifecycle has one phase and no sidecar lease state`() throws {
        let lifecycleSource = try sourceFile(
            relativePath: "ButtonHeist/Sources/TheInsideJob/InsideJobLifecycleState.swift"
        )
        let jobSource = try sourceFile(
            relativePath: "ButtonHeist/Sources/TheInsideJob/TheInsideJob.swift"
        )
        let transportSource = try sourceFile(
            relativePath: "ButtonHeist/Sources/TheInsideJob/Server/ServerTransport.swift"
        )

        #expect(lifecycleSource.contains("case running(InsideJobRuntimeResources)"))
        #expect(lifecycleSource.contains("case suspending(InsideJobSuspension)"))
        #expect(lifecycleSource.contains("case suspended(InsideJobSuspendedRuntime)"))
        #expect(lifecycleSource.contains("case resuming(InsideJobResumeAttempt)"))
        #expect(lifecycleSource.contains("case stopping(InsideJobStopAttempt)"))

        for forbidden in [
            "InsideJobRuntimeLease",
            "pendingTransportStopTask",
            "pendingForegroundResumeTask",
            "lifecycleObservationActive",
            "IdleTimerProtection",
            "releaseTask",
            "isActive",
        ] {
            #expect(!lifecycleSource.contains(forbidden))
            #expect(!jobSource.contains(forbidden))
        }

        #expect(!transportSource.contains("func stop() -> Task"))
        #expect(!transportSource.contains("@discardableResult\n    func stop()"))
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

private func sourceOccurrenceCount(_ needle: String, in source: String) -> Int {
    source.components(separatedBy: needle).count - 1
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
