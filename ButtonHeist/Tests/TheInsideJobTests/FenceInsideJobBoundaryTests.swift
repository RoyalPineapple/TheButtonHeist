import Foundation
import XCTest

final class FenceInsideJobBoundaryTests: XCTestCase {

    func testExecutionSourcesDoNotReferenceFenceRequestPayloadTypes() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceDirectories = [
            packageRoot.appendingPathComponent("Sources/TheInsideJob/TheBrains"),
            packageRoot.appendingPathComponent("Sources/TheInsideJob/TheSafecracker"),
        ]
        let forbiddenReferences = [
            ForbiddenReference(
                token: "RequestPayload",
                reason: "Fence request payload decoding must stay in TheFence"
            ),
            ForbiddenReference(
                token: "ParsedRequest",
                reason: "parsed transport requests must not cross into InsideJob execution"
            ),
            ForbiddenReference(
                token: "originalRequest",
                reason: "raw transport request dictionaries must stay at the Fence boundary"
            ),
            ForbiddenReference(
                token: "decodeRequestPayload",
                reason: "request decoding must not move below TheFence"
            ),
            ForbiddenReference(
                token: "TheFence.",
                reason: "InsideJob execution must not reference Fence boundary types"
            ),
            ForbiddenReference(
                token: "import ButtonHeist",
                reason: "TheInsideJob must not depend on the client Fence module"
            ),
            ForbiddenReference(
                token: "[String: Any]",
                reason: "InsideJob execution must receive typed domain values, not raw request dictionaries"
            ),
        ]

        var violations: [String] = []
        for fileURL in try swiftFiles(in: sourceDirectories) {
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            let relativePath = fileURL.path.replacingOccurrences(
                of: packageRoot.path + "/",
                with: ""
            )
            for reference in forbiddenReferences where contents.contains(reference.token) {
                let line = firstLineNumber(containing: reference.token, in: contents)
                violations.append("\(relativePath):\(line): \(reference.reason) (`\(reference.token)`)")
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            """
            The Fence translates transport requests before InsideJob execution.
            Forbidden boundary references found:
            \(violations.joined(separator: "\n"))
            """
        )
    }

    private struct ForbiddenReference {
        let token: String
        let reason: String
    }

    private func swiftFiles(in directories: [URL]) throws -> [URL] {
        let fileManager = FileManager.default
        var files: [URL] = []
        for directory in directories {
            guard let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey]
            ) else {
                continue
            }
            for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                if resourceValues.isRegularFile == true {
                    files.append(fileURL)
                }
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    private func firstLineNumber(containing token: String, in contents: String) -> Int {
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
        return (lines.firstIndex { $0.contains(token) } ?? 0) + 1
    }
}
