import Foundation
import Testing

@Suite struct HeistDoctorToolSourceTests {

    @Test
    func `heist-doctor stdout writes are routed through local output sink`() throws {
        let root = try repositoryRoot()
        let files = try swiftFiles(in: root.appendingPathComponent("ButtonHeist/Sources/HeistDoctorTool", isDirectory: true))
        let forbiddenSnippets = [
            "print(",
            "FileHandle.standardOutput.write",
        ]
        var foundOutputSink = false

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            foundOutputSink = foundOutputSink || source.contains("enum HeistDoctorToolOutput")
            for (lineNumber, line) in sourceLinesOutsideHeistDoctorToolOutputSink(source) {
                for snippet in forbiddenSnippets {
                    #expect(
                        line.range(of: snippet) == nil,
                        "\(file.path):\(lineNumber) contains \(snippet) outside HeistDoctorToolOutput"
                    )
                }
            }
        }

        #expect(foundOutputSink, "HeistDoctorToolOutput sink is missing")
    }
}

private func repositoryRoot() throws -> URL {
    let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    if isRepositoryRoot(currentDirectory) {
        return currentDirectory
    }

    var candidate = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while candidate.path != candidate.deletingLastPathComponent().path {
        if isRepositoryRoot(candidate) {
            return candidate
        }
        candidate = candidate.deletingLastPathComponent()
    }

    throw SourceScanFailure("could not find repository root")
}

private func isRepositoryRoot(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.appendingPathComponent("ButtonHeist/Package.swift").path)
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

private func sourceLinesOutsideHeistDoctorToolOutputSink(_ source: String) -> [(lineNumber: Int, line: Substring)] {
    var lines: [(lineNumber: Int, line: Substring)] = []
    var sinkBraceDepth: Int?

    for (index, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
        if sinkBraceDepth == nil, line.range(of: "enum HeistDoctorToolOutput") != nil {
            let depth = braceDelta(in: line)
            sinkBraceDepth = depth > 0 ? depth : nil
            continue
        }

        if let currentDepth = sinkBraceDepth {
            let nextDepth = currentDepth + braceDelta(in: line)
            sinkBraceDepth = nextDepth > 0 ? nextDepth : nil
            continue
        }

        lines.append((lineNumber: index + 1, line: line))
    }

    return lines
}

private func braceDelta(in line: Substring) -> Int {
    line.reduce(0) { result, character in
        switch character {
        case "{":
            return result + 1
        case "}":
            return result - 1
        default:
            return result
        }
    }
}

private struct SourceScanFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
