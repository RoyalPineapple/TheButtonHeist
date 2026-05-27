import XCTest
import ArgumentParser
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

    func testCLITopLevelCommandsMatchDescriptorIntent() {
        let cliOnlyCommands: Set<String> = ["session"]
        let expectedNames = Set(
            TheFence.Command.descriptors.compactMap { descriptor -> String? in
                guard case .directCommand = descriptor.cliExposure else { return nil }
                return descriptor.cliName
            }
        ).union(cliOnlyCommands)
        let actualNames = Set(topLevelCommandNames())

        XCTAssertEqual(
            actualNames,
            expectedNames,
            "Top-level CLI commands should be the descriptor directCommand projection plus CLI-only commands"
        )
    }

    func testCLIAdapterFenceCommandsMatchDirectDescriptorExposure() {
        let adapterFenceCommands = Set(
            ButtonHeistApp.configuration.subcommands.compactMap { commandType -> TheFence.Command? in
                (commandType as? CLICommandContract.Type)?.fenceCommand
            }
        )
        let directDescriptorCommands = Set(
            TheFence.Command.descriptors.compactMap { descriptor -> TheFence.Command? in
                guard case .directCommand = descriptor.cliExposure else { return nil }
                return descriptor.command
            }
        )
        let missingAdapters = directDescriptorCommands.subtracting(adapterFenceCommands)
        let extraAdapters = adapterFenceCommands.subtracting(directDescriptorCommands)

        XCTAssertTrue(
            missingAdapters.isEmpty,
            "Direct CLI descriptor commands missing adapters: \(missingAdapters.map(\.rawValue).sorted())"
        )
        XCTAssertTrue(
            extraAdapters.isEmpty,
            "CLI adapters expose commands not marked directCommand: \(extraAdapters.map(\.rawValue).sorted())"
        )
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

    func testGeneratedCommandReferenceUsesCLIDescriptorProjection() throws {
        let reference = try readRepositoryFile("docs/reference/commands.md")

        XCTAssertEqual(
            reference,
            FenceCommandReference.commandMarkdown(),
            "CLI command reference should be generated from FenceCommandDescriptor"
        )
        for descriptor in TheFence.Command.descriptors {
            guard let cliName = descriptor.cliName else { continue }
            XCTAssertTrue(
                reference.contains("`\(descriptor.canonicalName)`"),
                "Generated reference should include \(descriptor.canonicalName)"
            )
            XCTAssertTrue(
                reference.contains("`\(cliName)`"),
                "Generated reference should include descriptor-owned CLI name \(cliName)"
            )
        }
    }

    func testSessionHelpProjectsFromFenceDescriptors() {
        let help = ReplSession.humanHelp
        let exposedDescriptors = TheFence.Command.descriptors
            .filter { $0.cliExposure != .notExposed }

        for descriptor in exposedDescriptors {
            XCTAssertTrue(
                help.contains(descriptor.canonicalName),
                "REPL help should include descriptor command \(descriptor.canonicalName)"
            )
            XCTAssertTrue(
                help.contains(firstLine(of: descriptor.description)),
                "REPL help should include descriptor description for \(descriptor.canonicalName)"
            )

            for alias in descriptor.humanAliases.keys {
                XCTAssertTrue(
                    help.contains(alias),
                    "REPL help should include descriptor alias \(alias)"
                )
            }
        }

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

    func testFenceExpectationArgumentContractNormalizesShorthand() throws {
        let parsed = try TheFence.parseExpectationArgument("screen_changed")

        guard case .object(let object) = parsed else {
            return XCTFail("expected object expectation")
        }
        XCTAssertEqual(object["type"], .string("screen_changed"))
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

    func testHumanParserNormalizesChangeExpectationShortcut() throws {
        let request = try ReplSession.parseHumanInput("change expect=screen_changed")
        let expect = request[.expect] as? [String: Any]

        XCTAssertEqual(request[.command] as? String, TheFence.Command.waitForChange.rawValue)
        XCTAssertEqual(expect?[.type] as? String, "screen_changed")
    }

    func testHumanParserNormalizesChangeExpectationJsonObject() throws {
        let request = try ReplSession.parseHumanInput(#"change expect='{"type":"elements_changed"}'"#)
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

    func testHumanParserPreservesKnownStringParameterValues() throws {
        let request = try ReplSession.parseHumanInput("set_pasteboard text=false")

        XCTAssertEqual(request[.command] as? String, TheFence.Command.setPasteboard.rawValue)
        XCTAssertEqual(request[.text] as? String, "false")
    }

    func testHumanParserCoercesKnownBooleanParametersOnly() throws {
        let request = try ReplSession.parseHumanInput("wait label=true absent=true")

        XCTAssertEqual(request[.command] as? String, TheFence.Command.waitFor.rawValue)
        XCTAssertEqual(request[.label] as? String, "true")
        XCTAssertEqual(request[.absent] as? Bool, true)
    }

    func testHumanParserMapsCompoundCopyAlias() throws {
        let request = try ReplSession.parseHumanInput("copy")

        XCTAssertEqual(request[.command] as? String, TheFence.Command.editAction.rawValue)
        XCTAssertEqual(request[.action] as? String, EditAction.copy.rawValue)
    }

    func testHumanParserAliasesComeFromSharedCommandContract() throws {
        for (aliasName, alias) in TheFence.Command.humanCommandAliases {
            let request = try ReplSession.parseHumanInput(aliasName)

            XCTAssertEqual(
                request[.command] as? String,
                alias.command.rawValue,
                "\(aliasName) should resolve through TheFence.Command.humanCommandAliases"
            )
            for (key, value) in alias.parameters {
                assertRequestValue(
                    request[key],
                    equals: value,
                    "\(aliasName) should apply canonical alias parameter \(key.rawValue)"
                )
            }
        }
    }

    func testSharedRequestBuilderPreservesMachineJSONPassthrough() throws {
        let parsed = try CLIRequestBuilder.parsedRequest(
            from: #"{"command":"tap","id":7,"text":false}"#
        )

        XCTAssertEqual(parsed.mode, .machine)
        XCTAssertEqual(parsed.request[.command] as? String, "tap")
        XCTAssertEqual(parsed.request["id"] as? Int, 7)
        XCTAssertEqual(parsed.request[.text] as? Bool, false)
        XCTAssertNil(parsed.command, "Machine JSON should not resolve human aliases before Fence validation")
    }

    func testSharedRequestBuilderAttachesDescriptorForHumanCommandParsing() throws {
        let parsed = try CLIRequestBuilder.parsedRequest(from: "screenshot")

        XCTAssertEqual(parsed.mode, .human)
        XCTAssertEqual(parsed.command, .getScreen)
        XCTAssertEqual(parsed.descriptor?.canonicalName, TheFence.Command.getScreen.rawValue)
        XCTAssertEqual(parsed.request[.command] as? String, TheFence.Command.getScreen.rawValue)
    }

    func testSharedRequestBuilderAttachesDescriptorForCanonicalMachineJSON() throws {
        let parsed = try CLIRequestBuilder.parsedRequest(from: #"{"command":"quit","id":"repl-stop"}"#)

        XCTAssertEqual(parsed.mode, .machine)
        XCTAssertEqual(parsed.command, .quit)
        XCTAssertEqual(parsed.request[.command] as? String, TheFence.Command.quit.rawValue)
        XCTAssertEqual(parsed.request["id"] as? String, "repl-stop")
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
            try CLIRequestBuilder.parsedRequest(from: "wait absent=maybe")
        ) { error in
            XCTAssertTrue(
                CLIRequestBuilder.diagnosticMessage(for: error).contains("Invalid value 'maybe' for absent"),
                CLIRequestBuilder.diagnosticMessage(for: error)
            )
        }
    }

    func testREPLCanonicalCommandMatchesSharedCLIRequestShape() throws {
        let cliRequest = TheFence.Command.activate.cliRequest([.heistId: .string("button_save")])
        let replRequest = try ReplSession.parseHumanInput("activate button_save")

        XCTAssertEqual(replRequest[.command] as? String, cliRequest[.command] as? String)
        XCTAssertEqual(replRequest[.heistId] as? String, cliRequest[.heistId] as? String)
    }

    func testREPLAliasCommandMatchesSharedCLIRequestShape() throws {
        let cliRequest = CLIRequestBuilder.request(
            command: TheFence.Command.oneFingerTap,
            parameters: [.x: .double(100), .y: .double(200)]
        )
        let replRequest = try ReplSession.parseHumanInput("tap 100 200")

        XCTAssertEqual(replRequest[.command] as? String, cliRequest[.command] as? String)
        XCTAssertEqual(replRequest[.x] as? Double, cliRequest[.x] as? Double)
        XCTAssertEqual(replRequest[.y] as? Double, cliRequest[.y] as? Double)
    }

    func testHumanParserResolvesCanonicalCommandsThroughDescriptors() throws {
        for descriptor in TheFence.Command.descriptors {
            let request = try ReplSession.parseHumanInput(descriptor.canonicalName)

            XCTAssertEqual(
                request[.command] as? String,
                descriptor.command.rawValue,
                "\(descriptor.canonicalName) should resolve through the command descriptor catalog"
            )
        }
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

    func testHumanParserUsesCatalogTargetThenActionSyntax() throws {
        let request = try ReplSession.parseHumanInput("perform_custom_action checkout_button Magic Tap")

        XCTAssertEqual(request[.command] as? String, TheFence.Command.performCustomAction.rawValue)
        XCTAssertEqual(request[.heistId] as? String, "checkout_button")
        XCTAssertEqual(request[.action] as? String, "Magic Tap")
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

    func testScrollingCLIDefaultsProjectFromFenceParameterSpecs() throws {
        XCTAssertEqual(
            try ScrollCommand.parse([]).direction,
            catalogStringDefault(.scroll, .direction)
        )
        XCTAssertEqual(
            try ScrollToEdgeCommand.parse([]).edge,
            catalogStringDefault(.scrollToEdge, .edge)
        )
        XCTAssertEqual(
            try RotorCommand.parse(["button"]).direction,
            catalogStringDefault(.rotor, .direction)
        )
    }

    func testCLIChoiceHelpProjectsFromFenceParameterSpecs() {
        XCTAssertTrue(
            normalizedHelp(ScrollCommand.helpMessage()).contains(
                "Scroll direction: \(catalogEnumValues(.scroll, .direction)) (default: \(catalogStringDefault(.scroll, .direction)))"
            )
        )
        XCTAssertTrue(
            normalizedHelp(ScrollToEdgeCommand.helpMessage()).contains(
                "Edge to scroll to: \(catalogEnumValues(.scrollToEdge, .edge)) (default: \(catalogStringDefault(.scrollToEdge, .edge)))"
            )
        )
        XCTAssertTrue(
            normalizedHelp(RotorCommand.helpMessage()).contains(
                "Direction: \(catalogEnumValues(.rotor, .direction)) (default: \(catalogStringDefault(.rotor, .direction)))"
            )
        )
        XCTAssertTrue(
            normalizedHelp(EditActionCommand.helpMessage()).contains("Edit action: \(catalogEnumValues(.editAction, .action))")
        )
    }

    func testHumanParserMapsCoordinateTapAlias() throws {
        let request = try ReplSession.parseHumanInput("tap 100 200")

        XCTAssertEqual(request[.command] as? String, TheFence.Command.oneFingerTap.rawValue)
        XCTAssertEqual(request[.x] as? Double, 100)
        XCTAssertEqual(request[.y] as? Double, 200)
    }

    func testHumanParserMapsHeistIdPositionalTarget() throws {
        let request = try ReplSession.parseHumanInput("activate button_save")

        XCTAssertEqual(request[.command] as? String, TheFence.Command.activate.rawValue)
        XCTAssertEqual(request[.heistId] as? String, "button_save")
    }

    private func firstLine(of description: String) -> String {
        description
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""
    }

    private func normalizedHelp(_ help: String) -> String {
        help.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private func topLevelCommandNames() -> [String] {
        ButtonHeistApp.configuration.subcommands.map { commandType in
            commandType.configuration.commandName ?? String(describing: commandType)
        }
    }

    private func catalogStringDefault(
        _ command: TheFence.Command,
        _ key: FenceParameterKey,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> String {
        guard case .string(let value)? = command.defaultArgumentValue(for: key) else {
            XCTFail("Missing catalog string default for \(command.rawValue).\(key.rawValue)", file: file, line: line)
            return ""
        }
        return value
    }

    private func catalogEnumValues(
        _ command: TheFence.Command,
        _ key: FenceParameterKey,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> String {
        guard let values = command.parameter(named: key)?.enumValues else {
            XCTFail("Missing catalog enum values for \(command.rawValue).\(key.rawValue)", file: file, line: line)
            return ""
        }
        return values.joined(separator: ", ")
    }

    private func commandTypeIdentifiers(_ commandTypes: [ParsableCommand.Type]) -> [ObjectIdentifier] {
        commandTypes.map(ObjectIdentifier.init)
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let data = try Data(contentsOf: repositoryRoot().appendingPathComponent(relativePath))
        guard let contents = String(bytes: data, encoding: .utf8) else {
            XCTFail("\(relativePath) is not UTF-8")
            return ""
        }
        return contents
    }

    private func assertRequestValue(
        _ actual: Any?,
        equals expected: HeistValue,
        _ message: @autoclosure () -> String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch expected {
        case .string(let expectedValue):
            XCTAssertEqual(actual as? String, expectedValue, message(), file: file, line: line)
        case .int(let expectedValue):
            XCTAssertEqual(actual as? Int, expectedValue, message(), file: file, line: line)
        case .double(let expectedValue):
            XCTAssertEqual(actual as? Double, expectedValue, message(), file: file, line: line)
        case .bool(let expectedValue):
            XCTAssertEqual(actual as? Bool, expectedValue, message(), file: file, line: line)
        case .array(let expectedValue):
            XCTAssertEqual(
                (actual as? [Any])?.map { String(describing: $0) },
                expectedValue.map { String(describing: $0.cliRawValue) },
                message(),
                file: file,
                line: line
            )
        case .object(let expectedValue):
            XCTAssertEqual(
                (actual as? [String: Any])?.mapValues { String(describing: $0) },
                expectedValue.mapValues { String(describing: $0.cliRawValue) },
                message(),
                file: file,
                line: line
            )
        }
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private extension String {
    func removingSuffix(_ suffix: String) -> String {
        guard hasSuffix(suffix) else { return self }
        return String(dropLast(suffix.count))
    }

    func lowercasingFirstLetter() -> String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}
