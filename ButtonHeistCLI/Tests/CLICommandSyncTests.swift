import XCTest
import ButtonHeist
import Foundation
import ThePlans
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
        XCTAssertTrue(help.contains("run_heist"))
        XCTAssertTrue(help.contains("list_heists"))
        XCTAssertTrue(help.contains("describe_heist"))
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

    func testRunHeistForwardsInlineButtonHeistSource() throws {
        let source = #"HeistPlan("smoke") { Warn("Check login state") }"#
        let arguments = try RunHeistCommand.planArguments(
            inline: source
        )

        XCTAssertEqual(arguments[.plan], .string(source))
        XCTAssertNil(arguments[.version])
        XCTAssertNil(arguments[.body])
    }

    func testRunHeistRejectsEmptyInlineButtonHeistSource() {
        XCTAssertThrowsError(try RunHeistCommand.planArguments(inline: "   ")) { error in
            XCTAssertTrue(String(describing: error).contains("--plan must be ButtonHeist DSL source"))
        }
    }

    func testRunHeistDoesNotExpandRawJSONIRInlinePlan() throws {
        let rawJSON = #"{"version":1,"body":[{"type":"warn","warn":{"message":"x"}}]}"#
        let arguments = try RunHeistCommand.planArguments(inline: rawJSON)

        XCTAssertEqual(arguments[.plan], .string(rawJSON))
        XCTAssertNil(arguments[.version])
        XCTAssertNil(arguments[.body])
    }

    func testRunHeistRequiresExactlyOnePlanSource() {
        XCTAssertThrowsError(try RunHeistCommand.planArguments(inline: nil)) { error in
            XCTAssertTrue(String(describing: error).contains("Must supply --path or --plan"))
        }
        XCTAssertThrowsError(try RunHeistCommand.planArguments(
            inline: #"HeistPlan { Warn("x") }"#,
            path: "Flow.heist",
            entry: nil
        )) { error in
            XCTAssertTrue(String(describing: error).contains("mutually exclusive"))
        }
    }

    func testRunHeistForwardsArtifactPathToFenceWithoutReadingIt() throws {
        // The CLI must not read or re-encode the plan — it forwards the path so
        // the fence reads it into a HeistPlan. No version/body fields are sent.
        let arguments = try RunHeistCommand.planArguments(
            inline: nil,
            path: "Flow.heist",
            entry: nil
        )

        XCTAssertEqual(arguments[.path], .string("Flow.heist"))
        XCTAssertNil(arguments[.version])
        XCTAssertNil(arguments[.body])
    }

    func testRunHeistForwardsRootArgumentWithPathSource() throws {
        let arguments = try RunHeistCommand.planArguments(
            inline: nil,
            path: "Search.heist",
            entry: nil,
            argument: #"{"type":"string","value":"milk"}"#
        )

        XCTAssertEqual(arguments[.path], .string("Search.heist"))
        XCTAssertEqual(arguments[.argument], .object([
            "type": .string("string"),
            "value": .string("milk"),
        ]))
    }

    func testRunHeistForwardsRootArgumentWithInlineSource() throws {
        let source = """
        HeistPlan("search", parameter: .string("query")) {
            Warn("Check")
        }
        """
        let arguments = try RunHeistCommand.planArguments(
            inline: source,
            path: nil,
            entry: nil,
            argument: #"{"type":"string","value":"milk"}"#
        )

        XCTAssertEqual(arguments[.plan], .string(source))
        XCTAssertEqual(arguments[.argument], .object([
            "type": .string("string"),
            "value": .string("milk"),
        ]))
    }

    func testRunHeistCompilesSwiftSourceToTemporaryHeistArtifact() async throws {
        // Swift source compiles to a temp .heist the fence reads — the plan
        // crosses through the canonical codec, never a parameter round-trip.
        let plan = try HeistPlan(name: "swiftFlow", body: [.warn(WarnStep(message: "from swift"))])
        let prepared = try await RunHeistCommand.prepareInput(
            path: "Flow.swift",
            entry: "makeHeist",
            compileSwiftFile: { _, _ in .success(plan, diagnostics: []) }
        )
        defer { prepared.cleanup() }

        let artifactPath = try XCTUnwrap(prepared.path)
        XCTAssertTrue(artifactPath.hasSuffix(".heist"))
        XCTAssertNil(prepared.entry)

        // The compiled artifact round-trips losslessly through the canonical codec.
        let artifact = try HeistArtifactCodec.read(from: URL(fileURLWithPath: artifactPath))
        XCTAssertEqual(artifact.plan, plan)
        XCTAssertEqual(artifact.manifest.entry, "swiftFlow")

        // And it dispatches as a .heist path, not inline version/body params.
        let arguments = try RunHeistCommand.planArguments(
            inline: nil,
            path: prepared.path,
            entry: prepared.entry
        )
        XCTAssertEqual(arguments[.path], .string(artifactPath))
        XCTAssertNil(arguments[.version])
    }

    func testRunHeistSwiftSourceRequiresEntry() async {
        do {
            _ = try await RunHeistCommand.prepareInput(path: "Flow.swift", entry: nil)
            XCTFail("Expected missing entry to throw")
        } catch {
            XCTAssertTrue(String(describing: error).contains("--entry is required for Swift source input"))
        }
    }

    func testListHeistsUsesRunHeistPlanSourceShape() throws {
        let source = #"HeistPlan("flow") { Warn("Check") }"#
        let arguments = try RunHeistCommand.planArguments(
            inline: source,
            path: nil,
            entry: nil,
            commandName: "list_heists"
        )

        XCTAssertEqual(arguments[.plan], .string(source))
        XCTAssertNil(arguments[.version])
        XCTAssertNil(arguments[.path])
    }

    func testListHeistsDetailFlagDefaultsToSummary() throws {
        let command = try ListHeistsCommand.parse([
            "--plan",
            #"HeistPlan("flow") { Warn("Check") }"#,
        ])

        XCTAssertFalse(command.detail)
    }

    func testListHeistsDetailFlagRequestsDetailedMode() throws {
        let command = try ListHeistsCommand.parse([
            "--detail",
            "--plan",
            #"HeistPlan("flow") { Warn("Check") }"#,
        ])

        XCTAssertTrue(command.detail)
    }

    func testDescribeHeistAddsSelectorWithoutDroppingInlinePlanName() throws {
        let source = #"HeistPlan("flow") { Warn("Check") }"#
        var arguments = try RunHeistCommand.planArguments(
            inline: source,
            path: nil,
            entry: nil,
            commandName: "describe_heist"
        )
        arguments.set(.heist, "flow")

        XCTAssertEqual(arguments[.heist], .string("flow"))
        XCTAssertEqual(arguments[.plan], .string(source))
        XCTAssertNil(arguments[.version])
    }

    func testRunHeistRejectsEntryWithoutPath() {
        XCTAssertThrowsError(try RunHeistCommand.planArguments(
            inline: #"HeistPlan { Warn("x") }"#,
            path: nil,
            entry: "makeHeist"
        )) { error in
            XCTAssertTrue(String(describing: error).contains("--entry is only valid with Swift source input"))
        }
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
            from: #"{"command":"activate","target":{"identifier":"button_save"}}"#
        )

        XCTAssertEqual(parsed.command, .activate)
        guard case .object(let target)? = parsed.argument(.target) else {
            return XCTFail("expected typed target object")
        }
        XCTAssertEqual(target["identifier"], .string("button_save"))
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
        XCTAssertEqual(command.direction, "down")
    }

    func testScrollCLIAcceptsContainerName() throws {
        let command = try ScrollCommand.parse(["--container", "main_scroll", "--direction", "up"])

        XCTAssertEqual(command.container, "main_scroll")
        XCTAssertEqual(command.direction, "up")
        XCTAssertFalse(try command.element.hasTarget)
    }

    func testScrollCLIRejectsContainerNameWithElementTarget() {
        XCTAssertThrowsError(try ScrollCommand.parse(["--container", "main_scroll", "--label", "Item"]))
    }

    func testScrollCLIParsesDirection() throws {
        let command = try ScrollCommand.parse(["--direction", "up"])

        XCTAssertEqual(command.direction, "up")
    }

    func testScrollToEdgeCLIAllowsNoElementTargetAndDefaultsTop() throws {
        let command = try ScrollToEdgeCommand.parse([])

        XCTAssertFalse(try command.element.hasTarget)
        XCTAssertEqual(command.edge, "top")
    }

    func testScrollToEdgeCLIAcceptsContainerName() throws {
        let command = try ScrollToEdgeCommand.parse(["--container", "main_scroll", "--edge", "bottom"])

        XCTAssertEqual(command.container, "main_scroll")
        XCTAssertEqual(command.edge, "bottom")
        XCTAssertFalse(try command.element.hasTarget)
    }

    func testSwipeCLIHelpUsesDescriptorDirectionValues() {
        let help = SwipeSubcommand.helpMessage()

        XCTAssertTrue(help.contains("Swipe direction: up, down, left, right"), help)
    }

    private func topLevelCommandNames() -> [String] {
        ButtonHeistApp.configuration.subcommands.map { commandType in
            commandType.configuration.commandName ?? String(describing: commandType)
        }
    }
}

private final class TemporaryCLIDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("buttonheist-cli-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

private extension CLIParsedRequest {
    func argument(_ key: FenceParameterKey) -> HeistValue? {
        arguments.argumentValues[key.rawValue]
    }
}
