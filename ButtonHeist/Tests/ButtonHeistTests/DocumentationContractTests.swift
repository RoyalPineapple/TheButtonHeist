import XCTest
@_spi(ButtonHeistTooling) @testable import ButtonHeist
import TheScore

final class DocumentationContractTests: XCTestCase {

    func testHandwrittenMarkdownLinksResolve() throws {
        var failures: [String] = []

        for file in handwrittenMarkdownFiles() {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for link in try markdownLinks(in: contents) {
                guard let target = localPathTarget(from: link) else { continue }
                let resolved = file.deletingLastPathComponent()
                    .appendingPathComponent(target)
                    .standardizedFileURL
                if !FileManager.default.fileExists(atPath: resolved.path) {
                    failures.append("\(relativePath(file)) -> \(link)")
                }
            }
        }

        XCTAssertTrue(
            failures.isEmpty,
            "Broken local markdown links:\n\(failures.joined(separator: "\n"))"
        )
    }

    func testJSONLinesExamplesUseCLIExposedCommands() throws {
        var failures: [String] = []

        for file in handwrittenMarkdownFiles() {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for example in jsonLinesExamples(in: contents) {
                let data = Data(example.json.utf8)
                let decoded: JSONLinesCommandExample
                do {
                    decoded = try JSONDecoder().decode(JSONLinesCommandExample.self, from: data)
                } catch {
                    failures.append("\(relativePath(file)):\(example.line): invalid JSON-lines command example")
                    continue
                }

                guard let command = TheFence.Command(rawValue: decoded.commandName) else {
                    failures.append("\(relativePath(file)):\(example.line): invalid JSON-lines command example")
                    continue
                }

                if command.descriptor.cliExposure != .directCommand {
                    failures.append(
                        "\(relativePath(file)):\(example.line): \(decoded.commandName) is not CLI-exposed"
                    )
                }

                if command == .runHeist {
                    let presentRawFields = decoded.presentRawIRFields
                    if !presentRawFields.isEmpty {
                        let fieldList = presentRawFields.joined(separator: ", ")
                        failures.append(
                            "\(relativePath(file)):\(example.line): run_heist JSON-lines example exposes raw IR fields \(fieldList)"
                        )
                    }
                }
            }
        }

        XCTAssertTrue(
            failures.isEmpty,
            "Invalid JSON-lines documentation examples:\n\(failures.joined(separator: "\n"))"
        )
    }

    func testWireEnvelopeExamplesDecodeWithCanonicalTypes() throws {
        let wireProtocol = try contents(relativePath: "docs/WIRE-PROTOCOL.md")
        let envelopeBlocks = try jsonCodeBlocks(in: markdownSection(
            startingAt: "## Envelopes",
            endingAt: "## Public Wire Examples",
            in: wireProtocol
        ))
        let hello = try jsonDocuments(in: onlyJSONBlock(
            startingAt: "### Hello",
            endingAt: "### Authentication",
            in: wireProtocol
        ))

        let requestDocuments = try [
            XCTUnwrap(envelopeBlocks[safe: 0]),
            XCTUnwrap(hello[safe: 1]),
            onlyJSONBlock(
                startingAt: "### Authentication",
                endingAt: "### Rejected Auth Tags",
                in: wireProtocol
            ),
            jsonBlock(
                at: 0,
                startingAt: "### Status Probe",
                endingAt: "### Interface",
                in: wireProtocol
            ),
            jsonBlock(
                at: 0,
                startingAt: "### Interface",
                endingAt: "### One-Step Semantic Action",
                in: wireProtocol
            ),
            onlyJSONBlock(
                startingAt: "### One-Step Semantic Action",
                endingAt: "### Screen Capture",
                in: wireProtocol
            ),
            onlyJSONBlock(
                startingAt: "### Screen Capture",
                endingAt: "### Wait",
                in: wireProtocol
            ),
            jsonBlock(
                at: 0,
                startingAt: "### Wait",
                endingAt: "## Action Results",
                in: wireProtocol
            ),
        ]
        let responseDocuments = try [
            XCTUnwrap(envelopeBlocks[safe: 1]),
            XCTUnwrap(hello[safe: 0]),
            XCTUnwrap(hello[safe: 2]),
            onlyJSONBlock(
                startingAt: "### Protocol Mismatch",
                endingAt: "### Session Locked",
                in: wireProtocol
            ),
            onlyJSONBlock(
                startingAt: "### Session Locked",
                endingAt: "### Status Probe",
                in: wireProtocol
            ),
            jsonBlock(
                at: 1,
                startingAt: "### Status Probe",
                endingAt: "### Interface",
                in: wireProtocol
            ),
            jsonBlock(
                at: 1,
                startingAt: "### Interface",
                endingAt: "### One-Step Semantic Action",
                in: wireProtocol
            ),
            jsonBlock(
                at: 0,
                startingAt: "## Action Results",
                endingAt: "## Traces, Facts, and Public Deltas",
                in: wireProtocol
            ),
        ]

        for document in requestDocuments {
            _ = try JSONDecoder().decode(RequestEnvelope.self, from: Data(document.utf8))
        }
        for document in responseDocuments {
            _ = try JSONDecoder().decode(ResponseEnvelope.self, from: Data(document.utf8))
        }
    }

    func testPublicContractFragmentsDecodeWithCanonicalTypes() throws {
        let api = try contents(relativePath: "docs/API.md")
        let wireProtocol = try contents(relativePath: "docs/WIRE-PROTOCOL.md")
        let predicateDocuments = try jsonCodeBlocks(in: markdownSection(
            startingAt: "### Expectations",
            endingAt: "## Minimal Integration",
            in: api
        )) + jsonDocuments(in: onlyJSONBlock(
            startingAt: "The strict predicate wire grammar is:",
            endingAt: "Raw heist receipt steps use one tagged `outcome`",
            in: wireProtocol
        ))

        for document in predicateDocuments {
            let value = try JSONDecoder().decode(HeistValue.self, from: Data(document.utf8))
            _ = try TheFence.ExpectationPayload.parseRequiredPredicate(value)
        }

        let receipt = try onlyJSONBlock(
            startingAt: "Raw heist receipt steps use one tagged `outcome`",
            endingAt: "## Action Results",
            in: wireProtocol
        )
        _ = try JSONDecoder().decode(HeistExecutionStepResult.self, from: Data(receipt.utf8))

        let actionBlocks = try jsonCodeBlocks(in: markdownSection(
            startingAt: "## Action Results",
            endingAt: "## Traces, Facts, and Public Deltas",
            in: wireProtocol
        ))
        let payload = try XCTUnwrap(actionBlocks[safe: 1])
        _ = try JSONDecoder().decode(ResultPayload.self, from: Data(payload.utf8))
    }

    private func jsonLinesExamples(in contents: String) -> [(line: Int, json: String)] {
        contents
            .components(separatedBy: .newlines)
            .enumerated()
            .compactMap { offset, line in
                guard line.contains("buttonheist json_lines"),
                      let start = line.firstIndex(of: "{"),
                      let end = line.lastIndex(of: "}")
                else { return nil }
                return (line: offset + 1, json: String(line[start...end]))
            }
    }

    private func onlyJSONBlock(
        startingAt start: String,
        endingAt end: String,
        in contents: String
    ) throws -> String {
        let blocks = try jsonCodeBlocks(in: markdownSection(startingAt: start, endingAt: end, in: contents))
        return try XCTUnwrap(blocks.only)
    }

    private func jsonBlock(
        at index: Int,
        startingAt start: String,
        endingAt end: String,
        in contents: String
    ) throws -> String {
        let section = try markdownSection(startingAt: start, endingAt: end, in: contents)
        return try XCTUnwrap(jsonCodeBlocks(in: section)[safe: index])
    }

    private func markdownSection(
        startingAt start: String,
        endingAt end: String,
        in contents: String
    ) throws -> String {
        let startRange = try XCTUnwrap(contents.range(of: start))
        let remainder = contents[startRange.upperBound...]
        let endRange = try XCTUnwrap(remainder.range(of: end))
        return String(remainder[..<endRange.lowerBound])
    }

    private func jsonCodeBlocks(in contents: String) throws -> [String] {
        let regex = try NSRegularExpression(pattern: #"```json\s*\n([\s\S]*?)\n```"#)
        let range = NSRange(contents.startIndex..<contents.endIndex, in: contents)
        return regex.matches(in: contents, range: range).compactMap { match in
            Range(match.range(at: 1), in: contents).map { String(contents[$0]) }
        }
    }

    private func jsonDocuments(in block: String) throws -> [String] {
        let lines = block.split(whereSeparator: \Character.isNewline).map(String.init)
        guard lines.count > 1,
              lines.allSatisfy({ $0.hasPrefix("{") && $0.hasSuffix("}") }) else {
            return [block]
        }
        return lines
    }

    private func markdownLinks(in contents: String) throws -> [String] {
        let pattern = #"\[[^\]]+\]\(([^)]+)\)"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(contents.startIndex..<contents.endIndex, in: contents)
        return regex.matches(in: contents, range: range).compactMap { match in
            guard let matchRange = Range(match.range(at: 1), in: contents) else {
                return nil
            }
            return String(contents[matchRange])
        }
    }

    private func localPathTarget(from link: String) -> String? {
        var target = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if target.hasPrefix("<"), target.hasSuffix(">") {
            target = String(target.dropFirst().dropLast())
        }
        if target.hasPrefix("#") ||
            target.contains("://") ||
            target.hasPrefix("mailto:") ||
            target.isEmpty {
            return nil
        }
        if let titleStart = target.firstIndex(of: " ") {
            target = String(target[..<titleStart])
        }
        if let anchorStart = target.firstIndex(of: "#") {
            target = String(target[..<anchorStart])
        }
        return target.isEmpty ? nil : target.removingPercentEncoding ?? target
    }

    private func handwrittenMarkdownFiles() -> [URL] {
        let relativePaths = [
            "README.md",
            "ButtonHeistCLI/README.md",
            "ButtonHeistMCP/README.md",
            "examples/README.md",
            "examples/adoption-examples.md",
            "examples/semantic-command.md",
            "docs/ACCESSIBILITY-CONTRACT.md",
            "docs/API.md",
            "docs/ARCHITECTURE.md",
            "docs/AUTH.md",
            "docs/BONJOUR_TROUBLESHOOTING.md",
            "docs/CI.md",
            "docs/HEIST-DOCTOR.md",
            "docs/HEIST-FORMAT.md",
            "docs/MCP-AGENT-GUIDE.md",
            "docs/README.md",
            "docs/SCOPE-AND-LIMITS.md",
            "docs/SWIFT-HEIST-AUTHORING.md",
            "docs/USB_DEVICE_CONNECTIVITY.md",
            "docs/WIRE-PROTOCOL.md",
        ]
        return relativePaths.map { repositoryRoot().appendingPathComponent($0) }
    }

    private func contents(relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot().appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func relativePath(_ url: URL) -> String {
        let rootPath = repositoryRoot().path + "/"
        return url.path.hasPrefix(rootPath)
            ? String(url.path.dropFirst(rootPath.count))
            : url.path
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private extension Collection {
    var only: Element? {
        count == 1 ? first : nil
    }
}

private extension Collection where Index == Int {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private struct JSONLinesCommandExample: Decodable {
    let commandName: String
    let presentRawIRFields: [String]

    private enum CommandCodingKeys: String, CodingKey {
        case command
    }

    private enum RawIRField: String, CodingKey, CaseIterable {
        case version
        case name
        case parameter
        case definitions
        case body
    }

    init(from decoder: Decoder) throws {
        let commandContainer = try decoder.container(keyedBy: CommandCodingKeys.self)
        commandName = try commandContainer.decode(String.self, forKey: .command)

        let rawFieldContainer = try decoder.container(keyedBy: RawIRField.self)
        presentRawIRFields = RawIRField.allCases
            .filter { rawFieldContainer.contains($0) }
            .map(\.stringValue)
            .sorted()
    }
}
