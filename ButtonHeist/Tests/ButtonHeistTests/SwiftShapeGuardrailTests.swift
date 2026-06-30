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

    @Test func `handoff receive callbacks collapse into device receive events`() throws {
        let connectionSource = try sourceFile(
            relativePath: "ButtonHeist/Sources/TheButtonHeist/TheHandoff/DeviceConnection.swift"
        )
        #expect(connectionSource.contains("case received(DeviceReceiveEvent, connection: NWConnection)"))
        #expect(connectionSource.matches(
            of: #"\bcase\s+received\s*\(\s*content\s*:\s*Data\?"#,
            options: [.dotMatchesLineSeparators]
        ).isEmpty)

        let receivingSource = try sourceFile(
            relativePath: "ButtonHeist/Sources/TheButtonHeist/TheHandoff/DeviceConnectionReceiving.swift"
        )
        #expect(receivingSource.contains("enum DeviceReceiveEvent"))
        #expect(receivingSource.contains("func handleReceive(_ event: DeviceReceiveEvent, connection: NWConnection)"))

        let rawReceiveHandlerMatches = receivingSource.matches(
            of: #"\bfunc\s+handleReceive\s*\(\s*content\s*:\s*Data\?\s*,\s*isComplete\s*:\s*Bool\s*,\s*error\s*:\s*NWError\?"#,
            options: [.dotMatchesLineSeparators]
        )
        #expect(
            rawReceiveHandlerMatches.isEmpty,
            """
            DeviceConnection receive handling should accept DeviceReceiveEvent, not independent optional callback state:
            \(rawReceiveHandlerMatches.sorted().joined(separator: "\n"))
            """
        )
    }

    @Test func `storage cleanup results expose only outcome shaped construction`() throws {
        let storageCleanupSource = try sourceFile(
            relativePath: "ButtonHeist/Sources/TheButtonHeist/Storage/StorageCleanup.swift"
        )
        #expect(storageCleanupSource.contains("private enum Outcome"))
        #expect(storageCleanupSource.contains("private init(operation: StorageCleanupOperation, path: String?, outcome: Outcome)"))

        let root = repositoryRoot()
        let guardedFiles = try swiftFiles(
            in: root.appendingPathComponent("ButtonHeist", isDirectory: true)
        ).filter {
            repositoryRelativePath($0, root: root) != "ButtonHeist/Sources/TheButtonHeist/Storage/StorageCleanup.swift"
        }
        let directInitializerMatches = try sourceMatches(
            in: guardedFiles,
            root: root,
            pattern: #"StorageCleanupResult\s*\(\s*operation\s*:"#
        )

        #expect(
            directInitializerMatches.isEmpty,
            """
            StorageCleanupResult should be constructed through success/failure factories outside StorageCleanup.swift:
            \(directInitializerMatches.sorted().joined(separator: "\n"))
            """
        )
    }

    @Test func `plan source admission request carries only public source choices`() throws {
        let planningSource = try sourceFile(
            relativePath: "ButtonHeist/Sources/ThePlans/HeistPlanning.swift"
        )
        let rawIRAdmissionFields = planningSource.matches(
            of: #"\bstruct\s+HeistPlanSourceAdmissionRequest\b(?:(?!^\s*}$).)*\brawStructuredJSONIRFields\b"#,
            options: [.dotMatchesLineSeparators, .anchorsMatchLines]
        )

        #expect(
            rawIRAdmissionFields.isEmpty,
            """
            HeistPlanSourceAdmissionRequest should model normal public source choices only. \
            Boundary raw-IR rejection/diagnostics may still validate rawStructuredJSONIRFields \
            outside the admission request shape:
            \(rawIRAdmissionFields.sorted().joined(separator: "\n"))
            """
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

    @Test func `the fence projections model mutually exclusive state with enums`() throws {
        let deltaProjectionSource = try sourceFile(
            relativePath: "ButtonHeist/Sources/TheButtonHeist/TheFence/DeltaProjection.swift"
        )
        #expect(deltaProjectionSource.contains("enum DeltaProjection: Sendable"))
        #expect(deltaProjectionSource.contains("case elementsChanged(DeltaElementsChangedProjection)"))
        #expect(deltaProjectionSource.contains("case screenChanged(DeltaScreenChangedProjection)"))
        #expect(!deltaProjectionSource.contains("struct DeltaProjection: Sendable"))
        #expect(deltaProjectionSource.matches(of: #"(?m)^\s*let\s+kind\s*:\s*DeltaProjectionKind\b"#).isEmpty)
        #expect(deltaProjectionSource.matches(of: #"(?m)^\s*let\s+edits\s*:\s*DeltaEditsProjection[?]"#).isEmpty)
        #expect(deltaProjectionSource.matches(of: #"(?m)^\s*let\s+screen\s*:\s*DeltaScreenProjection[?]"#).isEmpty)

        #expect(deltaProjectionSource.contains("enum ScreenshotProjectionStorage: Sendable"))
        #expect(deltaProjectionSource.contains("case artifact(path: String)"))
        #expect(deltaProjectionSource.contains("case inlinePNG(String)"))
        #expect(deltaProjectionSource.matches(of: #"(?m)^\s*let\s+pngData\s*:\s*String[?]"#).isEmpty)
        #expect(deltaProjectionSource.matches(of: #"(?m)^\s*let\s+path\s*:\s*String[?]"#).isEmpty)

        let responseModelSource = try sourceFile(
            relativePath: "ButtonHeist/Sources/TheButtonHeist/TheFence/FenceResponseModels.swift"
        )
        #expect(responseModelSource.contains("public enum SessionConnectionState: Sendable, Equatable"))
        #expect(responseModelSource.contains("public let state: SessionConnectionState"))
        #expect(responseModelSource.matches(of: #"(?m)^\s*public\s+let\s+connected\s*:\s*Bool\b"#).isEmpty)
        #expect(responseModelSource.matches(of: #"(?m)^\s*public\s+let\s+phase\s*:\s*SessionConnectionPhase\b"#).isEmpty)

        let fenceSource = try sourceFile(
            relativePath: "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence.swift"
        )
        #expect(fenceSource.contains("let state: SessionConnectionState"))
        #expect(fenceSource.matches(of: #"(?m)^\s*let\s+connected\s*:\s*Bool\b"#).isEmpty)
        #expect(fenceSource.matches(of: #"(?m)^\s*let\s+phase\s*:\s*SessionConnectionPhase\b"#).isEmpty)
    }
}

private extension String {
    func matches(
        of pattern: String,
        options: NSRegularExpression.Options = []
    ) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
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
