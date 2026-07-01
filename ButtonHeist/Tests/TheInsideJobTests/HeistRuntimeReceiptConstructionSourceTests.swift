import Foundation
import Testing

@Suite struct HeistRuntimeReceiptConstructionSourceTests {
    @Test func `runtime action results use builders or factories`() throws {
        let offenders = try receiptSourceFiles(relativeRoot: "ButtonHeist/Sources/TheInsideJob")
            .filter { try receiptSourceContains(#"ActionResult\s*\(\s*success\s*:"#, in: $0.contents) }
            .map(\.relativePath)

        #expect(offenders.isEmpty, "Raw ActionResult(success:) construction remains in runtime sources: \(offenders)")
    }

    @Test func `heist step result construction stays behind receipt helpers`() throws {
        let helperPath = "ButtonHeist/Sources/TheInsideJob/TheBrains/TheBrains+HeistReceiptConstruction.swift"
        let helperSource = try receiptSourceFile(relativePath: helperPath)
        let nonHelperOffenders = try receiptSourceFiles(relativeRoot: "ButtonHeist/Sources/TheInsideJob/TheBrains")
            .filter { $0.relativePath != helperPath }
            .filter { try receiptSourceContains(#"\bHeistExecutionStepResult\s*\("#, in: $0.contents) }
            .map(\.relativePath)

        #expect(nonHelperOffenders.isEmpty, "Direct HeistExecutionStepResult construction should stay in \(helperPath): \(nonHelperOffenders)")
        #expect(
            try receiptSourceOccurrenceCount(#"\bHeistExecutionStepResult\s*\("#, in: helperSource) == 0,
            "Receipt helper should use the typed public step factories, not raw HeistExecutionStepResult construction"
        )
        #expect(
            !helperSource.contains("private func heistReceipt("),
            "Runtime receipt construction should not route through a generic status/evidence/failure funnel"
        )
        #expect(helperSource.contains("return .passed("))
        #expect(helperSource.contains("return .failed("))
        #expect(helperSource.contains(".skipped("))
    }

    @Test func `heist receipt outcomes are typed before step projection`() throws {
        let helperSource = try receiptSourceFile(
            relativePath: "ButtonHeist/Sources/TheInsideJob/TheBrains/TheBrains+HeistReceiptConstruction.swift"
        )
        let genericReceiptParameters = try receiptSourceLines(
            matching: #"\b(status\s+requestedStatus|requestedStatus)\s*:\s*HeistExecutionStepStatus\?|\bevidence\s*:\s*HeistStepEvidence\?"#,
            in: helperSource
        )
        #expect(
            genericReceiptParameters.isEmpty,
            """
            Runtime receipt helpers should expose typed receipt-specific evidence/status \
            decisions instead of generic status or erased optional evidence parameters:
            \(genericReceiptParameters.joined(separator: "\n"))
            """
        )
        #expect(
            helperSource.contains("enum HeistReceiptChildren"),
            "Runtime receipt construction should classify child subtrees with a typed child execution reducer"
        )
        #expect(
            helperSource.contains("enum HeistReceiptOutcome"),
            "Runtime receipt construction should project explicit receipt outcomes, not parallel optionals"
        )
        #expect(
            helperSource.contains("enum HeistReceiptCompletedOutcome"),
            "Completed-child receipt state should be typed before it is reduced into a step outcome"
        )
        #expect(
            helperSource.contains("completedOutcome: HeistReceiptCompletedOutcome = .passed"),
            "Receipt outcomes should reduce completed-child state through one typed initializer"
        )
        #expect(
            !helperSource.contains("completedFailure: HeistFailureDetail?"),
            "Receipt outcome reduction should not expose completed failure as an optional parameter"
        )
        #expect(
            helperSource.contains("func stepResult("),
            "Receipt outcomes should own the single projection into HeistExecutionStepResult"
        )
        #expect(
            try receiptSourceOccurrenceCount(#"case \.passed\(let evidence, let children\)"#, in: helperSource) == 1,
            "Passed outcome projection should have one canonical spelling"
        )
        #expect(
            try receiptSourceOccurrenceCount(#"case \.failed\(let evidence, let failure, let children\)"#, in: helperSource) == 1,
            "Failed outcome projection should have one canonical spelling"
        )
        #expect(
            try receiptSourceOccurrenceCount(#"case \.childAborted\(let evidence, let failure, let childAbort\)"#, in: helperSource) == 1,
            "Child-aborted outcome projection should have one canonical spelling"
        )
    }

    @Test func `heist receipt helper signatures accept typed outcomes`() throws {
        let helperSource = try receiptSourceFile(
            relativePath: "ButtonHeist/Sources/TheInsideJob/TheBrains/TheBrains+HeistReceiptConstruction.swift"
        )
        for helper in [
            "heistWaitReceipt",
            "heistInvocationReceipt",
            "heistLoopReceipt",
        ] {
            let declaration = receiptSourceFunctionDeclaration(named: helper, in: helperSource)
            #expect(
                declaration.contains("outcome: HeistReceiptOutcome"),
                "\(helper) should accept one typed outcome instead of optional status/failure fields"
            )
            #expect(
                !declaration.contains("failure: HeistFailureDetail?"),
                "\(helper) should not expose optional failure state in its signature"
            )
            #expect(
                !declaration.contains("abortedAtChildPath: String?"),
                "\(helper) should not expose optional child-abort state in its signature"
            )
            #expect(
                !declaration.contains("children: [HeistExecutionStepResult]"),
                "\(helper) should accept typed receipt children instead of a raw child bag"
            )
        }

        let childParentDeclaration = receiptSourceFunctionDeclaration(named: "heistChildParentReceipt", in: helperSource)
        #expect(childParentDeclaration.contains("children: HeistReceiptChildren"))
        #expect(!childParentDeclaration.contains("failure: HeistFailureDetail?"))
        #expect(!childParentDeclaration.contains("abortedAtChildPath: String?"))

        for helper in [
            "func heistActionReceipt",
            "func heistWaitReceipt",
            "func heistSkippedReceipt",
            "func heistChildParentReceipt",
            "func heistWarningReceipt",
            "func heistExplicitFailureReceipt",
            "func heistLoopReceipt",
        ] {
            #expect(helperSource.contains(helper), "Missing runtime receipt helper: \(helper)")
        }

        let loopIterationHelperOffenders = try receiptSourceFiles(relativeRoot: "ButtonHeist/Sources/TheInsideJob/TheBrains")
            .filter { $0.contents.contains("heistLoopIterationReceipt") }
            .map(\.relativePath)
        #expect(
            loopIterationHelperOffenders.isEmpty,
            "Loop iteration receipts should use the canonical heistLoopReceipt helper: \(loopIterationHelperOffenders)"
        )
    }
}

private struct ReceiptSourceFile {
    let relativePath: String
    let contents: String
}

private func receiptSourceFiles(relativeRoot: String) throws -> [ReceiptSourceFile] {
    let root = receiptRepositoryRoot()
    let sourceRoot = root.appendingPathComponent(relativeRoot)
    guard let enumerator = FileManager.default.enumerator(
        at: sourceRoot,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        return []
    }

    var files: [ReceiptSourceFile] = []
    for case let url as URL in enumerator where url.pathExtension == "swift" {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else { continue }
        let relativePath = url.path.replacingOccurrences(of: root.path + "/", with: "")
        files.append(ReceiptSourceFile(
            relativePath: relativePath,
            contents: try String(contentsOf: url, encoding: .utf8)
        ))
    }
    return files.sorted { $0.relativePath < $1.relativePath }
}

private func receiptSourceFile(relativePath: String) throws -> String {
    try String(contentsOf: receiptRepositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
}

private func receiptSourceContains(_ pattern: String, in source: String) throws -> Bool {
    try receiptSourceOccurrenceCount(pattern, in: source) > 0
}

private func receiptSourceOccurrenceCount(_ pattern: String, in source: String) throws -> Int {
    let regex = try NSRegularExpression(pattern: pattern)
    let range = NSRange(source.startIndex..<source.endIndex, in: source)
    return regex.numberOfMatches(in: source, range: range)
}

private func receiptSourceLines(matching pattern: String, in source: String) throws -> [String] {
    let regex = try NSRegularExpression(pattern: pattern)
    return source
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map(String.init)
        .filter { line in
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            return regex.firstMatch(in: line, range: range) != nil
        }
        .map { $0.trimmingCharacters(in: .whitespaces) }
}

private func receiptSourceFunctionDeclaration(named name: String, in source: String) -> String {
    guard let start = source.range(of: "func \(name)(")?.lowerBound else { return "" }
    guard let end = source[start...].firstIndex(of: "{") else {
        return String(source[start...])
    }
    return String(source[start..<end])
}

private func receiptRepositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
