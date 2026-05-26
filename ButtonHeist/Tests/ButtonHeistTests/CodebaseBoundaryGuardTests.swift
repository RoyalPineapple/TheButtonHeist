import XCTest

final class CodebaseBoundaryGuardTests: XCTestCase {
    private let publicDictionaryAdapterCall = "json" + "Dict("

    func testRuntimeOwnerFilesStayBelowReleaseGate() throws {
        let violations = try swiftSources(under: [
            "ButtonHeist/Sources/TheButtonHeist",
            "ButtonHeist/Sources/TheInsideJob",
        ])
            .filter { source in
                !Self.allowedLargeModelOrCatalogFiles.contains(source.relativePath)
            }
            .filter { source in
                source.lineCount > Self.maxRuntimeOwnerLineCount
            }

        XCTAssertTrue(
            violations.isEmpty,
            """
            Runtime owners should stay below \(Self.maxRuntimeOwnerLineCount) lines unless they are models/catalogs.
            Split by product invariant instead of adding helper junk drawers:
            \(violations.map { "\($0.relativePath): \($0.lineCount)" }.sorted().joined(separator: "\n"))
            """
        )

        let handler = try XCTUnwrap(try swiftSources(under: [
            "ButtonHeist/Sources/TheButtonHeist/TheFence",
        ]).first { $0.relativePath == "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+Handlers.swift" })
        XCTAssertLessThan(
            handler.lineCount,
            450,
            "TheFence+Handlers.swift should remain the interaction handler surface, not the full command runtime."
        )
    }

    func testRawCommandPayloadDictionariesStayAtNamedBoundaries() throws {
        let violations = try swiftSources(under: Self.productionSourceRoots)
            .filter { source in
                source.contains("[String: Any]")
                    || source.contains("Dictionary<String, Any>")
                    || source.contains("JSONSerialization.")
                    || source.contains(publicDictionaryAdapterCall)
            }
            .filter { source in
                !Self.allowedUntypedBoundaryFiles.contains(source.relativePath)
            }
            .filter { source in
                !Self.allowedPlatformDictionaryFiles.contains(source.relativePath)
            }

        XCTAssertTrue(
            violations.isEmpty,
            """
            Untyped payload or JSON object bridges are only allowed at named adapter/platform boundaries.
            Move new raw payload parsing to a typed boundary or add a deliberately named exception with tests:
            \(violations.map(\.relativePath).sorted().joined(separator: "\n"))
            """
        )
    }

    func testRuntimeExecutionCoreHasNoRawPayloadDictionaries() throws {
        let coreRuntimeRoots = [
            "ButtonHeist/Sources/TheInsideJob/TheBrains",
            "ButtonHeist/Sources/TheInsideJob/TheStash",
            "ButtonHeist/Sources/TheButtonHeist/TheHandoff",
        ]
        let violations = try swiftSources(under: coreRuntimeRoots)
            .filter { source in
                source.contains("[String: Any]")
                    || source.contains("Dictionary<String, Any>")
                    || source.contains("JSONSerialization.")
                    || source.contains(publicDictionaryAdapterCall)
            }

        XCTAssertTrue(
            violations.isEmpty,
            """
            Runtime execution core must consume typed values only. Raw command payloads belong at adapter ingress,
            the public execute(request:) boundary, or the public JSON serializer shim:
            \(violations.map(\.relativePath).sorted().joined(separator: "\n"))
            """
        )
    }

    func testRuntimeTryQuestionRefsAreBoundaryClassified() throws {
        let matches = try swiftSources(under: Self.productionSourceRoots)
            .flatMap { $0.executableLines(matchingRegex: #"\btry\?"#) }

        let runtimeViolations = matches.filter { match in
            !Self.allowedBoundaryTryQuestionFiles.contains(match.relativePath)
        }
        XCTAssertTrue(
            runtimeViolations.isEmpty,
            """
            runtime_try_question_refs must be zero. Any remaining try? must live in a named
            display, cleanup, or polymorphic-decode boundary:
            \(Self.format(runtimeViolations))
            """
        )

        let undocumentedBoundaryRefs = matches.filter { match in
            guard Self.allowedBoundaryTryQuestionFiles.contains(match.relativePath) else { return false }
            return !match.source.hasBoundaryTryQuestionComment(before: match.lineNumber)
        }
        XCTAssertTrue(
            undocumentedBoundaryRefs.isEmpty,
            """
            boundary_try_question_refs must be documented near the use site with "Boundary try?":
            \(Self.format(undocumentedBoundaryRefs))
            """
        )
    }

    func testCoreFallbackRefsAreClassified() throws {
        let bestEffortRefs = try swiftSources(under: Self.productionSourceRoots)
            .flatMap { $0.executableLines(containing: "bestEffort") }
        XCTAssertTrue(
            bestEffortRefs.isEmpty,
            """
            best_effort_refs must stay zero in runtime code:
            \(Self.format(bestEffortRefs))
            """
        )

        let fallbackRefs = try swiftSources(under: Self.productionSourceRoots)
            .flatMap { $0.executableLines(containingAny: ["fallback", "fall back"]) }
        let coreViolations = fallbackRefs.filter { match in
            Self.coreFallbackRoots.contains { match.relativePath.hasPrefix($0) }
                && !Self.allowedBoundaryFallbackFiles.contains(match.relativePath)
        }

        XCTAssertTrue(
            coreViolations.isEmpty,
            """
            silent_core_fallback_refs and named_core_fallback_refs must stay zero. Explicit
            serializer/config boundary fallbacks are tracked separately:
            \(Self.format(coreViolations))
            """
        )
    }

    func testPublicJSONObjectBridgeIsSingleNamedShim() throws {
        let violations = try swiftSources(under: [
            "ButtonHeist/Sources/TheButtonHeist",
            "ButtonHeistCLI/Sources",
            "ButtonHeistMCP/Sources",
        ])
            .filter { source in
                source.contains("JSONSerialization.") || source.contains(publicDictionaryAdapterCall)
            }
            .filter { source in
                source.relativePath != "ButtonHeist/Sources/TheButtonHeist/TheFence/PublicJSONSerializer.swift"
            }

        XCTAssertTrue(
            violations.isEmpty,
            """
            Public JSON object bridging should stay in PublicJSONSerializer. Runtime formatters and adapters should
            consume jsonData() or typed public response models:
            \(violations.map(\.relativePath).sorted().joined(separator: "\n"))
            """
        )
    }

    private static let maxRuntimeOwnerLineCount = 750

    private static let productionSourceRoots = [
        "ButtonHeist/Sources/TheButtonHeist",
        "ButtonHeist/Sources/TheInsideJob",
        "ButtonHeist/Sources/TheScore",
        "ButtonHeistCLI/Sources",
        "ButtonHeistMCP/Sources",
    ]

    private static let coreFallbackRoots = [
        "ButtonHeist/Sources/TheButtonHeist/TheFence",
        "ButtonHeist/Sources/TheInsideJob/TheBrains",
        "ButtonHeist/Sources/TheInsideJob/TheGetaway",
        "ButtonHeist/Sources/TheInsideJob/TheStakeout",
        "ButtonHeist/Sources/TheInsideJob/TheStash",
        "ButtonHeist/Sources/TheInsideJob/TheTripwire",
    ]

    private static let allowedBoundaryTryQuestionFiles: Set<String> = [
        "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+Formatting+Compact+Interface.swift",
        "ButtonHeist/Sources/TheScore/HeistPlayback.swift",
        "ButtonHeist/Sources/TheScore/ScoreDescription.swift",
        "ButtonHeistMCP/Sources/main.swift",
    ]

    private static let allowedBoundaryFallbackFiles: Set<String> = [
        "ButtonHeist/Sources/TheButtonHeist/TheFence/PublicJSONSerializer.swift",
        "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+Formatting+JSON.swift",
        "ButtonHeist/Sources/TheInsideJob/Lifecycle/StartupConfiguration.swift",
    ]

    private static let allowedLargeModelOrCatalogFiles: Set<String> = [
        "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandCatalog.swift",
        "ButtonHeist/Sources/TheScore/AccessibilityTrace+Diff.swift",
        "ButtonHeist/Sources/TheScore/BatchTargets.swift",
        "ButtonHeist/Sources/TheScore/ClientMessages.swift",
        "ButtonHeist/Sources/TheScore/ElementModels.swift",
        "ButtonHeist/Sources/TheScore/ElementObservationModels.swift",
        "ButtonHeist/Sources/TheScore/ServerMessages.swift",
    ]

    private static let allowedUntypedBoundaryFiles: Set<String> = [
        "ButtonHeist/Sources/TheButtonHeist/TheFence/PublicJSONSerializer.swift",
        "ButtonHeist/Sources/TheButtonHeist/TheFence/SchemaValidationError.swift",
        "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandArguments.swift",
        "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+RequestPayload.swift",
        "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence.swift",
        "ButtonHeistCLI/Sources/Commands/GestureCommands.swift",
        "ButtonHeistCLI/Sources/Session/SessionRepl.swift",
        "ButtonHeistCLI/Sources/Support/CLICommandContract.swift",
        "ButtonHeistCLI/Sources/Support/CLIRunner.swift",
        "ButtonHeistCLI/Sources/Support/CLIRequestBuilder.swift",
        "ButtonHeistCLI/Sources/Support/ElementTargetOptions.swift",
    ]

    private static let allowedPlatformDictionaryFiles: Set<String> = [
        "ButtonHeist/Sources/TheButtonHeist/TheBookKeeper/TheBookKeeper.swift",
        "ButtonHeist/Sources/TheInsideJob/Lifecycle/StartupConfiguration.swift",
        "ButtonHeist/Sources/TheInsideJob/Server/TLSIdentity.swift",
        "ButtonHeist/Sources/TheInsideJob/TheStakeout/TheStakeout.swift",
    ]

    private struct SourceFile {
        let relativePath: String
        let contents: String

        var lineCount: Int {
            contents.split(separator: "\n", omittingEmptySubsequences: false).count
        }

        func contains(_ needle: String) -> Bool {
            contents.contains(needle)
        }

        func executableLines(containing needle: String) -> [SourceMatch] {
            executableLines(containingAny: [needle])
        }

        func executableLines(containingAny needles: [String]) -> [SourceMatch] {
            lines().compactMap { line in
                let lowercased = line.text.lowercased()
                guard needles.contains(where: { lowercased.contains($0.lowercased()) }) else {
                    return nil
                }
                return line
            }
        }

        func executableLines(matchingRegex pattern: String) -> [SourceMatch] {
            lines().filter { line in
                line.text.range(of: pattern, options: .regularExpression) != nil
            }
        }

        func hasBoundaryTryQuestionComment(before lineNumber: Int) -> Bool {
            let lowerBound = max(1, lineNumber - 20)
            return contents
                .split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated()
                .contains { offset, line in
                    let candidateLineNumber = offset + 1
                    return candidateLineNumber >= lowerBound
                        && candidateLineNumber < lineNumber
                        && line.contains("Boundary try?")
            }
        }

        private func lines() -> [SourceMatch] {
            contents
                .split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated()
                .compactMap { offset, line in
                    let text = String(line)
                    guard !text.trimmingCharacters(in: .whitespaces).hasPrefix("//") else {
                        return nil
                    }
                    return SourceMatch(
                        relativePath: relativePath,
                        lineNumber: offset + 1,
                        text: text,
                        source: self
                    )
                }
        }
    }

    private struct SourceMatch {
        let relativePath: String
        let lineNumber: Int
        let text: String
        let source: SourceFile
    }

    private func swiftSources(under roots: [String]) throws -> [SourceFile] {
        let rootURL = repositoryRoot()
        let fileManager = FileManager.default
        var files: [SourceFile] = []

        for root in roots {
            let rootPath = rootURL.appendingPathComponent(root).path
            guard let enumerator = fileManager.enumerator(atPath: rootPath) else { continue }

            for case let relative as String in enumerator where relative.hasSuffix(".swift") {
                let path = "\(root)/\(relative)"
                let contents = try String(
                    contentsOf: rootURL.appendingPathComponent(path),
                    encoding: .utf8
                )
                files.append(SourceFile(relativePath: path, contents: contents))
            }
        }

        return files
    }

    private func repositoryRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1 {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("ButtonHeist").path),
               FileManager.default.fileExists(atPath: url.appendingPathComponent("ButtonHeistCLI").path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    private static func format(_ matches: [SourceMatch]) -> String {
        matches
            .map { "\($0.relativePath):\($0.lineNumber): \($0.text.trimmingCharacters(in: .whitespaces))" }
            .sorted()
            .joined(separator: "\n")
    }
}
