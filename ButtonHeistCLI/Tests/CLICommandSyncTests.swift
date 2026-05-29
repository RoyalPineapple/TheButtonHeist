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
        let help = TheFence.Command.cliSessionHelp

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
        XCTAssertThrowsError(try CLIRequestBuilder.parsedRequest(from: "wait_for_change expect=screen_changed")) { error in
            XCTAssertTrue(String(describing: error).contains("Expected expectation JSON object"))
        }
    }

    func testHumanParserPreservesChangeExpectationJsonObjectForRequestParsing() throws {
        let operation = try CLIRequestBuilder
            .parsedRequest(from: #"wait_for_change expect='{"type":"elements_changed"}'"#)
            .operation

        XCTAssertEqual(operation.command, .waitForChange)
        XCTAssertEqual(operation.argument(.expect), .object(["type": .string("elements_changed")]))
    }

    func testRunBatchSerializesStepsBeforeSending() throws {
        let steps = try RunBatchCommand.serializedBatchSteps(
            inline: #"[{"command":"activate","target":{"heistId":"button-login"}}]"#,
            fromFile: nil
        )

        XCTAssertEqual(steps.count, 1)
        guard case .object(let object) = steps[0] else {
            return XCTFail("expected serialized batch step object")
        }
        XCTAssertEqual(object["command"], .string(TheFence.Command.activate.rawValue))
        XCTAssertEqual(object["target"], .object(["heistId": .string("button-login")]))
    }

    func testHumanParserPreservesKnownStringParameterValues() throws {
        let operation = try CLIRequestBuilder.parsedRequest(from: "set_pasteboard text=false").operation

        XCTAssertEqual(operation.command, .setPasteboard)
        XCTAssertEqual(operation.argument(.text), .string("false"))
    }

    func testHumanParserCoercesKnownBooleanParametersOnly() throws {
        let operation = try CLIRequestBuilder.parsedRequest(from: "wait_for loading-spinner absent=true").operation

        XCTAssertEqual(operation.command, .waitFor)
        XCTAssertEqual(operation.arguments.elementTarget, .heistId("loading-spinner"))
        XCTAssertEqual(operation.argument(.absent), .bool(true))
    }

    func testSharedRequestBuilderParsesCanonicalMachineJSON() throws {
        let parsed = try CLIRequestBuilder.parsedRequest(
            from: #"{"command":"type_text","text":"hello"}"#
        )

        XCTAssertEqual(parsed.mode, .machine)
        XCTAssertEqual(parsed.operation.command, .typeText)
        XCTAssertEqual(parsed.operation.argument(.text), .string("hello"))
        XCTAssertEqual(parsed.command, .typeText)
    }

    func testSharedRequestBuilderParsesStringMachineRequestIdAsMetadata() throws {
        let parsed = try CLIRequestBuilder.parsedRequest(
            from: #"{"id":"request-1","command":"type_text","text":"hello"}"#
        )

        XCTAssertEqual(parsed.requestId, .string("request-1"))
        XCTAssertNil(parsed.operation.arguments.argumentValues["id"])
        XCTAssertEqual(parsed.operation.argument(.text), .string("hello"))
    }

    func testSharedRequestBuilderParsesTypedMachineRequestId() throws {
        let parsed = try CLIRequestBuilder.parsedRequest(
            from: #"{"id":9223372036854775807,"command":"type_text","text":"hello"}"#
        )

        XCTAssertEqual(parsed.requestId, .signedInteger(Int64.max))
    }

    func testSharedRequestBuilderParsesNullMachineRequestId() throws {
        let parsed = try CLIRequestBuilder.parsedRequest(
            from: #"{"id":null,"command":"ping"}"#
        )

        XCTAssertEqual(parsed.requestId, .null)
        XCTAssertEqual(parsed.operation.command, .ping)
    }

    func testSharedRequestBuilderParsesUnsignedMachineRequestId() throws {
        let parsed = try CLIRequestBuilder.parsedRequest(
            from: #"{"id":18446744073709551615,"command":"ping"}"#
        )

        XCTAssertEqual(parsed.requestId, .unsignedInteger(UInt64.max))
    }

    func testSharedRequestBuilderParsesDecimalMachineRequestId() throws {
        let parsed = try CLIRequestBuilder.parsedRequest(
            from: #"{"id":1.25,"command":"ping"}"#
        )

        XCTAssertEqual(parsed.requestId, .double(1.25))
    }

    func testSharedRequestBuilderParsesWholeNumberDecimalMachineRequestId() throws {
        let parsed = try CLIRequestBuilder.parsedRequest(
            from: #"{"id":1.0,"command":"ping"}"#
        )

        XCTAssertEqual(parsed.requestId, .double(1.0))
    }

    func testSharedRequestBuilderRejectsNonScalarMachineRequestId() {
        XCTAssertThrowsError(
            try CLIRequestBuilder.parsedRequest(
                from: #"{"id":{"nested":true},"command":"type_text","text":"hello"}"#
            )
        ) { error in
            XCTAssertTrue(
                CLIRequestBuilder.diagnosticMessage(for: error).contains("Public JSON request id must be string"),
                CLIRequestBuilder.diagnosticMessage(for: error)
            )
        }
    }

    func testSharedRequestBuilderRejectsBoolMachineRequestId() {
        XCTAssertThrowsError(
            try CLIRequestBuilder.parsedRequest(
                from: #"{"id":true,"command":"ping"}"#
            )
        ) { error in
            XCTAssertTrue(
                CLIRequestBuilder.diagnosticMessage(for: error).contains("does not support bool"),
                CLIRequestBuilder.diagnosticMessage(for: error)
            )
        }
    }

    func testSharedRequestBuilderRejectsArrayMachineRequestId() {
        XCTAssertThrowsError(
            try CLIRequestBuilder.parsedRequest(
                from: #"{"id":["r1"],"command":"ping"}"#
            )
        ) { error in
            XCTAssertTrue(
                CLIRequestBuilder.diagnosticMessage(for: error).contains("Public JSON request id"),
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
            from: #"{"command":"activate","target":{"heistId":"button_save"}}"#,
            acceptsHumanInput: false
        )

        XCTAssertEqual(parsed.mode, .machine)
        XCTAssertEqual(parsed.command, .activate)
        guard case .object(let target)? = parsed.operation.argument(.target) else {
            return XCTFail("expected typed target object")
        }
        XCTAssertEqual(target["heistId"], .string("button_save"))
    }

    func testSharedRequestBuilderParsesHumanCommand() throws {
        let parsed = try CLIRequestBuilder.parsedRequest(from: "get_screen")

        XCTAssertEqual(parsed.mode, .human)
        XCTAssertEqual(parsed.command, .getScreen)
        XCTAssertEqual(parsed.operation.command, .getScreen)
    }

    func testSharedRequestBuilderAttachesDescriptorForCanonicalMachineJSON() throws {
        let parsed = try CLIRequestBuilder.parsedRequest(from: #"{"command":"type_text","text":"hello"}"#)

        XCTAssertEqual(parsed.mode, .machine)
        XCTAssertEqual(parsed.command, .typeText)
        XCTAssertEqual(parsed.operation.command, .typeText)
        XCTAssertEqual(parsed.operation.argument(.text), .string("hello"))
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

    func testHumanParserParsesPositionalActivateTarget() throws {
        let operation = try CLIRequestBuilder.parsedRequest(from: "activate button_save").operation

        XCTAssertEqual(operation.command, .activate)
        XCTAssertEqual(operation.arguments.elementTarget, .heistId("button_save"))
    }

    func testCLIBuilderCarriesMatcherTargetAsTypedTarget() throws {
        let expectedTarget = ElementTarget.matcher(
            ElementMatcher(label: "Rotor Host", identifier: "rotor.host", traits: [.button]),
            ordinal: 1
        )
        let operation = try CLIRequestBuilder.operation(
            command: .activate,
            target: expectedTarget
        )

        XCTAssertEqual(operation.arguments.elementTarget, expectedTarget)
        XCTAssertNil(operation.argument(.target))
    }

    func testHumanParserParsesCoordinateGesture() throws {
        let operation = try CLIRequestBuilder.parsedRequest(from: "one_finger_tap x=100 y=200").operation

        XCTAssertEqual(operation.command, .oneFingerTap)
        XCTAssertEqual(operation.argument(.x), .double(100))
        XCTAssertEqual(operation.argument(.y), .double(200))
    }

    func testHumanParserUsesCatalogPositionalDirectionSyntax() throws {
        let operation = try CLIRequestBuilder.parsedRequest(from: "swipe up checkout_list").operation

        XCTAssertEqual(operation.command, .swipe)
        XCTAssertEqual(operation.argument(.direction), .string("up"))
        XCTAssertEqual(operation.arguments.elementTarget, .heistId("checkout_list"))
    }

    func testHumanParserUsesCatalogPositionalEdgeSyntax() throws {
        let operation = try CLIRequestBuilder.parsedRequest(from: "scroll_to_edge top checkout_list").operation

        XCTAssertEqual(operation.command, .scrollToEdge)
        XCTAssertEqual(operation.argument(.edge), .string("top"))
        XCTAssertEqual(operation.arguments.elementTarget, .heistId("checkout_list"))
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
        let operation = try CLIRequestBuilder.parsedRequest(from: "one_finger_tap x=100 y=200").operation

        XCTAssertEqual(operation.command, .oneFingerTap)
        XCTAssertEqual(operation.argument(.x), .double(100))
        XCTAssertEqual(operation.argument(.y), .double(200))
    }

    func testHumanParserMapsHeistIdPositionalTarget() throws {
        let operation = try CLIRequestBuilder.parsedRequest(from: "activate button_save").operation

        XCTAssertEqual(operation.command, .activate)
        XCTAssertEqual(operation.arguments.elementTarget, .heistId("button_save"))
    }

    func testHumanParserRejectsDuplicateElementTarget() {
        XCTAssertThrowsError(
            try CLIRequestBuilder.parsedRequest(from: "activate button_save target=button_cancel")
        ) { error in
            XCTAssertTrue(
                CLIRequestBuilder.diagnosticMessage(for: error).contains("Element target specified more than once"),
                CLIRequestBuilder.diagnosticMessage(for: error)
            )
        }
    }

    func testHumanParserRejectsTargetForCommandWithoutTargetParameter() {
        XCTAssertThrowsError(
            try CLIRequestBuilder.parsedRequest(from: "get_screen target=button_save")
        ) { error in
            XCTAssertTrue(
                CLIRequestBuilder.diagnosticMessage(for: error).contains("Unknown parameter 'target' for get_screen"),
                CLIRequestBuilder.diagnosticMessage(for: error)
            )
        }
    }

    private func topLevelCommandNames() -> [String] {
        ButtonHeistApp.configuration.subcommands.map { commandType in
            commandType.configuration.commandName ?? String(describing: commandType)
        }
    }
}

private extension NormalizedOperation {
    func argument(_ key: FenceParameterKey) -> HeistValue? {
        arguments.argumentValues[key.rawValue]
    }
}
