import XCTest

final class CodebaseBoundaryGuardTests: XCTestCase {
    private let publicDictionaryAdapterCall = "json" + "Dict("

    func testRawCommandPayloadDictionariesStayAtNamedBoundaries() throws {
        let violations = try swiftSources(under: [
            "ButtonHeist/Sources/TheButtonHeist",
            "ButtonHeist/Sources/TheInsideJob",
            "ButtonHeist/Sources/TheScore",
            "ButtonHeistCLI/Sources",
            "ButtonHeistMCP/Sources",
        ])
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

        func contains(_ needle: String) -> Bool {
            contents.contains(needle)
        }
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
}
