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

    func testTopLevelSubcommandsComeFromCLIAdapterCatalog() {
        XCTAssertEqual(
            commandTypeIdentifiers(ButtonHeistApp.configuration.subcommands),
            commandTypeIdentifiers(CLICommandAdapterCatalog.subcommands),
            "ButtonHeistApp should project subcommands from the CLI adapter catalog"
        )
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

    func testCLIAdapterCatalogMapsOnlyDirectFenceCommands() {
        for adapter in CLICommandAdapterCatalog.adapters {
            guard let descriptor = adapter.fenceDescriptor else { continue }
            XCTAssertEqual(
                descriptor.cliExposure,
                .directCommand,
                "\(adapter.commandType) maps to \(descriptor.canonicalName), which is not a direct CLI command"
            )
            XCTAssertEqual(
                descriptor.cliName,
                adapter.commandType.configuration.commandName,
                "\(adapter.commandType) should render the descriptor-owned CLI name"
            )
        }
    }

    func testCLIAdapterCatalogDoesNotPairTypesWithCommandCases() throws {
        let source = try readRepositoryFile("ButtonHeistCLI/Sources/Support/CLICommandContract.swift")
        let pairedCasePattern = #"\.fence\([^,\n]+,\s*\.[A-Za-z0-9_]+\)"#

        XCTAssertNil(
            source.range(of: pairedCasePattern, options: .regularExpression),
            "CLI adapter catalog should bind command types to Fence descriptors from the catalog, not paired command cases"
        )
        XCTAssertTrue(
            source.contains("TheFence.Command.descriptors"),
            "CLI adapter catalog should project command identity from FenceCommandDescriptor"
        )
        XCTAssertFalse(
            source.contains("directCommandTypesByDescriptorOrder"),
            "CLI adapter catalog should not rely on command-type order matching descriptor order"
        )
        XCTAssertFalse(
            source.contains("subcommandTypes"),
            "CLI adapter catalog should derive subcommand order from FenceCommandDescriptor exposure"
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

    func testCommandSourcesDoNotBypassFenceCommandRenderer() throws {
        let sourceFiles = try swiftSourceFiles(under: "ButtonHeistCLI/Sources/Commands")
            + swiftSourceFiles(under: "ButtonHeistCLI/Sources/Session")
            + swiftSourceFiles(under: "ButtonHeistCLI/Sources/Support")
        let disallowedPatterns = [
            #"commandName:\s*TheFence\.Command"#,
            #""command"\s*:\s*TheFence\.Command"#,
            #"TheFence\.Command\.[A-Za-z0-9_]+\.rawValue"#,
        ]
        let mirroredFenceKeys = descriptorParameterKeys.union(["command"])
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

    func testCLICommandContractDoesNotInferIdentityFromSwiftTypeNames() throws {
        let source = try readRepositoryFile("ButtonHeistCLI/Sources/Support/CLICommandContract.swift")

        XCTAssertFalse(
            source.contains("static var fenceCommand: TheFence.Command { get }"),
            "CLICommandContract should be a marker; command identity belongs to CLICommandAdapterCatalog and FenceCommandDescriptor"
        )
        XCTAssertFalse(
            source.contains("String(describing: Self.self)"),
            "CLI command identity should come from CLICommandAdapterCatalog and FenceCommandDescriptor"
        )
        XCTAssertFalse(
            source.contains("removingSuffix(\"Command\")"),
            "CLI command identity should not infer Fence commands from adapter type names"
        )
        XCTAssertFalse(
            source.contains("removingSuffix(\"Subcommand\")"),
            "CLI command identity should not infer Fence commands from adapter type names"
        )
    }

    func testReadmeDoesNotHandMaintainTopLevelCommandRegistry() throws {
        let contents = try readRepositoryFile("ButtonHeistCLI/README.md")
        let hardCodedCounts = regexFullMatches(
            in: contents,
            pattern: #"\b[0-9]+(?:\s+|-)(?:[A-Za-z-]+(?:\s+|-)){0,3}(?:commands?|cases?)\b"#
        )

        XCTAssertFalse(
            contents.contains("## Top-Level Commands"),
            "ButtonHeistCLI/README.md should not carry a second exhaustive command registry"
        )
        XCTAssertTrue(
            hardCodedCounts.isEmpty,
            "ButtonHeistCLI/README.md should not hard-code public command counts: \(hardCodedCounts)"
        )
        XCTAssertTrue(contents.contains("TheFence.Command"), "README should point to the Fence command contract")
        XCTAssertTrue(contents.contains("buttonheist --help"), "README should point users to generated CLI help")
        XCTAssertFalse(contents.contains("--index"), "README should document --ordinal, not stale --index")
        XCTAssertTrue(contents.contains("--ordinal"), "README should document the current ordinal selector option")
    }

    func testReadmeUsesOrdinalNotLegacyIndex() throws {
        let contents = try readRepositoryFile("ButtonHeistCLI/README.md")

        XCTAssertFalse(
            contents.contains("--index"),
            "ButtonHeistCLI/README.md should document --ordinal, not the removed --index flag"
        )
        XCTAssertTrue(contents.contains("--ordinal"), "README should document the current --ordinal flag")
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

        XCTAssertFalse(help.contains("Quick reference:"), "REPL help should not carry a hand-maintained command registry")
        XCTAssertFalse(help.contains("Inspect:"), "REPL help should not carry a hand-maintained command registry")
        XCTAssertFalse(help.contains("Gestures:"), "REPL help should not carry a hand-maintained command registry")
        XCTAssertFalse(help.contains("Scrolling:"), "REPL help should not carry a hand-maintained command registry")
    }

    func testSessionHelpUsesDescriptorCLINameProjectionForExposure() throws {
        let source = try readRepositoryFile("ButtonHeistCLI/Sources/Session/SessionRepl.swift")

        XCTAssertTrue(
            source.contains("TheFence.Command.cliSessionHelp"),
            "REPL help should project through the Fence-owned CLI help renderer"
        )
        XCTAssertFalse(
            source.contains("TheFence.Command.descriptors"),
            "REPL help should not scan command descriptors itself"
        )
        XCTAssertFalse(
            source.contains("descriptor.cliName"),
            "REPL help should not own CLI exposure projection"
        )
        XCTAssertFalse(
            source.contains("descriptor.cliExposure"),
            "REPL help should not reinterpret CLIExposure cases"
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

    func testHumanParserRejectsUnknownExpectationShortcutBeforeDispatch() {
        XCTAssertThrowsError(try CLIRequestBuilder.parsedRequest(from: "change expect=layout_changed")) { error in
            let message = CLIRequestBuilder.diagnosticMessage(for: error)

            XCTAssertTrue(
                message.contains("Invalid expectation 'layout_changed' for wait_for_change"),
                "Expected command-specific expectation parse failure, got: \(message)"
            )
            XCTAssertTrue(
                message.contains("Expected expectation shorthand"),
                "Expected valid expectation shape guidance, got: \(message)"
            )
        }
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

    func testCLIHasNoExpectationParserMirror() throws {
        let supportFiles = try swiftSourceFiles(under: "ButtonHeistCLI/Sources/Support")
        let parserFiles = supportFiles.filter { $0.lastPathComponent.contains("ExpectationArgumentParser") }

        XCTAssertTrue(
            parserFiles.isEmpty,
            "CLI expectation shorthand parsing should live in TheFence.parseExpectationArgument, not an adapter mirror"
        )

        let requestBuilderSource = try readRepositoryFile("ButtonHeistCLI/Sources/Support/CLIRequestBuilder.swift")
        XCTAssertFalse(
            requestBuilderSource.contains("parseExpectationArgument"),
            "Shared CLI request construction should not parse expectation shorthand directly"
        )
        XCTAssertTrue(
            requestBuilderSource.contains("FenceCommandDescriptor.humanRequest"),
            "Human REPL parsing should project requests through FenceCommandDescriptor"
        )

        let humanRequestSource = try readRepositoryFile(
            "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+HumanCommandRequest.swift"
        )
        XCTAssertTrue(
            humanRequestSource.contains("TheFence.parseExpectationArgument"),
            "Human request parsing should delegate expectation rules to TheFence"
        )

        let commandSource = try readRepositoryFile("ButtonHeistCLI/Sources/Commands/WaitForChangeCommand.swift")
        XCTAssertTrue(
            commandSource.contains("TheFence.parseExpectationArgument"),
            "Wait-for-change CLI parsing should delegate expectation rules to TheFence"
        )
    }

    func testSharedRequestBuilderDoesNotDeclareDescriptorLookupMirror() throws {
        let source = try readRepositoryFile("ButtonHeistCLI/Sources/Support/CLIRequestBuilder.swift")

        XCTAssertFalse(
            source.contains("extension FenceCommandDescriptor"),
            "CLI request building should use descriptor catalog APIs instead of private descriptor lookup extensions"
        )
        XCTAssertFalse(
            source.contains("TheFence.Command.descriptors.first"),
            "CLI request building should not scan descriptor catalogs directly"
        )
    }

    func testSharedRequestBuilderDoesNotInferParsedCommandFromRequestDictionary() throws {
        let source = try readRepositoryFile("ButtonHeistCLI/Sources/Support/CLIRequestBuilder.swift")

        XCTAssertFalse(
            source.contains("var commandName"),
            "Parsed request identity should be carried from the descriptor resolved during parsing"
        )
        XCTAssertFalse(
            source.contains("TheFence.Command.init(rawValue:)"),
            "Parsed request identity should not be inferred back out of the untyped request dictionary"
        )
        XCTAssertTrue(
            source.contains("let descriptor: FenceCommandDescriptor?"),
            "Parsed requests should retain the descriptor resolved by the parser"
        )
    }

    func testSharedRequestBuilderRendersCommandNameFromDescriptor() throws {
        let source = try readRepositoryFile("ButtonHeistCLI/Sources/Support/CLIRequestBuilder.swift")

        XCTAssertTrue(
            source.contains("command.descriptor.canonicalName"),
            "Shared CLI request rendering should project command names through FenceCommandDescriptor"
        )
        XCTAssertFalse(
            source.contains("request[.command] = command.rawValue"),
            "Shared CLI request rendering should not bypass FenceCommandDescriptor for command names"
        )
    }

    func testCLIAndREPLShareCanonicalRequestBuilding() {
        let parameters: CLIRequestParameters = [
            .heistId: .string("button_save"),
            .timeout: .double(2),
        ]
        let cliRequest = ActivateCommand.fenceRequest(parameters)
        let builderRequest = CLIRequestBuilder.request(
            command: TheFence.Command.activate,
            parameters: parameters
        )

        XCTAssertEqual(cliRequest[.command] as? String, builderRequest[.command] as? String)
        XCTAssertEqual(cliRequest[.heistId] as? String, builderRequest[.heistId] as? String)
        XCTAssertEqual(cliRequest[.timeout] as? Double, builderRequest[.timeout] as? Double)
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

    func testSessionReplDelegatesHumanParsingToSharedRequestBuilder() throws {
        let line = "swipe up checkout_list timeout=2"
        let replRequest = try ReplSession.parseHumanInput(line)
        let builderRequest = try CLIRequestBuilder.parseHumanInput(line)

        XCTAssertEqual(replRequest[.command] as? String, builderRequest[.command] as? String)
        XCTAssertEqual(replRequest[.direction] as? String, builderRequest[.direction] as? String)
        XCTAssertEqual(replRequest[.heistId] as? String, builderRequest[.heistId] as? String)
        XCTAssertEqual(replRequest[.timeout] as? Double, builderRequest[.timeout] as? Double)
    }

    func testSessionReplDoesNotDeclareCommandAliasTables() throws {
        let source = try String(
            contentsOf: repositoryRoot()
                .appendingPathComponent("ButtonHeistCLI/Sources/Session/SessionRepl.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("TheFence.Command.cliSessionHelp"), "REPL alias help should render from the Fence-owned CLI help projection")
        XCTAssertFalse(source.contains("TheFence.Command.humanCommandAliases"), "REPL alias help should not read alias tables directly")
        XCTAssertFalse(source.contains("commandAliases:"), "REPL command aliases should live in TheFence.Command.humanCommandAliases")
        XCTAssertFalse(source.contains("compoundAliases:"), "REPL compound aliases should live in TheFence.Command.humanCommandAliases")
        XCTAssertFalse(source.contains("descriptor.humanAliases"), "REPL should not rescan descriptor alias fields")
    }

    func testSessionReplDoesNotDeclareCommandSpecificPositionalTables() throws {
        let source = try String(
            contentsOf: repositoryRoot()
                .appendingPathComponent("ButtonHeistCLI/Sources/Session/SessionRepl.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("directionWords"), "REPL direction metadata should live in TheFence.Command.humanPositionalSyntax")
        XCTAssertFalse(source.contains("edgeWords"), "REPL edge metadata should live in TheFence.Command.humanPositionalSyntax")
        XCTAssertFalse(source.contains("directionCommands"), "REPL command-role metadata should live in TheFence.Command.humanPositionalSyntax")
    }

    func testSessionReplDoesNotOwnHumanRequestBuilder() throws {
        let source = try String(
            contentsOf: repositoryRoot()
                .appendingPathComponent("ButtonHeistCLI/Sources/Session/SessionRepl.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("HumanCommandRequest"), "REPL should delegate request construction to CLIRequestBuilder")
        XCTAssertFalse(source.contains("parseHumanValue"), "REPL should delegate parameter conversion to CLIRequestBuilder")
        XCTAssertFalse(source.contains("interpretPositionalArgs"), "REPL should delegate positional parsing to CLIRequestBuilder")
        XCTAssertFalse(source.contains("humanCommandDescriptor"), "REPL should resolve command identity through CLIRequestBuilder")
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

    func testGestureCommandsDoNotMirrorFenceCommandCases() throws {
        let source = try String(
            contentsOf: repositoryRoot()
                .appendingPathComponent("ButtonHeistCLI/Sources/Commands/GestureCommands.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(
            source.contains("TheFence.Command."),
            "Gesture command identity should project through GestureType and Fence descriptors"
        )
        XCTAssertFalse(
            source.contains("fenceCommand ="),
            "Gesture wrappers should not assign Fence command identity directly"
        )
        XCTAssertFalse(
            source.contains("cliFenceCommand"),
            "Gesture wrappers should use GestureCLICommandContract instead of a second command lookup helper"
        )
        XCTAssertTrue(
            source.contains("GestureCLICommandContract"),
            "Gesture wrappers should project command identity through descriptor-backed CLI contract"
        )
        XCTAssertFalse(
            source.contains("gestureType"),
            "Gesture wrappers should not carry a second GestureType -> command mirror"
        )
    }

    func testActivateCommandDoesNotMirrorActivationCommandCase() throws {
        let source = try String(
            contentsOf: repositoryRoot()
                .appendingPathComponent("ButtonHeistCLI/Sources/Commands/ActivateCommand.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(
            source.contains("TheFence.Command.activate"),
            "ActivateCommand should derive its base command from the shared activation alias contract"
        )
    }

    func testConventionNamedCLIAdaptersDoNotMirrorFenceCommandCases() throws {
        for file in try swiftSourceFiles(under: "ButtonHeistCLI/Sources/Commands") {
            let source = try String(contentsOf: file, encoding: .utf8)
            let conventionCommandName = file
                .deletingPathExtension()
                .lastPathComponent
                .removingSuffix("Command")
                .removingSuffix("Subcommand")
                .lowercasingFirstLetter()
            let assignedCases = captureGroupMatches(
                in: source,
                pattern: #"static\s+(?:let|var)\s+fenceCommand\s*=\s*TheFence\.Command\.([A-Za-z0-9_]+)"#
            )

            XCTAssertFalse(
                assignedCases.contains(conventionCommandName),
                "\(relativePath(file)) should derive convention-matching command identity through CLICommandContract"
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

    func testScrollingCLICommandsDoNotMirrorCatalogDefaultsInSources() throws {
        let scrollSource = try readRepositoryFile("ButtonHeistCLI/Sources/Commands/ScrollCommand.swift")
        let scrollToEdgeSource = try readRepositoryFile("ButtonHeistCLI/Sources/Commands/ScrollToEdgeCommand.swift")
        let rotorSource = try readRepositoryFile("ButtonHeistCLI/Sources/Commands/RotorCommand.swift")

        XCTAssertTrue(scrollSource.contains("Self.catalogDefaultString(for: .direction)"))
        XCTAssertFalse(scrollSource.contains(#"var direction: String = "down""#))
        XCTAssertTrue(scrollToEdgeSource.contains("Self.catalogDefaultString(for: .edge)"))
        XCTAssertFalse(scrollToEdgeSource.contains(#"var edge: String = "top""#))
        XCTAssertTrue(rotorSource.contains("Self.catalogDefaultString(for: .direction)"))
        XCTAssertFalse(rotorSource.contains("var direction: String = RotorDirection.next.rawValue"))
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

    func testCLIChoiceValidationDoesNotMirrorCatalogEnumCasesInSources() throws {
        let mirroredEnums = [
            "ScrollDirection",
            "ScrollSearchDirection",
            "ScrollEdge",
            "RotorDirection",
            "SwipeDirection",
            "EditAction.allCases",
            "TheFence.BatchPolicy.allCases",
        ]
        let sourceFiles = try swiftSourceFiles(under: "ButtonHeistCLI/Sources/Commands")
            + swiftSourceFiles(under: "ButtonHeistCLI/Sources/Support")

        for file in sourceFiles {
            let source = try String(contentsOf: file, encoding: .utf8)
            for mirror in mirroredEnums {
                XCTAssertFalse(
                    source.contains(mirror),
                    "\(relativePath(file)) should project choice values from FenceParameterSpec instead of \(mirror)"
                )
            }
        }
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

    private var descriptorParameterKeys: Set<String> {
        var keys = Set(TheFence.Command.descriptors.flatMap { $0.parameters.map(\.key) })
        keys.formUnion(TheFence.Command.mcpToolContracts.compactMap { $0.selector?.parameter.key })
        return keys
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

    private func regexFullMatches(in contents: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            XCTFail("Invalid regex pattern: \(pattern)")
            return []
        }
        let range = NSRange(contents.startIndex..<contents.endIndex, in: contents)
        return regex.matches(in: contents, range: range).compactMap { match in
            guard let matchRange = Range(match.range(at: 0), in: contents) else { return nil }
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
