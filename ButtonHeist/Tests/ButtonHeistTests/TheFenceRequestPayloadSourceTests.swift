import Foundation
import Testing

@Suite struct TheFenceRequestPayloadSourceTests {

    @Test func `get interface matcher fields are typed at the request boundary`() throws {
        let source = try sourceFile(
            relativePath: "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+RequestPayload+Observation.swift"
        )

        #expect(source.contains("private enum InterfaceElementMatcherField: CaseIterable"))

        for forbidden in [
            #"argumentValues["checks"]"#,
            #"argumentValues["label"]"#,
            #"argumentValues["identifier"]"#,
            #"argumentValues["value"]"#,
            #"argumentValues["traits"]"#,
            #"argumentValues["excludeTraits"]"#,
            #"schemaStringMatches("label")"#,
            #"schemaStringMatches("identifier")"#,
            #"schemaStringMatches("value")"#,
            #"schemaStringArray("traits")"#,
            #"schemaStringArray("excludeTraits")"#,
        ] {
            #expect(
                !source.contains(forbidden),
                "get_interface matcher parsing should use InterfaceElementMatcherField instead of \(forbidden)"
            )
        }
    }

    @Test func `gesture payload parsing does not use retired local decoder helpers`() throws {
        let source = try sourceFile(
            relativePath: "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+RequestPayload+GestureTargets.swift"
        )
        let forbidden = [
            "Swipe" + "Input",
            "Drag" + "Input",
            "Bounded" + "UnitPoint",
            "single" + "ObjectPayloadIntent",
        ]

        for snippet in forbidden {
            #expect(
                !source.contains(snippet),
                "gesture payload parsing should use shared typed payload decoding instead of \(snippet)"
            )
        }
    }

    @Test func `command boundary matcher shortcuts stay behind typed matcher fields`() throws {
        let root = repositoryRoot()
        let fenceFiles = try swiftFiles(
            in: root.appendingPathComponent("ButtonHeist/Sources/TheButtonHeist/TheFence", isDirectory: true)
        )
        let forbiddenPattern =
            #"argumentValues\[[^]]*"(checks|label|identifier|value|traits|excludeTraits)""#
            + #"|schemaStringMatches\s*\(\s*("label"|"identifier"|"value"|[.]label|[.]identifier|[.]value)\s*\)"#
            + #"|schemaStringArray\s*\(\s*("traits"|"excludeTraits"|[.]traits|[.]excludeTraits)\s*\)"#
        let unexpected = try sourceMatches(in: fenceFiles, root: root, pattern: forbiddenPattern)

        #expect(
            unexpected.isEmpty,
            """
            Command-boundary matcher parsing should go through typed matcher-field \
            routing instead of raw shortcut reads:
            \(unexpected.sorted().joined(separator: "\n"))
            """
        )
    }

    @Test func `tooling catalog and schema types are not normal public API`() throws {
        let sourcePaths = [
            "ButtonHeist/Sources/TheButtonHeist/Support/IdleMonitor.swift",
            "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandCatalog.swift",
            "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+ParameterSpec.swift",
            "ButtonHeist/Sources/TheButtonHeist/TheFence/FenceCommandReference.swift",
        ]

        var violations: [String] = []
        for sourcePath in sourcePaths {
            let source = try sourceFile(relativePath: sourcePath)
            violations.append(contentsOf: plainPublicToolingDeclarations(in: source, relativePath: sourcePath))
        }

        #expect(
            violations.isEmpty,
            """
            Tooling-only catalog/schema/reference declarations must be internal or \
            @_spi(ButtonHeistTooling) public, not normal public API:
            \(violations.joined(separator: "\n"))
            """
        )
    }

    @Test func `SPI public surfaces stay explicitly allowlisted`() throws {
        let root = repositoryRoot()
        let files = try [
            "ButtonHeist/Sources",
            "ButtonHeistCLI/Sources",
            "ButtonHeistMCP/Sources",
        ].flatMap { relativeRoot in
            try swiftFiles(in: root.appendingPathComponent(relativeRoot, isDirectory: true))
        }
        let observed = try sourceMatches(
            in: files,
            root: root,
            pattern: #"@_spi\([^)]*\)\s+public\s+"#
        )
        let unexpected = observed.subtracting(allowedSPIPublicDeclarations)

        #expect(
            unexpected.isEmpty,
            "Unexpected SPI-public declarations:\n\(unexpected.sorted().joined(separator: "\n"))"
        )
    }
}

private let allowedSPIPublicDeclarations: Set<String> = [
        allowedSPI(
            "ButtonHeist/Sources/TheButtonHeist/Support/IdleMonitor.swift",
            "@_spi(ButtonHeistTooling) public final class IdleMonitor {"
        ),
        allowedSPI(
            "ButtonHeist/Sources/TheButtonHeist/TheFence/FenceCommandReference.swift",
            "@_spi(ButtonHeistTooling) public enum FenceCommandReference {"
        ),
        allowedSPI(
            "ButtonHeist/Sources/TheButtonHeist/TheFence/FenceResponsePresenter.swift",
            "@_spi(ButtonHeistInternals) public struct FenceResponsePresenter: Sendable {"
        ),
        allowedSPI(
            "ButtonHeist/Sources/TheButtonHeist/TheFence/ProjectionProfile.swift",
            "@_spi(ButtonHeistInternals) public struct ProjectionLimits: Sendable, Equatable {"
        ),
        allowedSPI(
            "ButtonHeist/Sources/TheButtonHeist/TheFence/ProjectionProfile.swift",
            "@_spi(ButtonHeistInternals) public struct ProjectionProfile: Sendable, Equatable {"
        ),
        allowedSPI(
            "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandArguments.swift",
            "@_spi(ButtonHeistTooling) public struct CommandArgumentEnvelope: Sendable {"
        ),
        allowedSPI(
            "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandArguments.swift",
            "@_spi(ButtonHeistTooling) public let argumentValues: [String: HeistValue]"
        ),
        allowedSPI(
            "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandArguments.swift",
            "@_spi(ButtonHeistTooling) public init("
        ),
        allowedSPI(
            "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandCatalog.swift",
            "@_spi(ButtonHeistTooling) public enum FenceCommandFamily: String, Sendable, CaseIterable {"
        ),
        allowedSPI(
            "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandCatalog.swift",
            "@_spi(ButtonHeistTooling) public struct FenceCommandDescriptor: Sendable, Equatable {"
        ),
        allowedSPI(
            "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandCatalog.swift",
            "@_spi(ButtonHeistTooling) public struct FenceCommandProjection: Sendable, Equatable {"
        ),
        allowedSPI(
            "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandCatalog.swift",
            "@_spi(ButtonHeistTooling) public extension TheFence.Command {"
        ),
        allowedSPI(
            "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandRouting.swift",
            "@_spi(ButtonHeistTooling) public struct FenceOperationRoutingError: Error, LocalizedError, Sendable {"
        ),
        allowedSPI(
            "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandRouting.swift",
            "@_spi(ButtonHeistTooling) public let message: String"
        ),
        allowedSPI(
            "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandRouting.swift",
            "@_spi(ButtonHeistTooling) public let details: FailureDetails"
        ),
        allowedSPI(
            "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandRouting.swift",
            "@_spi(ButtonHeistTooling) public init(message: String, details: FailureDetails = FailureDetails(code: .requestInvalid)) {"
        ),
        allowedSPI(
            "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandRouting.swift",
            "@_spi(ButtonHeistTooling) public struct FenceOperationRequest: Sendable {"
        ),
        allowedSPI(
            "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandRouting.swift",
            "@_spi(ButtonHeistTooling) public let command: TheFence.Command"
        ),
        allowedSPI(
            "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandRouting.swift",
            "@_spi(ButtonHeistTooling) public let arguments: TheFence.CommandArgumentEnvelope"
        ),
        allowedSPI(
            "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandRouting.swift",
            "@_spi(ButtonHeistTooling) public init(command: TheFence.Command, arguments: TheFence.CommandArgumentEnvelope) {"
        ),
        allowedSPI(
            "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandRouting.swift",
            "@_spi(ButtonHeistTooling) public extension TheFence.Command {"
        ),
        allowedSPI(
            "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+ParameterSpec.swift",
            "@_spi(ButtonHeistTooling) public struct FenceParameterSpec: Sendable, Equatable {"
        ),
        allowedSPI(
            "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+ParameterSpec.swift",
            "@_spi(ButtonHeistTooling) public struct FenceParameterKey: RawRepresentable, Hashable, Sendable {"
        ),
        allowedSPI(
            "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+ParameterSpec.swift",
            "@_spi(ButtonHeistTooling) public extension FenceParameterKey {"
        ),
        allowedSPI(
            "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+ParameterSpec.swift",
            "@_spi(ButtonHeistTooling) public enum MCPExposure: Sendable, Equatable {"
        ),
        allowedSPI(
            "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+ParameterSpec.swift",
            "@_spi(ButtonHeistTooling) public struct MCPToolAnnotationSpec: Sendable, Equatable {"
        ),
        allowedSPI(
            "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+ParameterSpec.swift",
            "@_spi(ButtonHeistTooling) public extension FenceParameterSpec.ParamType {"
        ),
        allowedSPI(
            "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+ParameterSpec.swift",
            "@_spi(ButtonHeistTooling) public extension FenceCommandDescriptor {"
        ),
        allowedSPI(
            "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+ParameterSpec.swift",
            "@_spi(ButtonHeistTooling) public extension FenceParameterSpec {"
        ),
        allowedSPI(
            "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+ParameterSpec.swift",
            "@_spi(ButtonHeistTooling) public enum CLIExposure: Sendable, Equatable {"
        ),
        allowedSPI(
            "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence.swift",
            "@_spi(ButtonHeistTooling) public func execute(_ request: FenceOperationRequest) async throws -> FenceResponse {"
        ),
]

private func allowedSPI(_ path: String, _ declaration: String) -> String {
    "\(path):\(declaration)"
}

private func plainPublicToolingDeclarations(in source: String, relativePath: String) -> [String] {
    let forbiddenPrefixes = [
        "public final class IdleMonitor",
        "public struct FenceCommandDescriptor",
        "public struct FenceCommandProjection",
        "public enum FenceCommandFamily",
        "public struct FenceParameterSpec",
        "public struct FenceParameterKey",
        "public enum MCPExposure",
        "public struct MCPToolAnnotationSpec",
        "public enum CLIExposure",
        "public enum FenceCommandReference",
        "public extension TheFence.Command",
        "public extension FenceParameterKey",
        "public extension FenceParameterSpec",
        "public extension FenceParameterSpec.ParamType",
        "public extension FenceCommandDescriptor",
    ]

    return source
        .split(separator: "\n", omittingEmptySubsequences: false)
        .enumerated()
        .compactMap { offset, line -> String? in
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            guard forbiddenPrefixes.contains(where: { trimmedLine.hasPrefix($0) }) else {
                return nil
            }
            return "\(relativePath):\(offset + 1): \(trimmedLine)"
        }
}

private func sourceFile(relativePath: String) throws -> String {
    try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
}

private func swiftFiles(in root: URL) throws -> [URL] {
    let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey]
    guard let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: Array(resourceKeys),
        options: [.skipsHiddenFiles]
    ) else {
        return []
    }

    var files: [URL] = []
    for case let url as URL in enumerator {
        if url.lastPathComponent == ".build" || url.lastPathComponent == "Derived" {
            enumerator.skipDescendants()
            continue
        }
        let values = try url.resourceValues(forKeys: resourceKeys)
        if values.isRegularFile == true, url.pathExtension == "swift" {
            files.append(url)
        }
    }
    return files
}

private func sourceMatches(in files: [URL], root: URL, pattern: String) throws -> Set<String> {
    var matches: Set<String> = []
    for file in files {
        let relativePath = repositoryRelativePath(file, root: root)
        for line in try sourceLines(in: file) where line.range(of: pattern, options: .regularExpression) != nil {
            matches.insert("\(relativePath):\(line.trimmingCharacters(in: .whitespaces))")
        }
    }
    return matches
}

private func sourceLines(in file: URL) throws -> [String] {
    try String(contentsOf: file, encoding: .utf8)
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map(String.init)
}

private func repositoryRelativePath(_ file: URL, root: URL) -> String {
    let rootPath = root.standardizedFileURL.path
    let filePath = file.standardizedFileURL.path
    guard filePath.hasPrefix(rootPath + "/") else {
        return file.path
    }
    return String(filePath.dropFirst(rootPath.count + 1))
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
