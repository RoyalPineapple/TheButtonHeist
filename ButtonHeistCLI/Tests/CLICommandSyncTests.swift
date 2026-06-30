import XCTest
@_spi(ButtonHeistTooling) import ButtonHeist
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

    func testCommandSourcesUseCentralArgumentWriterForRequestConstruction() throws {
        let commandsURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("Commands", isDirectory: true)
        let commandFiles = try FileManager.default.contentsOfDirectory(
            at: commandsURL,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(commandFiles.isEmpty, "Expected CLI command source files")

        let disallowedPatterns = [
            ("mutable CLIRequestParameters", #"var\s+\w+\s*=\s*CLIRequestParameters\(\)"#),
            ("manual request mutation", #"\.\s*set\s*\("#),
            ("raw CLIRequestObject dictionary literal", #"CLIRequestObject\s*\(\s*\["#),
        ]
        for fileURL in commandFiles {
            let source = try String(contentsOf: fileURL)
            for (description, pattern) in disallowedPatterns {
                let regex = try NSRegularExpression(pattern: pattern)
                let range = NSRange(source.startIndex..<source.endIndex, in: source)
                guard let match = regex.firstMatch(in: source, range: range),
                      let matchRange = Range(match.range, in: source) else {
                    continue
                }
                let snippet = source[matchRange].replacingOccurrences(of: "\n", with: "\\n")
                XCTFail("\(fileURL.lastPathComponent) contains \(description): \(snippet)")
            }
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

    func testGetInterfaceAcceptsDiscoveryLimitOptions() throws {
        let command = try GetInterfaceCommand.parse([
            "--max-scrolls-per-container", "25",
            "--max-scrolls-per-discovery", "40",
        ])

        XCTAssertEqual(command.discoveryLimits.maxScrollsPerContainer, 25)
        XCTAssertEqual(command.discoveryLimits.maxScrollsPerDiscovery, 40)
        XCTAssertEqual(command.discoveryLimits.parameters[.maxScrollsPerContainer], .int(25))
        XCTAssertEqual(command.discoveryLimits.parameters[.maxScrollsPerDiscovery], .int(40))
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
        let command = try WaitCommand.parse(["--change", "screen"])

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
        let parsed = try TheFence.parseExpectationArgument(
            #"{"type":"change","scopes":[{"type":"elements","assertions":[{"type":"updated","property":"value"}]}]}"#
        )

        guard case .object(let object) = parsed else {
            return XCTFail("expected object expectation")
        }
        XCTAssertEqual(object["type"], .string("change"))
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
        let arguments = try RunHeistCommand.planArguments(
            inline: source,
            path: nil,
            entry: nil,
            commandName: "describe_heist"
        ).adding(
            CommandArgumentWriter.value(.heist, "flow")
        )

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
            let failure = requestBuildFailure(from: error)
            XCTAssertTrue(
                failure.message.contains("Public JSON request id must be string"),
                failure.message
            )
            XCTAssertEqual(failure.details.code, FailureCode(.requestInvalid))
        }
    }

    func testSharedRequestBuilderRejectsBoolMachineRequestId() {
        XCTAssertThrowsError(
            try CLIRequestBuilder.parsedRequest(
                from: #"{"id":true,"command":"ping"}"#
            )
        ) { error in
            let failure = requestBuildFailure(from: error)
            XCTAssertTrue(
                failure.message.contains("does not support bool"),
                failure.message
            )
            XCTAssertEqual(failure.details.code, FailureCode(.requestInvalid))
        }
    }

    func testSharedRequestBuilderRejectsArrayMachineRequestId() {
        XCTAssertThrowsError(
            try CLIRequestBuilder.parsedRequest(
                from: #"{"id":["r1"],"command":"ping"}"#
            )
        ) { error in
            let failure = requestBuildFailure(from: error)
            XCTAssertTrue(
                failure.message.contains("Public JSON request id"),
                failure.message
            )
            XCTAssertEqual(failure.details.code, FailureCode(.requestInvalid))
        }
    }

    func testSharedRequestBuilderRejectsHumanTextInJSONLinesMode() {
        XCTAssertThrowsError(
            try CLIRequestBuilder.parsedRequest(from: "activate button_save")
        ) { error in
            let failure = requestBuildFailure(from: error)
            XCTAssertTrue(
                failure.message.contains("Expected JSON object input"),
                failure.message
            )
            XCTAssertEqual(failure.details.code, FailureCode(.requestInvalid))
        }
    }

    func testSharedRequestBuilderRejectsMalformedMachineJSON() {
        XCTAssertThrowsError(
            try CLIRequestBuilder.parsedRequest(from: #"{"command":"ping","#)
        ) { error in
            let failure = requestBuildFailure(from: error)
            let message = failure.message
            XCTAssertTrue(message.contains("Public JSON request is not valid JSON"), message)
            XCTAssertEqual(failure.details.code, FailureCode(.requestInvalid))
        }
    }

    func testSharedRequestBuilderAcceptsValidPingRequest() throws {
        let parsed = try CLIRequestBuilder.parsedRequest(from: #"{"command":"ping"}"#)

        XCTAssertEqual(parsed.command, .ping)
        XCTAssertNil(parsed.requestId)
    }

    func testSharedRequestBuilderAcceptsCanonicalMachineJSONInJSONLinesMode() throws {
        let parsed = try CLIRequestBuilder.parsedRequest(
            from: #"{"command":"activate","target":{"identifier":{"mode":"exact","value":"button_save"}}}"#
        )

        XCTAssertEqual(parsed.command, .activate)
        guard case .object(let target)? = parsed.argument(.target) else {
            return XCTFail("expected typed target object")
        }
        XCTAssertEqual(target["identifier"], .object([
            "mode": .string("exact"),
            "value": .string("button_save"),
        ]))
    }

    func testSharedRequestBuilderRejectsWaitTimeoutAtOrBelowZeroInJSONLinesMode() {
        for timeout in ["0", "-1"] {
            XCTAssertThrowsError(
                try CLIRequestBuilder.parsedRequest(
                    from: #"{"command":"wait","predicate":{"type":"change","scopes":[{"type":"screen"}]},"timeout":\#(timeout)}"#
                )
            ) { error in
                let failure = requestBuildFailure(from: error)
                let message = failure.message
                XCTAssertTrue(message.contains("schema validation failed for timeout"), message)
                XCTAssertTrue(message.contains("expected number > 0"), message)
                XCTAssertEqual(failure.details.code, FailureCode(.requestValidationError))
            }
        }
    }

    func testSharedRequestBuilderRejectsWaitTimeoutAboveThirtyInJSONLinesMode() {
        XCTAssertThrowsError(
            try CLIRequestBuilder.parsedRequest(
                from: #"{"command":"wait","predicate":{"type":"change","scopes":[{"type":"screen"}]},"timeout":31}"#
            )
        ) { error in
            let failure = requestBuildFailure(from: error)
            let message = failure.message
            XCTAssertTrue(message.contains("schema validation failed for timeout"), message)
            XCTAssertTrue(message.contains("expected number in 0...30"), message)
            XCTAssertEqual(failure.details.code, FailureCode(.requestValidationError))
        }
    }

    func testSharedRequestBuilderRoutesValidWaitInJSONLinesMode() throws {
        let parsed = try CLIRequestBuilder.parsedRequest(
            from: #"{"command":"wait","predicate":{"type":"change","scopes":[{"type":"screen"}]},"timeout":5}"#
        )

        XCTAssertEqual(parsed.command, .wait)
        XCTAssertEqual(parsed.argument(.timeout), .int(5))
    }

    func testSharedRequestBuilderRejectsMCPOnlyPerformInJSONLinesMode() {
        XCTAssertThrowsError(
            try CLIRequestBuilder.parsedRequest(
                from: #"{"command":"perform","step":"Activate(.label(\"Pay\"))"}"#
            )
        ) { error in
            let failure = requestBuildFailure(from: error)
            let message = failure.message
            XCTAssertTrue(
                message.contains(#"JSON input command "perform" is not supported"#),
                message
            )
            XCTAssertEqual(failure.details.code, FailureCode(.requestInvalid))
        }
    }

    func testSharedRequestBuilderAcceptsRunHeistInJSONLinesMode() throws {
        let parsed = try CLIRequestBuilder.parsedRequest(
            from: #"{"command":"run_heist","plan":"HeistPlan(\"one\") { Warn(\"check\") }"}"#
        )

        XCTAssertEqual(parsed.command, .runHeist)
        XCTAssertEqual(parsed.argument(.plan), .string(#"HeistPlan("one") { Warn("check") }"#))
    }

    func testSharedRequestBuilderRejectsHugeMachineJSONLineBeforeDecoding() {
        let hugeText = String(repeating: "x", count: PublicJSONInputLimits.maxRequestBytes + 1)
        let line = "{\"command\":\"type_text\",\"text\":\"" + hugeText + "\"}"

        XCTAssertThrowsError(try CLIRequestBuilder.parsedRequest(from: line)) { error in
            let failure = requestBuildFailure(from: error)
            let message = failure.message
            XCTAssertTrue(
                message.contains("Public JSON request exceeds \(PublicJSONInputLimits.maxRequestBytes) bytes"),
                message
            )
            XCTAssertEqual(failure.details.code, FailureCode(.requestInvalid))
        }
    }

    func testSharedRequestBuilderRejectsDeeplyNestedMachineJSONBeforeDecoding() {
        var payload = "true"
        for index in 0..<PublicJSONInputLimits.maxNestingDepth {
            if index.isMultiple(of: 2) {
                payload = "{\"child\":\(payload)}"
            } else {
                payload = "[\(payload)]"
            }
        }
        let line = "{\"command\":\"ping\",\"payload\":\(payload)}"

        XCTAssertThrowsError(try CLIRequestBuilder.parsedRequest(from: line)) { error in
            let failure = requestBuildFailure(from: error)
            let message = failure.message
            XCTAssertTrue(
                message.contains(
                    "Public JSON request nesting depth exceeds \(PublicJSONInputLimits.maxNestingDepth)"
                ),
                message
            )
            XCTAssertEqual(failure.details.code, FailureCode(.requestInvalid))
        }
    }

    func testSharedRequestBuilderRejectsExcessiveMachineJSONKeyCountBeforeDecoding() {
        var fields = ["\"command\":\"ping\""]
        for index in 0..<PublicJSONInputLimits.maxTotalObjectKeys {
            fields.append("\"\(index)\":\(index)")
        }
        let line = "{\(fields.joined(separator: ","))}"

        XCTAssertThrowsError(try CLIRequestBuilder.parsedRequest(from: line)) { error in
            let failure = requestBuildFailure(from: error)
            let message = failure.message
            XCTAssertTrue(
                message.contains(
                    "Public JSON request object key count exceeds \(PublicJSONInputLimits.maxTotalObjectKeys)"
                ),
                message
            )
            XCTAssertEqual(failure.details.code, FailureCode(.requestInvalid))
        }
    }

    func testSharedRequestBuilderAttachesDescriptorForCanonicalMachineJSON() throws {
        let parsed = try CLIRequestBuilder.parsedRequest(from: #"{"command":"type_text","text":"hello"}"#)

        XCTAssertEqual(parsed.command, .typeText)
        XCTAssertEqual(parsed.argument(.text), .string("hello"))
    }

    func testCLIBuilderCarriesPredicateTargetAsPublicTargetArgument() throws {
        let expectedTarget = ElementTarget.predicate(
            ElementPredicate(
                label: "Rotor Host",
                identifier: "rotor.host",
                traits: [.selected, .button, .button],
                excludeTraits: [.notEnabled, .header]
            ),
            ordinal: 1
        )
        let arguments = CLIRequestBuilder.arguments(
            target: expectedTarget
        )

        XCTAssertEqual(arguments.argumentValues[FenceParameterKey.target.rawValue], .object([
            "label": .object([
                "mode": .string("exact"),
                "value": .string("Rotor Host"),
            ]),
            "identifier": .object([
                "mode": .string("exact"),
                "value": .string("rotor.host"),
            ]),
            "traits": .array([.string("button"), .string("selected")]),
            "excludeTraits": .array([.string("header"), .string("notEnabled")]),
            "ordinal": .int(1),
        ]))
    }

    func testScrollCLIAllowsNoElementTarget() throws {
        let command = try ScrollCommand.parse([])

        XCTAssertFalse(try command.selection.element.hasTarget)
        XCTAssertEqual(command.direction, "down")
    }

    func testScrollCLIAcceptsContainerName() throws {
        let command = try ScrollCommand.parse(["--container", "main_scroll", "--direction", "up"])

        XCTAssertEqual(command.selection.container, "main_scroll")
        XCTAssertEqual(command.direction, "up")
        XCTAssertFalse(try command.selection.element.hasTarget)
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

        XCTAssertFalse(try command.selection.element.hasTarget)
        XCTAssertEqual(command.edge, "top")
    }

    func testScrollToEdgeCLIAcceptsContainerName() throws {
        let command = try ScrollToEdgeCommand.parse(["--container", "main_scroll", "--edge", "bottom"])

        XCTAssertEqual(command.selection.container, "main_scroll")
        XCTAssertEqual(command.edge, "bottom")
        XCTAssertFalse(try command.selection.element.hasTarget)
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

    private func requestBuildFailure(
        from error: Error,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> DiagnosticFailure {
        guard let buildError = error as? CLIRequestBuildError else {
            XCTFail("expected CLIRequestBuildError, got \(error)", file: file, line: line)
            return DiagnosticFailure(
                message: String(describing: error),
                details: FailureDetails(code: .clientUnknown)
            )
        }
        return buildError.diagnosticFailure
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
