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

    func testJSONLinesHelpShowsCurrentUserCommands() {
        let help = TheFence.Command.cliJSONLinesHelp

        XCTAssertTrue(help.contains("activate"))
        XCTAssertTrue(help.contains("get_interface"))
        XCTAssertTrue(help.contains("run_batch"))
    }

    func testJSONLinesDefaultOutputIsCanonicalJSON() {
        XCTAssertEqual(JSONLinesDefaults.outputFormat, .json)
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

    func testConnectCommandUsesTypedDeviceOption() throws {
        let command = try ConnectCommand.parse([
            "--device",
            "127.0.0.1:1455",
            "--connect-timeout",
            "2.5",
            "--quiet",
        ])

        XCTAssertEqual(command.connection.device, "127.0.0.1:1455")
        XCTAssertEqual(command.connection.connectTimeout, 2.5)
        XCTAssertTrue(command.connection.quiet)
    }

    func testConnectCommandRejectsPositionalDevice() {
        XCTAssertThrowsError(try ConnectCommand.parse(["127.0.0.1:1455"]))
    }

    func testWaitCommandDefaultTimeoutIsTenSeconds() throws {
        let command = try WaitCommand.parse(["--changed", "screen_changed"])

        XCTAssertEqual(command.timeout, 10)
    }

    func testTypeTextRequiresText() {
        XCTAssertThrowsError(try TypeCommand.parse([]))
    }

    func testTypeTextRejectsEmptyText() throws {
        XCTAssertThrowsError(try TypeCommand.parse(["--text", ""]))
    }

    func testTypeTextRejectsUnknownOption() {
        XCTAssertThrowsError(try TypeCommand.parse(["--unknown-option", "--text", "hello"]))
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

    func testSharedRequestBuilderParsesCanonicalMachineJSON() throws {
        let parsed = try CLIRequestBuilder.parsedRequest(
            from: #"{"command":"type_text","text":"hello"}"#
        )

        XCTAssertEqual(parsed.command, .typeText)
        XCTAssertEqual(parsed.argument(.text), .string("hello"))
    }

    func testSharedRequestBuilderParsesStringMachineRequestIdAsMetadata() throws {
        let parsed = try CLIRequestBuilder.parsedRequest(
            from: #"{"id":"request-1","command":"type_text","text":"hello"}"#
        )

        XCTAssertEqual(parsed.requestId, .string("request-1"))
        XCTAssertNil(parsed.arguments.argumentValues["id"])
        XCTAssertEqual(parsed.argument(.text), .string("hello"))
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
        XCTAssertEqual(parsed.command, .ping)
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

    func testSharedRequestBuilderParsesWholeNumberMachineRequestIdAsInteger() throws {
        let parsed = try CLIRequestBuilder.parsedRequest(
            from: #"{"id":1.0,"command":"ping"}"#
        )

        XCTAssertEqual(parsed.requestId, .signedInteger(1))
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

    func testSharedRequestBuilderRejectsHumanTextInJSONLinesMode() {
        XCTAssertThrowsError(
            try CLIRequestBuilder.parsedRequest(from: "activate button_save")
        ) { error in
            XCTAssertTrue(
                CLIRequestBuilder.diagnosticMessage(for: error).contains("Expected JSON object input"),
                CLIRequestBuilder.diagnosticMessage(for: error)
            )
        }
    }

    func testSharedRequestBuilderAcceptsCanonicalMachineJSONInJSONLinesMode() throws {
        let parsed = try CLIRequestBuilder.parsedRequest(
            from: #"{"command":"activate","target":{"heistId":"button_save"}}"#
        )

        XCTAssertEqual(parsed.command, .activate)
        guard case .object(let target)? = parsed.argument(.target) else {
            return XCTFail("expected typed target object")
        }
        XCTAssertEqual(target["heistId"], .string("button_save"))
    }

    func testSharedRequestBuilderAttachesDescriptorForCanonicalMachineJSON() throws {
        let parsed = try CLIRequestBuilder.parsedRequest(from: #"{"command":"type_text","text":"hello"}"#)

        XCTAssertEqual(parsed.command, .typeText)
        XCTAssertEqual(parsed.argument(.text), .string("hello"))
    }

    func testCLIBuilderCarriesPredicateTargetAsTypedTarget() throws {
        let expectedTarget = ElementTarget.predicate(
            ElementPredicate(label: "Rotor Host", identifier: "rotor.host", traits: [.button]),
            ordinal: 1
        )
        let arguments = CLIRequestBuilder.arguments(
            target: expectedTarget
        )

        XCTAssertEqual(arguments.elementTarget, expectedTarget)
        XCTAssertNil(arguments.argumentValues[FenceParameterKey.target.rawValue])
    }

    func testScrollCLIAllowsNoElementTarget() throws {
        let command = try ScrollCommand.parse([])

        XCTAssertFalse(try command.element.hasTarget)
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

        XCTAssertFalse(try command.element.hasTarget)
        XCTAssertNil(command.stableId)
        XCTAssertEqual(command.edge, "top")
    }

    private func topLevelCommandNames() -> [String] {
        ButtonHeistApp.configuration.subcommands.map { commandType in
            commandType.configuration.commandName ?? String(describing: commandType)
        }
    }
}

private extension CLIParsedRequest {
    func argument(_ key: FenceParameterKey) -> HeistValue? {
        arguments.argumentValues[key.rawValue]
    }
}
