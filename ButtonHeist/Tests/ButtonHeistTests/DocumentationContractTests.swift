import XCTest
@testable import ButtonHeist

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
        let rawIRFields = Set(["version", "name", "parameter", "definitions", "body"])

        for file in handwrittenMarkdownFiles() {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for example in jsonLinesExamples(in: contents) {
                let data = Data(example.json.utf8)
                let decoded = try JSONSerialization.jsonObject(with: data)
                guard let object = decoded as? [String: Any],
                      let commandName = object["command"] as? String,
                      let command = TheFence.Command(rawValue: commandName)
                else {
                    failures.append("\(relativePath(file)):\(example.line): invalid JSON-lines command example")
                    continue
                }

                if command.descriptor.cliExposure != .directCommand {
                    failures.append(
                        "\(relativePath(file)):\(example.line): \(commandName) is not CLI-exposed"
                    )
                }

                if command == .runHeist {
                    let presentRawFields = rawIRFields
                        .filter { object.keys.contains($0) }
                        .sorted()
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

    func testPublicSurfaceMatrixCoversRequiredContracts() throws {
        let api = try contents(relativePath: "docs/API.md")

        XCTAssertTrue(api.contains("## Public Surface Matrix"), api)
        for phrase in [
            "SwiftPM products and modules",
            "Homebrew release",
            "CLI commands",
            "JSON-lines input",
            "MCP tools",
            "`.heist` artifact format",
            "Plan DSL/source",
            "Config and environment keys",
            "Wire compatibility policy",
        ] {
            XCTAssertTrue(api.contains(phrase), phrase)
        }
    }

    func testHeistDoctorStatusIsDocumentedAsExperimentalSPMOnly() throws {
        let api = try contents(relativePath: "docs/API.md")
        let doctor = try contents(relativePath: "docs/HEIST-DOCTOR.md")
        let formula = try contents(relativePath: "Formula/buttonheist.rb")
        let package = try contents(relativePath: "Package.swift")

        XCTAssertTrue(package.contains(#".executable(name: "heist-doctor""#))
        XCTAssertFalse(formula.contains(#"bin.install "heist-doctor""#))

        for phrase in [
            "Public experimental, SwiftPM-only",
            "Not installed by Homebrew",
            "not a major-version stability contract",
        ] {
            XCTAssertTrue(api.containsNormalizedMarkdown(phrase), phrase)
        }
        for phrase in [
            "public experimental, SwiftPM-only alpha",
            "not installed by the Homebrew formula",
            "not a major-version compatibility contract",
        ] {
            XCTAssertTrue(doctor.containsNormalizedMarkdown(phrase), phrase)
        }
    }

    func testWireProtocolDocumentsExactProductVersionLockstep() throws {
        let wireProtocol = try contents(relativePath: "docs/WIRE-PROTOCOL.md")

        for phrase in [
            "There is no separate wire-protocol version",
            "exact product-version lockstep",
            "must come from the same Button Heist release",
            "major, minor, and patch differences are all incompatible",
            "there is no downgrade, feature negotiation, or best-effort compatibility mode",
            "protocolMismatch",
        ] {
            XCTAssertTrue(wireProtocol.containsNormalizedMarkdown(phrase), phrase)
        }
    }

    func testHomebrewRendererAcceptsOnlySemVerReleaseVersions() throws {
        let renderer = try contents(relativePath: "scripts/render-homebrew-formula.sh")

        XCTAssertTrue(renderer.contains("RELEASE_VERSION_REGEX='^[0-9]+\\.[0-9]+\\.[0-9]+$'"))
        XCTAssertTrue(renderer.contains("MAJOR.MINOR.PATCH") || renderer.contains("0.2.0 or 1.0.0"))
        XCTAssertFalse(renderer.contains("(\\.[0-9]+)?"))
        XCTAssertNil(
            renderer.range(
                of: #"[0-9]{4}\.[0-9]{2}\.[0-9]{2}\.[0-9]+"#,
                options: .regularExpression
            )
        )
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
            "examples/semantic-command.md",
            "docs/ACCESSIBILITY-CONTRACT.md",
            "docs/API.md",
            "docs/ARCHITECTURE.md",
            "docs/AUTH.md",
            "docs/BENCHMARKS.md",
            "docs/BONJOUR_TROUBLESHOOTING.md",
            "docs/HEIST-DOCTOR.md",
            "docs/HEIST-FORMAT.md",
            "docs/MCP-AGENT-GUIDE.md",
            "docs/README.md",
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

private extension String {
    func containsNormalizedMarkdown(_ phrase: String) -> Bool {
        normalizedMarkdownWhitespace.contains(phrase.normalizedMarkdownWhitespace)
    }

    var normalizedMarkdownWhitespace: String {
        split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
