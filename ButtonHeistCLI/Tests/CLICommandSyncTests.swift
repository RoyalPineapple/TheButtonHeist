import XCTest
import ButtonHeist
import Foundation
import TheScore
@testable import ButtonHeistCLIExe

final class CLICommandSyncTests: XCTestCase {

    func testTopLevelSubcommandsHaveNoDuplicates() {
        var seen = Set<String>()
        for cliName in topLevelCommandNames() {
            XCTAssertTrue(seen.insert(cliName).inserted, "Duplicate top-level CLI command: '\(cliName)'")
        }
    }

    func testSessionHelpShowsCurrentUserCommands() {
        let help = ReplSession.humanHelp

        XCTAssertTrue(help.contains("activate"))
        XCTAssertTrue(help.contains("get_interface"))
        XCTAssertTrue(help.contains("run_batch"))
    }

    func testGetInterfaceHelpDescribesCurrentContract() {
        let help = GetInterfaceCommand.helpMessage()

        XCTAssertTrue(help.contains("Read the app accessibility hierarchy"), help)
    }

    func testGetInterfaceRejectsUnknownOption() {
        XCTAssertThrowsError(try GetInterfaceCommand.parse(["--unknown-option"]))
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

    func testTypeTextRejectsUnknownOption() {
        XCTAssertThrowsError(try TypeCommand.parse(["--unknown-option", "hello"]))
    }

    func testFenceExpectationArgumentContractRejectsShorthand() {
        XCTAssertThrowsError(try TheFence.parseExpectationArgument("screen_changed")) { error in
            XCTAssertTrue(String(describing: error).contains("Expected expectation JSON object"))
        }
    }

    func testFenceExpectationArgumentContractAcceptsJsonObject() throws {
        let parsed = try TheFence.parseExpectationArgument(#"{"type":"element_updated","property":"value"}"#)

        guard case .object(let object) = parsed else {
            return XCTFail("expected object expectation")
        }
        XCTAssertEqual(object["type"], .string("element_updated"))
        XCTAssertEqual(object["property"], .string("value"))
    }

    func testFenceExpectationArgumentContractRejectsUnknownString() {
        XCTAssertThrowsError(try TheFence.parseExpectationArgument("layout_changed"))
    }

    func testHumanParserRejectsExpectationShortcut() {
        XCTAssertThrowsError(try ReplSession.parseHumanInput("wait_for_change expect=screen_changed")) { error in
            XCTAssertTrue(String(describing: error).contains("Expected expectation JSON object"))
        }
    }

    func testHumanParserNormalizesChangeExpectationJsonObject() throws {
        let request = try ReplSession.parseHumanInput(#"wait_for_change expect='{"type":"elements_changed"}'"#)
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

    func testRunBatchRejectsUnknownSerializedCommandAtEdge() {
        XCTAssertThrowsError(
            try RunBatchCommand.serializedBatchSteps(
                inline: #"[{"command":"not_a_command"}]"#,
                fromFile: nil
            )
        ) { error in
            XCTAssertTrue(
                CLIRequestBuilder.diagnosticMessage(for: error).contains("Unknown command 'not_a_command'"),
                CLIRequestBuilder.diagnosticMessage(for: error)
            )
        }
    }

    func testRunBatchRejectsNestedRunBatchCommandAtEdge() {
        XCTAssertThrowsError(
            try RunBatchCommand.serializedBatchSteps(
                inline: #"[{"command":"run_batch","steps":[]}]"#,
                fromFile: nil
            )
        ) { error in
            XCTAssertTrue(
                CLIRequestBuilder.diagnosticMessage(for: error).contains("steps[0] command 'run_batch' is not supported in run_batch"),
                CLIRequestBuilder.diagnosticMessage(for: error)
            )
        }
    }

    func testRunBatchRejectsUnknownSerializedParameterAtEdge() {
        XCTAssertThrowsError(
            try RunBatchCommand.serializedBatchSteps(
                inline: #"[{"command":"scroll","unexpected":"value","label":"Done"}]"#,
                fromFile: nil
            )
        ) { error in
            XCTAssertTrue(
                CLIRequestBuilder.diagnosticMessage(for: error).contains("Unknown parameter 'unexpected' for scroll"),
                CLIRequestBuilder.diagnosticMessage(for: error)
            )
        }
    }

    func testHumanParserPreservesKnownStringParameterValues() throws {
        let request = try ReplSession.parseHumanInput("set_pasteboard text=false")

        XCTAssertEqual(request[.command] as? String, TheFence.Command.setPasteboard.rawValue)
        XCTAssertEqual(request[.text] as? String, "false")
    }

    func testHumanParserCoercesKnownBooleanParametersOnly() throws {
        let request = try ReplSession.parseHumanInput("wait_for label=true absent=true")

        XCTAssertEqual(request[.command] as? String, TheFence.Command.waitFor.rawValue)
        XCTAssertEqual(request[.label] as? String, "true")
        XCTAssertEqual(request[.absent] as? Bool, true)
    }

    func testSharedRequestBuilderParsesCanonicalMachineJSON() throws {
        let parsed = try CLIRequestBuilder.parsedRequest(
            from: #"{"command":"type_text","text":"hello"}"#
        )

        XCTAssertEqual(parsed.mode, .machine)
        XCTAssertEqual(parsed.request[.command] as? String, TheFence.Command.typeText.rawValue)
        XCTAssertEqual(parsed.request[.text] as? String, "hello")
        XCTAssertEqual(parsed.command, .typeText)
    }

    func testSharedRequestBuilderParsesTypedMachineRequestId() throws {
        let parsed = try CLIRequestBuilder.parsedRequest(
            from: #"{"id":9223372036854775807,"command":"type_text","text":"hello"}"#
        )

        XCTAssertEqual(parsed.requestId, .signedInteger(Int64.max))
    }

    func testSharedRequestBuilderRejectsNonScalarMachineRequestId() {
        XCTAssertThrowsError(
            try CLIRequestBuilder.parsedRequest(
                from: #"{"id":{"nested":true},"command":"type_text","text":"hello"}"#
            )
        ) { error in
            XCTAssertTrue(
                CLIRequestBuilder.diagnosticMessage(for: error).contains("Public JSON request id must be a finite JSON scalar"),
                CLIRequestBuilder.diagnosticMessage(for: error)
            )
        }
    }

    func testSharedRequestBuilderRejectsHumanTextInJSONSessionMode() {
        XCTAssertThrowsError(
            try CLIRequestBuilder.parsedRequest(from: "activate button_save", acceptsHumanInput: false)
        ) { error in
            XCTAssertTrue(
                CLIRequestBuilder.diagnosticMessage(for: error).contains("Expected JSON object input"),
                CLIRequestBuilder.diagnosticMessage(for: error)
            )
        }
    }

    func testSharedRequestBuilderAcceptsCanonicalMachineJSONInJSONSessionMode() throws {
        let parsed = try CLIRequestBuilder.parsedRequest(
            from: #"{"command":"activate","heistId":"button_save"}"#,
            acceptsHumanInput: false
        )

        XCTAssertEqual(parsed.mode, .machine)
        XCTAssertEqual(parsed.command, .activate)
        XCTAssertEqual(parsed.request[.heistId] as? String, "button_save")
    }

    func testSharedRequestBuilderParsesHumanCommand() throws {
        let parsed = try CLIRequestBuilder.parsedRequest(from: "get_screen")

        XCTAssertEqual(parsed.mode, .human)
        XCTAssertEqual(parsed.command, .getScreen)
        XCTAssertEqual(parsed.request[.command] as? String, TheFence.Command.getScreen.rawValue)
    }

    func testSharedRequestBuilderAttachesDescriptorForCanonicalMachineJSON() throws {
        let parsed = try CLIRequestBuilder.parsedRequest(from: #"{"command":"type_text","text":"hello"}"#)

        XCTAssertEqual(parsed.mode, .machine)
        XCTAssertEqual(parsed.command, .typeText)
        XCTAssertEqual(parsed.request[.command] as? String, TheFence.Command.typeText.rawValue)
        XCTAssertEqual(parsed.request[.text] as? String, "hello")
    }

    func testSharedRequestBuilderRejectsUnknownHumanCommand() {
        XCTAssertThrowsError(
            try CLIRequestBuilder.parsedRequest(from: "not_a_command label=Save")
        ) { error in
            XCTAssertTrue(
                CLIRequestBuilder.diagnosticMessage(for: error).contains("Unknown command 'not_a_command'"),
                CLIRequestBuilder.diagnosticMessage(for: error)
            )
        }
    }

    func testSharedRequestBuilderRejectsUnknownHumanParameter() {
        XCTAssertThrowsError(
            try CLIRequestBuilder.parsedRequest(from: "activate bogus=Save")
        ) { error in
            XCTAssertTrue(
                CLIRequestBuilder.diagnosticMessage(for: error).contains("Unknown parameter 'bogus' for activate"),
                CLIRequestBuilder.diagnosticMessage(for: error)
            )
        }
    }

    func testSharedRequestBuilderRejectsInvalidHumanParameterValue() {
        XCTAssertThrowsError(
            try CLIRequestBuilder.parsedRequest(from: "wait_for absent=maybe")
        ) { error in
            XCTAssertTrue(
                CLIRequestBuilder.diagnosticMessage(for: error).contains("Invalid value 'maybe' for absent"),
                CLIRequestBuilder.diagnosticMessage(for: error)
            )
        }
    }

    func testREPLParsesPositionalActivateTarget() throws {
        let replRequest = try ReplSession.parseHumanInput("activate button_save")

        XCTAssertEqual(replRequest[.command] as? String, TheFence.Command.activate.rawValue)
        XCTAssertEqual(replRequest[.heistId] as? String, "button_save")
    }

    func testREPLParsesCoordinateGesture() throws {
        let replRequest = try ReplSession.parseHumanInput("one_finger_tap x=100 y=200")

        XCTAssertEqual(replRequest[.command] as? String, TheFence.Command.oneFingerTap.rawValue)
        XCTAssertEqual(replRequest[.x] as? Double, 100)
        XCTAssertEqual(replRequest[.y] as? Double, 200)
    }

    func testHumanParserUsesCatalogPositionalDirectionSyntax() throws {
        let request = try ReplSession.parseHumanInput("swipe up checkout_list")

        XCTAssertEqual(request[.command] as? String, TheFence.Command.swipe.rawValue)
        XCTAssertEqual(request[.direction] as? String, "up")
        XCTAssertEqual(request[.heistId] as? String, "checkout_list")
    }

    func testHumanParserUsesCatalogPositionalEdgeSyntax() throws {
        let request = try ReplSession.parseHumanInput("scroll_to_edge top checkout_list")

        XCTAssertEqual(request[.command] as? String, TheFence.Command.scrollToEdge.rawValue)
        XCTAssertEqual(request[.edge] as? String, "top")
        XCTAssertEqual(request[.heistId] as? String, "checkout_list")
    }

    func testScrollCLIAllowsNoElementTarget() throws {
        let command = try ScrollCommand.parse([])

        XCTAssertNil(command.element.target)
        XCTAssertNil(command.stableId)
        XCTAssertEqual(command.direction, "down")
    }

    func testScrollCLIParsesContainerStableId() throws {
        let command = try ScrollCommand.parse(["--stable-id", "main_scroll", "--direction", "up"])

        XCTAssertEqual(command.stableId, "main_scroll")
        XCTAssertEqual(command.direction, "up")
    }

    func testScrollToEdgeCLIAllowsNoElementTargetAndDefaultsTop() throws {
        let command = try ScrollToEdgeCommand.parse([])

        XCTAssertNil(command.element.target)
        XCTAssertNil(command.stableId)
        XCTAssertEqual(command.edge, "top")
    }

    func testHumanParserMapsCoordinateTapCanonicalCommand() throws {
        let request = try ReplSession.parseHumanInput("one_finger_tap x=100 y=200")

        XCTAssertEqual(request[.command] as? String, TheFence.Command.oneFingerTap.rawValue)
        XCTAssertEqual(request[.x] as? Double, 100)
        XCTAssertEqual(request[.y] as? Double, 200)
    }

    func testHumanParserMapsHeistIdPositionalTarget() throws {
        let request = try ReplSession.parseHumanInput("activate button_save")

        XCTAssertEqual(request[.command] as? String, TheFence.Command.activate.rawValue)
        XCTAssertEqual(request[.heistId] as? String, "button_save")
    }

    private func topLevelCommandNames() -> [String] {
        ButtonHeistApp.configuration.subcommands.map { commandType in
            commandType.configuration.commandName ?? String(describing: commandType)
        }
    }
}
