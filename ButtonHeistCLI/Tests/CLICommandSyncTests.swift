import XCTest
import ButtonHeist
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
}
