import XCTest
import ButtonHeist
import Foundation
import TheScore
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
            + swiftSourceFiles(under: "ButtonHeistCLI/Sources/Support")
        let disallowedPatterns = [
            #"commandName:\s*TheFence\.Command"#,
            #""command"\s*:\s*TheFence\.Command"#,
            #"TheFence\.Command\.[A-Za-z0-9_]+\.rawValue"#,
        ]
        let mirroredFenceKeys = Set(FenceParameterKey.allCases.map(\.rawValue))
        let requestKeyPatterns = [
            #"(?:request|result|parsed|dictionary)\["([^"]+)"\]"#,
            #"(?:fenceRequest|cliRequest)\(\["([^"]+)"\s*:"#,
            #"return\s+\["([^"]+)"\s*:"#,
        ]

        for file in sourceFiles {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for pattern in disallowedPatterns {
                XCTAssertNil(
                    contents.range(of: pattern, options: .regularExpression),
                    "\(relativePath(file)) should use CLICommandContract / TheFence.Command.cliRequest() instead of bypassing the renderer"
                )
            }

            for pattern in requestKeyPatterns {
                let mirroredLiterals = Set(captureGroupMatches(in: contents, pattern: pattern))
                    .intersection(mirroredFenceKeys)
                XCTAssertTrue(
                    mirroredLiterals.isEmpty,
                    "\(relativePath(file)) should use FenceParameterKey instead of mirrored request keys: \(mirroredLiterals.sorted())"
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

    func testGetInterfaceHelpDoesNotAdvertiseScopeOrLegacyFullAlias() {
        let help = GetInterfaceCommand.helpMessage()

        XCTAssertFalse(help.contains("--scope"), help)
        XCTAssertFalse(help.contains("visible"), help)
        XCTAssertFalse(help.contains("--timeout"), help)
        XCTAssertTrue(help.contains("Read the app accessibility hierarchy"), help)
        XCTAssertFalse(help.contains("full"), help)
        XCTAssertFalse(help.contains("--full"), help)
        XCTAssertFalse(help.contains("current UI element hierarchy"), help)
    }

    func testGetInterfaceRejectsLegacyFullAlias() {
        XCTAssertThrowsError(try GetInterfaceCommand.parse(["--full"]))
    }

    func testGetInterfaceRejectsTimeoutOption() {
        XCTAssertThrowsError(try GetInterfaceCommand.parse(["--timeout", "1"]))
    }

    func testGetInterfaceAcceptsConnectionTimeoutOption() throws {
        let command = try GetInterfaceCommand.parse(["--connect-timeout", "2.5"])

        XCTAssertEqual(command.connection.connectTimeout, 2.5)
    }

    func testConnectCommandMergesPositionalDeviceAndConnectionTimeout() throws {
        let command = try ConnectCommand.parse([
            "127.0.0.1:1455",
            "--connect-timeout",
            "2.5",
            "--quiet",
        ])
        let merged = ConnectionOptions.merging(
            base: command.connection,
            positionalDevice: command.device
        )

        XCTAssertEqual(merged.device, "127.0.0.1:1455")
        XCTAssertEqual(merged.connectTimeout, 2.5)
        XCTAssertTrue(merged.quiet)
    }

    func testRecordCommandLeavesOmittedInactivityTimeoutUnset() throws {
        let command = try RecordCommand.parse(["--max-duration", "120"])

        XCTAssertNil(command.inactivityTimeout)
        XCTAssertEqual(command.maxDuration, 120)
    }

    func testRecordCommandPreservesExplicitInactivityTimeout() throws {
        let command = try RecordCommand.parse(["--inactivity-timeout", "3"])

        XCTAssertEqual(command.inactivityTimeout, 3)
    }

    func testWaitForChangeCommandDefaultTimeoutIsThirtySeconds() throws {
        let command = try WaitForChangeCommand.parse([])

        XCTAssertEqual(command.timeout, 30)
    }

    func testTypeTextRequiresText() {
        XCTAssertThrowsError(try TypeCommand.parse([]))
    }

    func testTypeTextRejectsEmptyText() throws {
        XCTAssertThrowsError(try TypeCommand.parse([""]))
    }

    func testTypeTextRejectsLegacyDeleteOption() {
        XCTAssertThrowsError(try TypeCommand.parse(["--delete", "3", "hello"]))
    }

    func testExpectationArgumentParserNormalizesShorthand() throws {
        let parsed = try ExpectationArgumentParser.parse("screen_changed")

        guard case .object(let object) = parsed else {
            return XCTFail("expected object expectation")
        }
        XCTAssertEqual(object["type"], .string("screen_changed"))
    }

    func testExpectationArgumentParserAcceptsJsonObject() throws {
        let parsed = try ExpectationArgumentParser.parse(#"{"type":"element_updated","property":"value"}"#)

        guard case .object(let object) = parsed else {
            return XCTFail("expected object expectation")
        }
        XCTAssertEqual(object["type"], .string("element_updated"))
        XCTAssertEqual(object["property"], .string("value"))
    }

    func testExpectationArgumentParserRejectsUnknownString() {
        XCTAssertThrowsError(try ExpectationArgumentParser.parse("layout_changed"))
    }

    func testHumanParserNormalizesChangeExpectationShortcut() {
        let request = ReplSession.parseHumanInput("change expect=screen_changed")
        let expect = request[.expect] as? [String: Any]

        XCTAssertEqual(request[.command] as? String, TheFence.Command.waitForChange.rawValue)
        XCTAssertEqual(expect?[.type] as? String, "screen_changed")
    }

    func testHumanParserNormalizesChangeExpectationJsonObject() {
        let request = ReplSession.parseHumanInput(#"change expect='{"type":"elements_changed"}'"#)
        let expect = request[.expect] as? [String: Any]

        XCTAssertEqual(request[.command] as? String, TheFence.Command.waitForChange.rawValue)
        XCTAssertEqual(expect?[.type] as? String, "elements_changed")
    }

    func testRunBatchSerializesStepsBeforeSending() throws {
        let steps = try RunBatchCommand.serializedBatchSteps(
            inline: #"[{"command":"activate","heistId":"button-login"}]"#,
            fromFile: nil
        )

        XCTAssertEqual(steps.count, 1)
        guard case .object(let object) = steps[0].value else {
            return XCTFail("expected serialized batch step object")
        }
        XCTAssertEqual(object["command"], .string(TheFence.Command.activate.rawValue))
        XCTAssertEqual(object["heistId"], .string("button-login"))
    }

    func testRunBatchLeavesUnknownSerializedCommandForFenceValidation() throws {
        let steps = try RunBatchCommand.serializedBatchSteps(
            inline: #"[{"command":"not_a_command"}]"#,
            fromFile: nil
        )

        guard case .object(let object) = steps[0].value else {
            return XCTFail("expected serialized batch step object")
        }
        XCTAssertEqual(object["command"], .string("not_a_command"))
    }

    func testRunBatchLeavesNestedRunBatchCommandForFenceValidation() throws {
        let steps = try RunBatchCommand.serializedBatchSteps(
            inline: #"[{"command":"run_batch","steps":[]}]"#,
            fromFile: nil
        )

        guard case .object(let object) = steps[0].value else {
            return XCTFail("expected serialized batch step object")
        }
        XCTAssertEqual(object["command"], .string(TheFence.Command.runBatch.rawValue))
        XCTAssertEqual(object["steps"], .array([]))
    }

    func testHumanParserPreservesKnownStringParameterValues() {
        let request = ReplSession.parseHumanInput("set_pasteboard text=false")

        XCTAssertEqual(request[.command] as? String, TheFence.Command.setPasteboard.rawValue)
        XCTAssertEqual(request[.text] as? String, "false")
    }

    func testHumanParserCoercesKnownBooleanParametersOnly() {
        let request = ReplSession.parseHumanInput("wait label=true absent=true")

        XCTAssertEqual(request[.command] as? String, TheFence.Command.waitFor.rawValue)
        XCTAssertEqual(request[.label] as? String, "true")
        XCTAssertEqual(request[.absent] as? Bool, true)
    }

    func testHumanParserMapsCompoundCopyAlias() {
        let request = ReplSession.parseHumanInput("copy")

        XCTAssertEqual(request[.command] as? String, TheFence.Command.editAction.rawValue)
        XCTAssertEqual(request[.action] as? String, EditAction.copy.rawValue)
    }

    func testHumanParserAliasesComeFromSharedCommandContract() {
        for (aliasName, alias) in TheFence.Command.humanCommandAliases {
            let request = ReplSession.parseHumanInput(aliasName)

            XCTAssertEqual(
                request[.command] as? String,
                alias.command.rawValue,
                "\(aliasName) should resolve through TheFence.Command.humanCommandAliases"
            )
            for (key, value) in alias.parameters {
                XCTAssertEqual(
                    request[key].flatMap(HeistValue.from),
                    value,
                    "\(aliasName) should apply canonical alias parameter \(key.rawValue)"
                )
            }
        }
    }

    func testSessionReplDoesNotDeclareCommandAliasTables() throws {
        let source = try String(
            contentsOf: repositoryRoot()
                .appendingPathComponent("ButtonHeistCLI/Sources/Session/SessionRepl.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("commandAliases:"), "REPL command aliases should live in TheFence.Command.humanCommandAliases")
        XCTAssertFalse(source.contains("compoundAliases:"), "REPL compound aliases should live in TheFence.Command.humanCommandAliases")
    }

    func testHumanParserMapsCoordinateTapAlias() {
        let request = ReplSession.parseHumanInput("tap 100 200")

        XCTAssertEqual(request[.command] as? String, TheFence.Command.oneFingerTap.rawValue)
        XCTAssertEqual(request[.x] as? Double, 100)
        XCTAssertEqual(request[.y] as? Double, 200)
    }

    func testHumanParserMapsHeistIdPositionalTarget() {
        let request = ReplSession.parseHumanInput("activate button_save")

        XCTAssertEqual(request[.command] as? String, TheFence.Command.activate.rawValue)
        XCTAssertEqual(request[.heistId] as? String, "button_save")
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

    private func captureGroupMatches(in contents: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            XCTFail("Invalid regex pattern: \(pattern)")
            return []
        }
        let range = NSRange(contents.startIndex..<contents.endIndex, in: contents)
        return regex.matches(in: contents, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let matchRange = Range(match.range(at: 1), in: contents) else {
                return nil
            }
            return String(contents[matchRange])
        }
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
