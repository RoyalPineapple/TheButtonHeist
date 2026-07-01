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
        #expect(!planningSource.contains("rawStructuredJSONIRFieldNames"))
        #expect(planningSource.contains("public enum HeistPlanRejectedPublicSourceField"))
        #expect(planningSource.contains("public enum HeistPlanSource: Sendable, Equatable"))
        #expect(planningSource.contains("case artifactPath(String)"))
        #expect(planningSource.contains("case inlineDSL(String)"))
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

    @Test func `the fence pending request registry uses one typed response result`() throws {
        let pendingSource = try sourceFile(
            relativePath: "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+PendingRequestTrackers.swift"
        )
        #expect(pendingSource.contains("fileprivate enum PendingResponsePayload: Sendable"))
        #expect(pendingSource.contains("fileprivate struct PendingRequest: Sendable"))
        #expect(pendingSource.contains("let expectedKind: PendingResponseKind"))
        #expect(pendingSource.contains("private var pending: [String: PendingRequest] = [:]"))
        #expect(pendingSource.contains("Result<PendingResponsePayload, Error>"))
        #expect(pendingSource.contains("static func result(from message: ServerMessage) -> Result<PendingResponsePayload, Error>?"))
        #expect(pendingSource.matches(of: #"\bPendingRequest\s*<"#).isEmpty)
        #expect(pendingSource.matches(of: #"\bPendingResponseContinuation\b"#).isEmpty)
        #expect(pendingSource.matches(of: #"\bfunc\s+resolve(Action|Pong|Interface|Screen|HeistExecution)\s*\("#).isEmpty)
        #expect(pendingSource.matches(of: #"\bfunc\s+waitForResponse\s*\("#).isEmpty)
        #expect(!pendingSource.contains("PendingRequestTrackerError"))
        #expect(!FileManager.default.fileExists(
            atPath: repositoryRoot()
                .appendingPathComponent("ButtonHeist/Sources/TheButtonHeist/Support/PendingRequestTracker.swift")
                .path
        ))

        let transportSource = try sourceFile(
            relativePath: "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+TransportWaits.swift"
        )
        #expect(transportSource.matches(of: #"\bfunc\s+sendAndAwaitResponse\s*\("#).isEmpty)
        #expect(transportSource.matches(of: #"\bPendingResponsePayload\b"#).isEmpty)
        #expect(!transportSource.contains("responseTypeMismatchError"))
    }

    @Test func `public and package production APIs do not expose named tuple surfaces`() throws {
        let root = repositoryRoot()
        let productionFiles = try productionSwiftFiles(root: root)
        let namedTupleAPIMatches = try publicOrPackageDeclarationMatches(
            in: productionFiles,
            root: root,
            matching: #"(?:->|:)\s*\((?=[^)\n]*\b[A-Za-z_][A-Za-z0-9_]*\s*:)[^)\n]*\)"#
        )

        #expect(
            namedTupleAPIMatches.isEmpty,
            """
            Public/package production API surfaces should expose named domain types, not named tuples. \
            Local tuple destructuring and private helpers are allowed; public/package declarations are not:
            \(namedTupleAPIMatches.sorted().joined(separator: "\n"))
            """
        )
    }

    @Test func `raw Any is confined to named Foundation boundary concepts and not public APIs`() throws {
        let root = repositoryRoot()
        let productionFiles = try productionSwiftFiles(root: root)
        let rawAnyBoundaryConcepts = [
            SourceBoundaryConcept(
                name: "FoundationInfoPlistBridge",
                relativePath: "ButtonHeist/Sources/TheInsideJob/Lifecycle/StartupConfiguration.swift"
            ),
            SourceBoundaryConcept(
                name: "FoundationFileAttributeDictionary",
                relativePath: "ButtonHeist/Sources/TheButtonHeist/Storage/PrivateStorage.swift"
            ),
        ]

        let anyAPIMatches = try publicOrPackageDeclarationMatches(
            in: productionFiles,
            root: root,
            matching: #"\[String\s*:\s*Any\]|\bAny\b"#
        )

        #expect(
            anyAPIMatches.isEmpty,
            """
            Public/package production APIs should use typed model/runtime pipeline surfaces rather than \
            raw type erasure or untyped Foundation JSON dictionaries. Raw type erasure is only allowed \
            inside named Foundation boundary concepts:
            \(rawAnyBoundaryConcepts.map(\.name).sorted().joined(separator: ", "))
            \(anyAPIMatches.sorted().joined(separator: "\n"))
            """
        )

        let rawAnyMatches = try rawAnyMatchesOutsideBoundaryConcepts(
            in: productionFiles,
            root: root,
            allowedBoundaries: rawAnyBoundaryConcepts
        )

        #expect(
            rawAnyMatches.isEmpty,
            """
            Raw Any in production code should stay inside explicitly named Foundation boundary concepts, \
            not model or runtime pipeline surfaces:
            \(rawAnyMatches.sorted().joined(separator: "\n"))
            """
        )
    }

    @Test func `production result models do not use optional bag success failure payload shape`() throws {
        let root = repositoryRoot()
        let productionFiles = try productionSwiftFiles(root: root)
        let optionalBagMatches = try optionalBagResultStructMatches(in: productionFiles, root: root)

        #expect(
            optionalBagMatches.isEmpty,
            """
            Production result models should encode mutually exclusive states with enums or typed outcomes, \
            not optional bags mixing success/status, errorKind/failure, and payload/evidence stored fields. \
            Decoded boundary models should be named explicitly before adding an exception:
            \(optionalBagMatches.sorted().joined(separator: "\n"))
            """
        )
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

    var singleLineSourceShapeDescription: String {
        split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var prefixBeforeFirstOpeningBrace: String {
        guard let brace = firstIndex(of: "{") else { return self }
        return String(self[..<brace])
    }

    var sourceShapeParenBalance: Int {
        reduce(0) { balance, character in
            switch character {
            case "(":
                return balance + 1
            case ")":
                return max(0, balance - 1)
            default:
                return balance
            }
        }
    }

    func splitIntoNumberedLines() -> [(lineNumber: Int, line: String)] {
        split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { (lineNumber: $0.offset + 1, line: String($0.element)) }
    }

    func removingCommentsAndStringLiteralContents() -> String {
        var result = ""
        var index = startIndex
        var state = SourceLexicalState.code
        while index < endIndex {
            let character = self[index]
            let nextIndex = self.index(after: index)
            let nextCharacter = nextIndex < endIndex ? self[nextIndex] : nil

            switch state {
            case .code:
                if character == "/", nextCharacter == "/" {
                    result.append("  ")
                    index = self.index(after: nextIndex)
                    state = .lineComment
                } else if character == "/", nextCharacter == "*" {
                    result.append("  ")
                    index = self.index(after: nextIndex)
                    state = .blockComment(depth: 1)
                } else if character == #"""# {
                    result.append(character)
                    index = nextIndex
                    state = .string
                } else {
                    result.append(character)
                    index = nextIndex
                }
            case .lineComment:
                if character == "\n" {
                    result.append("\n")
                    state = .code
                } else {
                    result.append(" ")
                }
                index = nextIndex
            case .blockComment(let depth):
                if character == "/", nextCharacter == "*" {
                    result.append("  ")
                    index = self.index(after: nextIndex)
                    state = .blockComment(depth: depth + 1)
                } else if character == "*", nextCharacter == "/" {
                    result.append("  ")
                    index = self.index(after: nextIndex)
                    if depth == 1 {
                        state = .code
                    } else {
                        state = .blockComment(depth: depth - 1)
                    }
                } else {
                    result.append(character == "\n" ? "\n" : " ")
                    index = nextIndex
                }
            case .string:
                if character == "\\" {
                    result.append(" ")
                    if nextIndex < endIndex {
                        result.append(" ")
                        index = self.index(after: nextIndex)
                    } else {
                        index = nextIndex
                    }
                } else if character == #"""# {
                    result.append(character)
                    state = .code
                    index = nextIndex
                } else {
                    result.append(character == "\n" ? "\n" : " ")
                    index = nextIndex
                }
            }
        }
        return result
    }

    func namedDeclarationRanges(named name: String) throws -> [ClosedRange<Int>] {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let declarationRegex = try NSRegularExpression(
            pattern: "\\b(?:typealias|struct|enum|class|actor|protocol)\\s+\(escapedName)\\b"
        )
        let fullRange = NSRange(startIndex..<endIndex, in: self)
        return declarationRegex.matches(in: self, range: fullRange).compactMap { match in
            guard let range = Range(match.range, in: self) else { return nil }
            return declarationLineRange(startingAt: range.lowerBound)
        }
    }

    func structBlocks() throws -> [SourceStructBlock] {
        let regex = try NSRegularExpression(
            pattern: #"(?m)^\s*(?:(?:public|package|internal|fileprivate|private)\s+)?(?:final\s+)?struct\s+([A-Za-z_][A-Za-z0-9_]*)\b"#
        )
        let fullRange = NSRange(startIndex..<endIndex, in: self)
        return regex.matches(in: self, range: fullRange).compactMap { match in
            guard let matchRange = Range(match.range, in: self),
                  let nameRange = Range(match.range(at: 1), in: self),
                  let bodyRange = declarationCharacterRange(startingAt: matchRange.lowerBound)
            else {
                return nil
            }
            return SourceStructBlock(
                name: String(self[nameRange]),
                lineNumber: lineNumber(at: matchRange.lowerBound),
                contents: String(self[bodyRange])
            )
        }
    }

    private func declarationLineRange(startingAt declarationStart: String.Index) -> ClosedRange<Int>? {
        guard let characterRange = declarationCharacterRange(startingAt: declarationStart) else {
            let line = lineNumber(at: declarationStart)
            return line...line
        }
        return lineNumber(at: characterRange.lowerBound)...lineNumber(at: characterRange.upperBound)
    }

    private func declarationCharacterRange(startingAt declarationStart: String.Index) -> Range<String.Index>? {
        guard let openingBrace = self[declarationStart...].firstIndex(of: "{") else {
            return nil
        }
        var depth = 0
        var index = openingBrace
        while index < endIndex {
            switch self[index] {
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    return declarationStart..<self.index(after: index)
                }
            default:
                break
            }
            formIndex(after: &index)
        }
        return declarationStart..<endIndex
    }

    private func lineNumber(at index: String.Index) -> Int {
        self[..<index].reduce(1) { lineNumber, character in
            character == "\n" ? lineNumber + 1 : lineNumber
        }
    }
}

private enum SourceLexicalState {
    case code
    case lineComment
    case blockComment(depth: Int)
    case string
}

private struct SourceStructBlock: Sendable {
    let name: String
    let lineNumber: Int
    let contents: String

    var isResultStateModelCandidate: Bool {
        guard name.contains("Result")
            || name.contains("Outcome")
            || name.contains("Receipt")
            || name.contains("State")
        else {
            return false
        }
        return !name.hasPrefix("Public") && !name.hasSuffix("Projection")
    }

    var storedFieldTypes: [String: String] {
        let pattern = #"^\s*(?:(?:public|package|internal|fileprivate|private)\s+)?(?:let|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([^=\n{]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [:] }
        return contents.split(separator: "\n", omittingEmptySubsequences: false).reduce(into: [:]) { fields, rawLine in
            let line = String(rawLine)
            guard !line.contains("{") else { return }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = regex.firstMatch(in: line, range: range),
                  let nameRange = Range(match.range(at: 1), in: line),
                  let typeRange = Range(match.range(at: 2), in: line)
            else {
                return
            }
            fields[String(line[nameRange])] = String(line[typeRange]).trimmingCharacters(in: .whitespaces)
        }
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

private func productionSwiftFiles(root: URL) throws -> [URL] {
    try swiftFiles(in: root.appendingPathComponent("ButtonHeist/Sources", isDirectory: true))
}

private struct SourceBoundaryConcept: Equatable, Sendable {
    let name: String
    let relativePath: String
}

private struct SourceDeclarationMatch: Hashable, Sendable {
    let relativePath: String
    let lineNumber: Int
    let text: String

    var description: String {
        "\(relativePath):\(lineNumber):\(text)"
    }
}

private func publicOrPackageDeclarationMatches(
    in files: [URL],
    root: URL,
    matching pattern: String
) throws -> Set<String> {
    let regex = try NSRegularExpression(pattern: pattern)
    var matches: Set<String> = []
    for file in files {
        let relativePath = repositoryRelativePath(file, root: root)
        let source = try String(contentsOf: file, encoding: .utf8).removingCommentsAndStringLiteralContents()
        for declaration in publicOrPackageDeclarationSpans(in: source) {
            let range = NSRange(declaration.text.startIndex..<declaration.text.endIndex, in: declaration.text)
            guard regex.firstMatch(in: declaration.text, range: range) != nil else { continue }
            matches.insert(
                SourceDeclarationMatch(
                    relativePath: relativePath,
                    lineNumber: declaration.lineNumber,
                    text: declaration.text.singleLineSourceShapeDescription
                ).description
            )
        }
    }
    return matches
}

private func rawAnyMatchesOutsideBoundaryConcepts(
    in files: [URL],
    root: URL,
    allowedBoundaries: [SourceBoundaryConcept]
) throws -> Set<String> {
    let anyRegex = try NSRegularExpression(pattern: #"\[String\s*:\s*Any\]|\bAny\b"#)
    var matches: Set<String> = []
    for file in files {
        let relativePath = repositoryRelativePath(file, root: root)
        let allowedNames = Set(allowedBoundaries.filter { $0.relativePath == relativePath }.map(\.name))
        let source = try String(contentsOf: file, encoding: .utf8).removingCommentsAndStringLiteralContents()
        let boundaryRanges = try allowedNames.flatMap { name in
            try source.namedDeclarationRanges(named: name)
        }
        for (lineNumber, line) in source.splitIntoNumberedLines() {
            let lineRange = NSRange(line.startIndex..<line.endIndex, in: line)
            guard anyRegex.firstMatch(in: line, range: lineRange) != nil else { continue }
            guard !boundaryRanges.contains(where: { $0.contains(lineNumber) }) else { continue }
            matches.insert("\(relativePath):\(lineNumber):\(line.trimmingCharacters(in: .whitespaces))")
        }
    }
    return matches
}

private func optionalBagResultStructMatches(in files: [URL], root: URL) throws -> Set<String> {
    var matches: Set<String> = []
    for file in files {
        let relativePath = repositoryRelativePath(file, root: root)
        let source = try String(contentsOf: file, encoding: .utf8).removingCommentsAndStringLiteralContents()
        for block in try source.structBlocks() {
            guard block.isResultStateModelCandidate else { continue }
            let storedFields = block.storedFieldTypes
            let hasStatusField = storedFields.keys.contains("success") || storedFields.keys.contains("status")
            let hasFailureField = storedFields.keys.contains("errorKind") || storedFields.keys.contains("failure")
            let hasPayloadField = storedFields.keys.contains("payload") || storedFields.keys.contains("evidence")
            let hasOptionalFailureOrPayload = ["errorKind", "failure", "payload", "evidence"].contains { fieldName in
                storedFields[fieldName]?.contains("?") == true
            }
            guard hasStatusField, hasFailureField, hasPayloadField, hasOptionalFailureOrPayload else { continue }
            matches.insert("\(relativePath):\(block.lineNumber):\(block.name)")
        }
    }
    return matches
}

private struct SourceDeclarationSpan: Sendable {
    let lineNumber: Int
    let text: String
}

private func publicOrPackageDeclarationSpans(in source: String) -> [SourceDeclarationSpan] {
    let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    let accessPattern = #"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:public|package)\s+"#
    let modifierPattern = #"(?:(?:static|class|final|mutating|nonmutating|async|throws)\s+)*"#
    let declarationPattern = accessPattern + modifierPattern + #"(?:func|var|let|subscript|init)\b"#
    var spans: [SourceDeclarationSpan] = []
    var lineIndex = 0
    while lineIndex < lines.count {
        let line = lines[lineIndex]
        if line.range(
            of: declarationPattern,
            options: .regularExpression
        ) != nil {
            let startLine = lineIndex + 1
            var declarationLines = [line]
            var cursor = lineIndex
            let isStoredValueDeclaration = line.range(
                of: #"\b(?:var|let)\b"#,
                options: .regularExpression
            ) != nil
            while !declarationLines.joined(separator: "\n").contains("{"),
                  cursor + 1 < lines.count,
                  declarationLines.count < 20 {
                if isStoredValueDeclaration,
                   declarationLines.joined(separator: "\n").sourceShapeParenBalance == 0 {
                    break
                }
                cursor += 1
                declarationLines.append(lines[cursor])
                if isStoredValueDeclaration,
                   declarationLines.joined(separator: "\n").sourceShapeParenBalance == 0 {
                    break
                }
            }
            let declaration = declarationLines.joined(separator: "\n").prefixBeforeFirstOpeningBrace
            spans.append(SourceDeclarationSpan(lineNumber: startLine, text: declaration))
            lineIndex = cursor
        }
        lineIndex += 1
    }
    return spans
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
