import Foundation
import Testing

@Suite struct MCPValueBridgeSourceShapeTests {

    @Test func `recursive MCP value conversion stays inside MCPValueBridge`() throws {
        let bridgeSource = try sourceFile(relativePath: "ButtonHeistMCP/Sources/MCPValueBridge.swift")
        #expect(bridgeSource.contains("enum MCPValueBridge"))
        #expect(bridgeSource.contains("static func commandEnvelope(from arguments: MCPRawArgumentObject?) throws -> TheFence.CommandArgumentEnvelope"))
        #expect(bridgeSource.contains("static func value(from heistValue: HeistValue) -> Value"))
        #expect(bridgeSource.contains("static func heistValue(from value: Value) throws -> HeistValue"))
        #expect(bridgeSource.contains("static func value(decodingJSONData data: Data) throws -> Value"))
        #expect(bridgeSource.contains("static func jsonValueNode(_ value: Value) -> PublicJSONValueNode<Value>"))

        let root = repositoryRoot()
        let mcpSourceFiles = try swiftFiles(
            in: root.appendingPathComponent("ButtonHeistMCP/Sources", isDirectory: true)
        )
            .filter { $0.lastPathComponent != "MCPValueBridge.swift" }

        let forbiddenPatterns = [
            SourcePattern(
                label: "MCP Value array conversion",
                pattern: #"return\s+[.]array\s*\(\s*(try\s+)?values[.]map"#
            ),
            SourcePattern(
                label: "MCP Value object conversion",
                pattern: #"return\s+[.]object\s*\(\s*(try\s+)?object[.]mapValues"#
            ),
            SourcePattern(
                label: "recursive HeistValue conversion",
                pattern: #"mapValues\s*\{\s*try\s+heistValue\s*\("#
            ),
            SourcePattern(
                label: "recursive MCP Value conversion",
                pattern: #"mapValues\s*\{\s*self[.]value\s*\("#
            ),
            SourcePattern(
                label: "direct JSON-to-MCP Value decoding",
                pattern: #"JSONDecoder\s*\(\s*\)[.]decode\s*\(\s*Value[.]self"#
            ),
            SourcePattern(
                label: "direct public JSON preflight over MCP Value",
                pattern: #"PublicJSONValuePreflight[.]validateObject"#
            ),
            SourcePattern(
                label: "direct MCP Value node bridge",
                pattern: #"PublicJSONValueNode\s*<\s*Value\s*>"#
            ),
        ]
        let violations = try sourceMatches(
            in: mcpSourceFiles,
            root: root,
            patterns: forbiddenPatterns
        )

        #expect(
            violations.isEmpty,
            """
            Recursive MCP SDK Value conversion should stay centralized in MCPValueBridge:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    @Test func `MCP call sites route through bridge conversion entrypoints`() throws {
        let toolDefinitions = try sourceFile(relativePath: "ButtonHeistMCP/Sources/ToolDefinitions.swift")
        #expect(toolDefinitions.contains("MCPValueBridge.value(from: descriptor.inputJSONSchema)"))

        let preflight = try sourceFile(relativePath: "ButtonHeistMCP/Sources/MCPArgumentInputPreflight.swift")
        #expect(preflight.contains("typealias MCPRawArgumentObject = [String: Value]"))
        #expect(preflight.contains("try MCPValueBridge.commandEnvelope(from: arguments)"))
        #expect(!preflight.contains("static func heistValue(from value: Value)"))

        let main = try sourceFile(relativePath: "ButtonHeistMCP/Sources/main.swift")
        #expect(main.contains("MCPValueBridge.structuredContent(for: response, presenter: presenter)"))
        #expect(main.contains("MCPValueBridge.structuredErrorValue(failure, presenter: presenter)"))
        #expect(!main.contains("JSONDecoder().decode(Value.self"))
    }
}

private struct SourcePattern {
    let label: String
    let pattern: String
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

private func sourceMatches(in files: [URL], root: URL, patterns: [SourcePattern]) throws -> Set<String> {
    var matches: Set<String> = []
    for file in files {
        let relativePath = repositoryRelativePath(file, root: root)
        for line in try sourceLines(in: file) {
            for sourcePattern in patterns where line.range(of: sourcePattern.pattern, options: .regularExpression) != nil {
                matches.insert("\(relativePath):\(sourcePattern.label):\(line.trimmingCharacters(in: .whitespaces))")
            }
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
}
