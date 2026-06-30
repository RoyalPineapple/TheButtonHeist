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
            "decode" + "GestureTarget(",
        ]

        for snippet in forbidden {
            #expect(
                !source.contains(snippet),
                "gesture payload parsing should use shared typed payload decoding instead of \(snippet)"
            )
        }

        #expect(source.contains("private protocol PublicGestureTarget"))
        #expect(source.contains("static func gesturePayloadExpectation("))

        let duplicatedElementTargetExpectationPatterns = [
            #"prefixed\s*\(\s*"elementDirection\.element""#,
            #"prefixed\s*\(\s*"elementUnitPoints\.element""#,
            #"prefixed\s*\(\s*"elementToPoint\.element""#,
        ]
        for pattern in duplicatedElementTargetExpectationPatterns {
            #expect(
                source.range(of: pattern, options: .regularExpression) == nil,
                "gesture payload expectations should route element target schemas through gesturePayloadExpectation"
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

    @Test func `request payload argument accessors use typed parameter keys`() throws {
        let root = repositoryRoot()
        let fenceFiles = try swiftFiles(
            in: root.appendingPathComponent("ButtonHeist/Sources/TheButtonHeist/TheFence", isDirectory: true)
        ).filter {
            $0.lastPathComponent.hasPrefix("TheFence+RequestPayload")
                || $0.lastPathComponent == "TheFence+RequestTargetDecoding.swift"
        }
        let forbiddenPattern =
            #"\b(schemaInteger|requiredSchemaInteger|schemaNonNegativeInteger|schemaString|requiredSchemaString|"#
            + #"schemaStringMatch|schemaStringMatches|schemaBoolean|schemaNumber|requiredSchemaNumber|"#
            + #"schemaStringArray|schemaObjectArray|requiredSchemaObjectArray|schemaDictionary|"#
            + #"schemaEnum|requiredSchemaEnum|nonEmptyString|optionalNonEmptyString|optionalContainerName|"#
            + #"field|observedDescription)\s*\(\s*\"[A-Za-z_][A-Za-z0-9_]*\""#
        let unexpected = try sourceMatches(in: fenceFiles, root: root, pattern: forbiddenPattern)

        #expect(
            unexpected.isEmpty,
            """
            Request payload command-argument access should use FenceParameterKey \
            overloads instead of raw string keys:
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

    @Test func `fence parameter specs store typed schema until projection`() throws {
        let source = try sourceFile(
            relativePath: "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+ParameterSpec.swift"
        )

        #expect(source.contains("let jsonSchema: FenceParameterJSONSchema"))
        #expect(source.contains("indirect enum FenceParameterJSONSchema: Sendable, Equatable"))
        #expect(source.contains("var heistValue: HeistValue"))

        for forbidden in [
            "jsonSchemaProperty: HeistValue",
            "var schema: [String: HeistValue]",
            "let schema: [String: HeistValue]",
        ] {
            #expect(
                !source.contains(forbidden),
                "Fence parameter specs should keep typed schema nodes until projection, not \(forbidden)"
            )
        }
    }

    @Test func `doc reference and projection implementation controls stay out of public SPI`() throws {
        let referenceSource = try sourceFile(
            relativePath: "ButtonHeist/Sources/TheButtonHeist/TheFence/FenceCommandReference.swift"
        )
        #expect(referenceSource.contains("package enum FenceCommandReference"))
        #expect(!referenceSource.contains("@_spi(ButtonHeistTooling) public enum FenceCommandReference"))
        #expect(!referenceSource.contains("public enum FenceCommandReference"))
        #expect(!referenceSource.contains("public static func commandMarkdown"))
        #expect(!referenceSource.contains("public static func mcpMarkdown"))

        let projectionSource = try sourceFile(
            relativePath: "ButtonHeist/Sources/TheButtonHeist/TheFence/ProjectionProfile.swift"
        )
        #expect(projectionSource.contains("struct ProjectionLimits: Sendable, Equatable"))
        #expect(projectionSource.contains("@_spi(ButtonHeistInternals) public struct ProjectionProfile"))
        for forbidden in [
            "@_spi(ButtonHeistInternals) public struct ProjectionLimits",
            "public struct ProjectionLimits",
            "public enum Kind",
            "public let kind",
            "public let limits",
            "public init(kind: Kind, limits: ProjectionLimits)",
        ] {
            #expect(
                !projectionSource.contains(forbidden),
                "Projection internals should not be exported through SPI/public API: \(forbidden)"
            )
        }

        let presenterSource = try sourceFile(
            relativePath: "ButtonHeist/Sources/TheButtonHeist/TheFence/FenceResponsePresenter.swift"
        )
        #expect(!presenterSource.contains("public let profile: ProjectionProfile"))
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

    @Test func `CLI command requests stay behind typed boundary containers`() throws {
        let root = repositoryRoot()
        let commandFiles = try swiftFiles(
            in: root.appendingPathComponent("ButtonHeistCLI/Sources/Commands", isDirectory: true)
        )
        let forbiddenPattern = [
            #"CLIRequestParameters\s*=\s*\["#,
            #"\[FenceParameterKey\s*:\s*HeistValue\]"#,
            #"\[String\s*:\s*HeistValue\]"#,
            #"\.object\s*\(\s*Dictionary"#,
            #"\.object\s*\(\s*\["#,
        ].joined(separator: "|")
        let unexpected = try sourceMatches(in: commandFiles, root: root, pattern: forbiddenPattern)

        #expect(
            unexpected.isEmpty,
            """
            CLI command adapters should build request arguments through \
            CLIRequestParameters/CLIRequestObject instead of ad hoc maps:
            \(unexpected.sorted().joined(separator: "\n"))
            """
        )

        let contract = try sourceFile(relativePath: "ButtonHeistCLI/Sources/Support/CLICommandContract.swift")
        #expect(contract.contains("struct CLIRequestParameters:"))
        #expect(contract.contains("struct CLIRequestObject:"))
        #expect(!contract.contains("typealias CLIRequestParameters"))
    }

    @Test func `CLI gesture payloads stay named typed envelopes`() throws {
        let source = try sourceFile(relativePath: "ButtonHeistCLI/Sources/Commands/GestureCommands.swift")

        #expect(source.contains("struct CLIGesturePayload:"))
        #expect(source.contains("static func elementDirection("))
        #expect(source.contains("static func pointToPoint("))

        for forbidden in [
            "objects: [(FenceParameterKey, [FenceParameterKey: HeistValue]?)]",
            "static func valueObject",
            "static func pointObject",
            "static func requiredPointObject",
        ] {
            #expect(
                !source.contains(forbidden),
                "gesture commands should use named typed payload envelopes instead of \(forbidden)"
            )
        }
    }

    @Test func `MCP raw Value maps stay at input preflight boundary`() throws {
        let root = repositoryRoot()
        let mcpFiles = try swiftFiles(
            in: root.appendingPathComponent("ButtonHeistMCP/Sources", isDirectory: true)
        )
        let rawValueMapMatches = try sourceMatches(
            in: mcpFiles,
            root: root,
            pattern: #"\[String\s*:\s*Value\]"#
        )
        let unexpectedRawValueMaps = rawValueMapMatches.filter {
            !$0.hasPrefix("ButtonHeistMCP/Sources/MCPArgumentInputPreflight.swift:typealias MCPRawArgumentObject")
        }

        #expect(
            unexpectedRawValueMaps.isEmpty,
            """
            Raw MCP Value maps should be named at MCPArgumentInputPreflight and \
            not leak deeper into request routing:
            \(unexpectedRawValueMaps.sorted().joined(separator: "\n"))
            """
        )

        let preflight = try sourceFile(relativePath: "ButtonHeistMCP/Sources/MCPArgumentInputPreflight.swift")
        #expect(preflight.contains("let arguments: TheFence.CommandArgumentEnvelope"))
        #expect(preflight.contains("static func commandEnvelope("))
        #expect(!preflight.contains("let arguments: MCPToolArguments"))
        #expect(!preflight.contains("static func heistValues(_ arguments: MCPRawArgumentObject?) throws -> [String: HeistValue]"))

        let main = try sourceFile(relativePath: "ButtonHeistMCP/Sources/main.swift")
        #expect(!main.contains("request.arguments.commandEnvelope"))
    }
}

private let allowedSPIPublicDeclarations: Set<String> = [
        allowedSPI(
            "ButtonHeist/Sources/TheButtonHeist/Support/IdleMonitor.swift",
            "@_spi(ButtonHeistTooling) public final class IdleMonitor {"
        ),
        allowedSPI(
            "ButtonHeist/Sources/TheButtonHeist/TheFence/FenceResponsePresenter.swift",
            "@_spi(ButtonHeistInternals) public struct FenceResponsePresenter: Sendable {"
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
