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

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
