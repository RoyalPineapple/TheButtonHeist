import XCTest
import ButtonHeist
import Foundation
@testable import ButtonHeistCLIExe

final class CLICommandSyncTests: XCTestCase {

    func testDirectCLICommandsHaveTopLevelSubcommands() {
        let cliNames = topLevelCommandNames()

        for command in TheFence.Command.allCases {
            switch command.cliExposure {
            case .directCommand:
                XCTAssertTrue(
                    cliNames.contains(command.rawValue),
                    "Command '\(command.rawValue)' is marked directCommand but has no top-level CLI command"
                )
            case .groupedUnder(let commandName):
                XCTAssertTrue(
                    cliNames.contains(commandName),
                    "Command '\(command.rawValue)' is grouped under missing CLI command '\(commandName)'"
                )
            case .sessionOnly, .notExposed:
                break
            }
        }
    }

    func testTopLevelSubcommandsMapToCommandCatalogOrCLIOnlyCommands() {
        let commandNames = Set(TheFence.Command.allCases.map(\.rawValue))
        let cliOnlyCommands: Set<String> = ["session"]

        for cliName in topLevelCommandNames() {
            XCTAssertTrue(
                commandNames.contains(cliName) || cliOnlyCommands.contains(cliName),
                "Top-level CLI command '\(cliName)' is not in TheFence.Command or the CLI-only allowlist"
            )
        }
    }

    func testTopLevelSubcommandsHaveNoDuplicates() {
        var seen = Set<String>()
        for cliName in topLevelCommandNames() {
            XCTAssertTrue(seen.insert(cliName).inserted, "Duplicate top-level CLI command: '\(cliName)'")
        }
    }

    func testTopLevelFenceCommandAdaptersRenderNamesFromCanonicalContract() {
        let cliOnlyCommands: Set<String> = ["session"]

        for commandType in ButtonHeistApp.configuration.subcommands {
            let cliName = commandType.configuration.commandName ?? String(describing: commandType)
            if cliOnlyCommands.contains(cliName) {
                continue
            }

            guard let adapter = commandType as? CLICommandContract.Type else {
                XCTFail("Top-level CLI command '\(cliName)' should declare a canonical Fence command")
                continue
            }

            XCTAssertEqual(
                cliName,
                adapter.fenceCommand.cliCommandName,
                "Top-level CLI command '\(cliName)' should render its name from TheFence.Command"
            )
        }
    }

    func testCommandSourcesDoNotBypassFenceCommandRenderer() throws {
        let sourceFiles = try swiftSourceFiles(under: "ButtonHeistCLI/Sources/Commands")
            + swiftSourceFiles(under: "ButtonHeistCLI/Sources/Session")
        let disallowedPatterns = [
            #"commandName:\s*TheFence\.Command"#,
            #""command"\s*:\s*TheFence\.Command"#,
            #"TheFence\.Command\.[A-Za-z0-9_]+\.rawValue"#,
        ]

        for file in sourceFiles {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for pattern in disallowedPatterns {
                XCTAssertNil(
                    contents.range(of: pattern, options: .regularExpression),
                    "\(relativePath(file)) should use CLICommandContract / TheFence.Command.cliRequest() instead of bypassing the renderer"
                )
            }
        }
    }

    func testDocumentedTopLevelCommandsMatchCLIConfiguration() throws {
        let documentedCommands = try documentedTopLevelCommandNames()
        let actualCommands = Set(topLevelCommandNames())

        XCTAssertEqual(
            documentedCommands,
            actualCommands,
            """
            ButtonHeistCLI/README.md top-level command table differs: \
            docs-only \(documentedCommands.subtracting(actualCommands).sorted()), \
            missing \(actualCommands.subtracting(documentedCommands).sorted())
            """
        )
    }

    func testGetInterfaceAdvertisedScopeOptionsHideLegacyFullScope() {
        XCTAssertEqual(
            Set(CLIGetInterfaceScope.allCases.map(\.rawValue)),
            ["visible"]
        )
    }

    func testGetInterfaceHelpAdvertisesScopeAndHidesLegacyFullAlias() {
        let help = GetInterfaceCommand.helpMessage()

        XCTAssertTrue(help.contains("--scope"), help)
        XCTAssertTrue(help.contains("visible"), help)
        XCTAssertFalse(help.contains("full"), help)
        XCTAssertFalse(help.contains("--full"), help)
    }

    func testExpectationArgumentParserNormalizesShorthand() throws {
        let parsed = try ExpectationArgumentParser.parse("screen_changed")

        XCTAssertEqual(parsed["type"] as? String, "screen_changed")
    }

    func testExpectationArgumentParserAcceptsJsonObject() throws {
        let parsed = try ExpectationArgumentParser.parse(#"{"type":"element_updated","property":"value"}"#)

        XCTAssertEqual(parsed["type"] as? String, "element_updated")
        XCTAssertEqual(parsed["property"] as? String, "value")
    }

    func testExpectationArgumentParserRejectsUnknownString() {
        XCTAssertThrowsError(try ExpectationArgumentParser.parse("layout_changed"))
    }

    func testHumanParserNormalizesChangeExpectationShortcut() {
        let request = ReplSession.parseHumanInput("change expect=screen_changed")
        let expect = request["expect"] as? [String: Any]

        XCTAssertEqual(request["command"] as? String, TheFence.Command.waitForChange.rawValue)
        XCTAssertEqual(expect?["type"] as? String, "screen_changed")
    }

    func testHumanParserNormalizesChangeExpectationJsonObject() {
        let request = ReplSession.parseHumanInput(#"change expect='{"type":"elements_changed"}'"#)
        let expect = request["expect"] as? [String: Any]

        XCTAssertEqual(expect?["type"] as? String, "elements_changed")
    }

    private func topLevelCommandNames() -> [String] {
        ButtonHeistApp.configuration.subcommands.map { commandType in
            commandType.configuration.commandName ?? String(describing: commandType)
        }
    }

    private func documentedTopLevelCommandNames() throws -> Set<String> {
        let data = try Data(contentsOf: repositoryRoot().appendingPathComponent("ButtonHeistCLI/README.md"))
        guard let contents = String(bytes: data, encoding: .utf8) else {
            XCTFail("ButtonHeistCLI/README.md is not UTF-8")
            return []
        }
        guard let startRange = contents.range(of: "## Top-Level Commands"),
              let endRange = contents[startRange.upperBound...].range(of: "### activate") else {
            XCTFail("Missing Top-Level Commands table in ButtonHeistCLI/README.md")
            return []
        }

        let section = contents[startRange.upperBound..<endRange.lowerBound]
        return Set(section.split(separator: "\n").compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("| `") else { return nil }
            return trimmed.dropFirst(3).split(separator: "`", maxSplits: 1).first.map(String.init)
        })
    }

    private func swiftSourceFiles(under relativePath: String) throws -> [URL] {
        let root = repositoryRoot().appendingPathComponent(relativePath)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            XCTFail("Unable to enumerate \(relativePath)")
            return []
        }

        return try enumerator.compactMap { item -> URL? in
            guard let url = item as? URL, url.pathExtension == "swift" else { return nil }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            return values.isRegularFile == true ? url : nil
        }
    }

    private func relativePath(_ url: URL) -> String {
        let rootPath = repositoryRoot().path
        let path = url.path
        guard path.hasPrefix(rootPath + "/") else { return path }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
