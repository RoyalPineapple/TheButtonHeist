import Foundation
import Testing

@Suite struct SwiftShapeGuardrailTests {

    @Test func `the inside job container traversal uses named semantic container entries`() throws {
        let screenSource = try sourceFile(
            relativePath: "ButtonHeist/Sources/TheInsideJob/TheStash/Screen.swift"
        )
        #expect(screenSource.contains("var orderedContainers: [SemanticScreen.Container]"))

        let navigationSource = try sourceFile(
            relativePath: "ButtonHeist/Sources/TheInsideJob/TheBrains/Navigation.swift"
        )
        #expect(navigationSource.contains("mutating func addPendingContainers(_ containers: [SemanticScreen.Container])"))

        let semanticExplorationSource = try sourceFile(
            relativePath: "ButtonHeist/Sources/TheInsideJob/TheBrains/Navigation+SemanticExploration.swift"
        )
        #expect(semanticExplorationSource.contains("mutating func addDiscoveredContainers(_ containers: [SemanticScreen.Container])"))

        let explorationScanningSource = try sourceFile(
            relativePath: "ButtonHeist/Sources/TheInsideJob/TheBrains/Navigation+ExplorationScanning.swift"
        )
        #expect(
            explorationScanningSource.matches(
                of: #"for\s+semanticContainer\s*:\s*SemanticScreen[.]Container"#
            ).count == 1
        )
        #expect(explorationScanningSource.contains("private func sortedPendingContainers(in exploration: SemanticExploration) -> [SemanticScreen.Container]"))

        let root = repositoryRoot()
        let insideJobFiles = try swiftFiles(
            in: root.appendingPathComponent("ButtonHeist/Sources/TheInsideJob", isDirectory: true)
        )
        let tupleContainerPathPattern = [
            #"\[\s*\(\s*container\s*:\s*AccessibilityContainer\s*,\s*path\s*:\s*TreePath\s*\)\s*\]"#,
            #"\[\s*\(\s*path\s*:\s*TreePath\s*,\s*container\s*:\s*AccessibilityContainer\s*\)\s*\]"#,
            #"\[\s*\(\s*AccessibilityContainer\s*,\s*TreePath\s*\)\s*\]"#,
            #"\[\s*\(\s*TreePath\s*,\s*AccessibilityContainer\s*\)\s*\]"#,
        ].joined(separator: "|")
        let tupleContainerPathMatches = try sourceMatches(
            in: insideJobFiles,
            root: root,
            pattern: tupleContainerPathPattern
        )

        #expect(
            tupleContainerPathMatches.isEmpty,
            """
            TheInsideJob container path APIs should pass named SemanticScreen.Container \
            values, not tuple pairs:
            \(tupleContainerPathMatches.sorted().joined(separator: "\n"))
            """
        )
    }

    @Test func `the inside job reuses the score node path traversal`() throws {
        let root = repositoryRoot()
        let insideJobFiles = try swiftFiles(
            in: root.appendingPathComponent("ButtonHeist/Sources/TheInsideJob", isDirectory: true)
        )
        let localNodeTraversalMatches = try sourceMatches(
            in: insideJobFiles,
            root: root,
            pattern: #"func\s+node\s*\(\s*at\s+path\s*:\s*TreePath"#
        )

        #expect(
            localNodeTraversalMatches.isEmpty,
            """
            TheInsideJob should call the centralized TheScore AccessibilityHierarchy.node(at:) \
            helpers instead of carrying local traversal copies:
            \(localNodeTraversalMatches.sorted().joined(separator: "\n"))
            """
        )

        let traversalSource = try sourceFile(
            relativePath: "ButtonHeist/Sources/TheScore/AccessibilityHierarchy+Traversal.swift"
        )
        #expect(traversalSource.contains("public extension AccessibilityHierarchy"))
        #expect(traversalSource.contains("public extension Array where Element == AccessibilityHierarchy"))

        let centralizedDefinitions = traversalSource.matches(
            of: #"func\s+node\s*\(\s*at\s+path\s*:\s*TreePath"#
        )
        #expect(
            centralizedDefinitions.count == 2,
            "TheScore should own exactly the single-node and forest node(at:) traversal helpers"
        )
    }

    @Test func `public action payload projections explicitly surface screenshot and heist execution data`() throws {
        let actionProjectionSource = try sourceFile(
            relativePath: "ButtonHeist/Sources/TheButtonHeist/TheFence/ActionProjection.swift"
        )
        #expect(actionProjectionSource.contains("case screenshot(width: Double, height: Double)"))
        #expect(actionProjectionSource.contains("case heistExecutionStepCount(Int)"))
        #expect(actionProjectionSource.contains("case .screenshot(let screen):"))
        #expect(actionProjectionSource.contains("payload = .screenshot(width: screen.width, height: screen.height)"))
        #expect(actionProjectionSource.contains("case .heistExecution(let heist):"))
        #expect(actionProjectionSource.contains("payload = .heistExecutionStepCount(heist.steps.count)"))
        #expect(!actionProjectionSource.matchesCaseBody(#"screenshot"#, containing: #"payload\s*=\s*[.]none"#))
        #expect(!actionProjectionSource.matchesCaseBody(#"heistExecution"#, containing: #"payload\s*=\s*[.]none"#))

        let actionJSONSource = try sourceFile(
            relativePath: "ButtonHeist/Sources/TheButtonHeist/TheFence/FenceJSON+Action.swift"
        )
        #expect(actionJSONSource.contains("case screenshot(PublicScreenshotResult)"))
        #expect(actionJSONSource.contains("case heistExecution(PublicHeistExecutionActionResult)"))
        #expect(actionJSONSource.contains("case .screenshot(let width, let height):"))
        #expect(actionJSONSource.contains("self = .screenshot(PublicScreenshotResult(width: width, height: height))"))
        #expect(actionJSONSource.contains("case .heistExecutionStepCount(let stepCount):"))
        #expect(actionJSONSource.contains("self = .heistExecution(PublicHeistExecutionActionResult(stepCount: stepCount))"))
        #expect(actionJSONSource.contains("try container.encode(screenshot, forKey: .screenshot)"))
        #expect(actionJSONSource.contains("try container.encode(heistExecution, forKey: .heistExecution)"))
        #expect(!actionJSONSource.matchesCaseBody(#"screenshot"#, containing: #"break"#))
        #expect(!actionJSONSource.matchesCaseBody(#"heistExecution"#, containing: #"break"#))
    }
}

private extension String {
    func matches(of pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let fullRange = NSRange(startIndex..<endIndex, in: self)
        return regex.matches(in: self, range: fullRange).compactMap { match in
            Range(match.range, in: self).map { String(self[$0]) }
        }
    }

    func matchesCaseBody(_ caseNamePattern: String, containing bodyPattern: String) -> Bool {
        let pattern = #"case\s+[.]"# + caseNamePattern + #"\b(?:(?!\n\s*case\s+[.]).)*"# + bodyPattern
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return false
        }
        return regex.firstMatch(in: self, range: NSRange(startIndex..<endIndex, in: self)) != nil
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
