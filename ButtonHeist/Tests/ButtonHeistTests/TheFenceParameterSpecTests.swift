import XCTest
@testable import ButtonHeist
import TheScore

final class TheFenceParameterSpecTests: XCTestCase {

    func testOptionalParametersDeclareNonCompatibilityRole() {
        let issues = optionalParameterRoleIssues()

        XCTAssertTrue(
            issues.isEmpty,
            "Optional parameter role issues:\n\(issues.joined(separator: "\n"))"
        )
    }

    func testRemovedCompatibilityFieldsStayOutOfCommandSpecs() {
        let removedFieldsByCommand: [TheFence.Command: Set<String>] = [
            .getInterface: ["full"],
            .typeText: ["clearFirst", "deleteCount"],
            .performCustomAction: ["actionName"],
            .drag: ["x", "y"],
            .pinch: ["x", "y"],
            .rotate: ["x", "y"],
            .twoFingerTap: ["x", "y"],
        ]

        let offenders = removedFieldsByCommand.flatMap { command, removedFields in
            let parameterKeys = Set(command.parameters.map(\.key))
            return parameterKeys.intersection(removedFields).map { "\(command.rawValue).\($0)" }
        }.sorted()

        XCTAssertTrue(
            offenders.isEmpty,
            "Compatibility fields reintroduced into command specs:\n\(offenders.joined(separator: "\n"))"
        )
    }

    func testHumanCommandAliasesResolveToCanonicalCommands() {
        let aliases = TheFence.Command.humanCommandAliases

        XCTAssertEqual(aliases["tap"]?.command, .oneFingerTap)
        XCTAssertEqual(aliases["ui"]?.command, .getInterface)
        XCTAssertEqual(aliases["record"]?.command, .startRecording)
        XCTAssertEqual(aliases["copy"]?.command, .editAction)
        XCTAssertEqual(aliases["copy"]?.parameters[.action], .string(EditAction.copy.rawValue))
        XCTAssertEqual(aliases["select_all"]?.parameters[.action], .string(EditAction.selectAll.rawValue))
    }

    func testHumanCommandAliasesDoNotShadowCanonicalCommands() {
        let canonicalCommandNames = Set(TheFence.Command.allCases.map(\.rawValue))
        let shadowedAliases = Set(TheFence.Command.humanCommandAliases.keys).intersection(canonicalCommandNames)

        XCTAssertTrue(
            shadowedAliases.isEmpty,
            "Human aliases must not shadow canonical command names: \(shadowedAliases.sorted())"
        )
    }

    func testCommandDescriptorsCoverCommandIdentities() {
        let descriptors = TheFence.Command.descriptors

        XCTAssertEqual(descriptors.map(\.command), TheFence.Command.allCases)
        XCTAssertEqual(descriptors.map(\.canonicalName), TheFence.Command.allCases.map(\.rawValue))

        for command in TheFence.Command.allCases {
            let descriptor = command.descriptor
            XCTAssertEqual(descriptor.command, command)
            XCTAssertEqual(descriptor.canonicalName, command.rawValue)
            XCTAssertEqual(descriptor.parameters, command.parameters)
            XCTAssertEqual(descriptor.cliExposure, command.cliExposure)
            XCTAssertEqual(descriptor.mcpExposure, command.mcpExposure)
            XCTAssertEqual(descriptor.isBatchExecutable, command.isBatchExecutable)
            XCTAssertEqual(descriptor.isPlaybackExecutable, command.isPlaybackExecutable)
            XCTAssertEqual(descriptor.isHeistRecordable, command.isHeistRecordable)
            XCTAssertEqual(
                descriptor.requiresConnectionBeforeDispatch,
                command.requiresConnectionBeforeDispatch
            )
            XCTAssertFalse(descriptor.description.isEmpty)
        }
    }

    func testCommandExecutionEligibilityIsDescriptorOwned() {
        let descriptors = TheFence.Command.descriptors

        XCTAssertEqual(TheFence.Command.batchExecutableCases, descriptors.filter(\.isBatchExecutable).map(\.command))
        XCTAssertEqual(TheFence.Command.playbackExecutableCases, TheFence.Command.batchExecutableCases)
        XCTAssertEqual(
            TheFence.Command.allCases.filter(\.isHeistRecordable),
            TheFence.Command.playbackExecutableCases
        )

        let nonBatchCommands = TheFence.Command.allCases.filter { !$0.isBatchExecutable }
        XCTAssertEqual(
            Set(nonBatchCommands),
            [
                .help, .status, .ping, .quit, .exit,
                .listDevices, .getInterface, .getScreen, .getPasteboard,
                .getSessionState, .connect, .listTargets,
                .getSessionLog, .archiveSession,
                .startRecording, .stopRecording, .runBatch,
                .startHeist, .stopHeist, .playHeist,
            ]
        )

        XCTAssertTrue(TheFence.Command.allCases.allSatisfy { !$0.isHeistRecordable || $0.isPlaybackExecutable })
    }

    func testExecutionEligibilityCountsAreExplicit() {
        XCTAssertEqual(
            TheFence.Command.batchExecutableCases.count,
            24,
            "Batch-eligible command count changed - update run_batch schema tests and this canary"
        )
        XCTAssertEqual(
            TheFence.Command.playbackExecutableCases.count,
            TheFence.Command.batchExecutableCases.count,
            "Playback eligibility should derive from batch eligibility unless a separate product contract is reintroduced"
        )
        XCTAssertEqual(
            TheFence.Command.allCases.filter(\.isHeistRecordable).count,
            TheFence.Command.playbackExecutableCases.count,
            "Heist-recordable commands should derive from playback eligibility unless a separate product contract is reintroduced"
        )
    }

    func testConnectionDispatchPolicyIsDescriptorOwned() {
        let noConnectionCommands = TheFence.Command.allCases.filter { !$0.requiresConnectionBeforeDispatch }
        XCTAssertEqual(
            Set(noConnectionCommands),
            [
                .status, .ping, .getSessionState, .listDevices, .connect, .listTargets,
                .getSessionLog, .archiveSession, .startHeist, .stopHeist,
            ]
        )
    }

    func testPingMCPAnnotationsAreReadOnlyAndIdempotent() {
        let contract = TheFence.Command.mcpToolContract(named: TheFence.Command.ping.rawValue)

        XCTAssertEqual(contract?.annotations?.readOnlyHint, true)
        XCTAssertEqual(contract?.annotations?.idempotentHint, true)
    }

    func testCommandAliasesAreDescriptorOwned() {
        let descriptorAliases = Dictionary(
            TheFence.Command.descriptors.flatMap { descriptor in
                descriptor.humanAliases.map { ($0.key, $0.value) }
            },
            uniquingKeysWith: { _, newest in newest }
        )

        XCTAssertEqual(TheFence.Command.humanCommandAliases, descriptorAliases)
    }

    func testHumanAliasCountIsExplicit() {
        XCTAssertEqual(
            TheFence.Command.humanCommandAliases.count,
            18,
            "Human alias count changed - update descriptor-owned aliases and REPL help tests"
        )
    }

    func testEveryParameterSpecKeyIsBackedByFenceParameterKey() {
        let knownKeys = Set(FenceParameterKey.allCases.map(\.rawValue))

        for command in TheFence.Command.allCases {
            assertParameterKeysAreBacked(
                command.parameters,
                knownKeys: knownKeys,
                context: command.rawValue
            )
        }

        for contract in TheFence.Command.mcpToolContracts {
            guard let selector = contract.selector else { continue }
            assertParameterKeysAreBacked(
                [selector.parameter],
                knownKeys: knownKeys,
                context: "\(contract.name).selector"
            )
        }
    }

    private func assertParameterKeysAreBacked(
        _ specs: [FenceParameterSpec],
        knownKeys: Set<String>,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for spec in specs {
            XCTAssertTrue(
                knownKeys.contains(spec.key),
                "\(context).\(spec.key) is not in FenceParameterKey - add a case or fix the spec key",
                file: file,
                line: line
            )
            assertParameterKeysAreBacked(
                spec.objectProperties,
                knownKeys: knownKeys,
                context: "\(context).\(spec.key)",
                file: file,
                line: line
            )
            assertParameterKeysAreBacked(
                spec.arrayItemProperties,
                knownKeys: knownKeys,
                context: "\(context).\(spec.key)[]",
                file: file,
                line: line
            )
        }
    }

    private func optionalParameterRoleIssues() -> [String] {
        var issues: [String] = []

        for command in TheFence.Command.allCases {
            collectOptionalParameterRoleIssues(
                in: command.parameters,
                context: command.rawValue,
                issues: &issues
            )
        }

        for contract in TheFence.Command.mcpToolContracts {
            guard let selector = contract.selector else { continue }
            collectOptionalParameterRoleIssues(
                in: [selector.parameter],
                context: "\(contract.name).selector",
                issues: &issues
            )
        }

        return issues.sorted()
    }

    private func collectOptionalParameterRoleIssues(
        in specs: [FenceParameterSpec],
        context: String,
        issues: inout [String]
    ) {
        for spec in specs {
            let specPath = "\(context).\(spec.key)"
            if spec.required {
                if let optionalRole = spec.optionalRole {
                    issues.append("\(specPath) is required but declares optionalRole=\(optionalRole.rawValue)")
                }
            } else {
                switch spec.optionalRole {
                case .matcher, .payload, .behaviorSwitch:
                    break
                case nil:
                    issues.append("\(specPath) is optional but missing optionalRole")
                }
            }

            collectOptionalParameterRoleIssues(
                in: spec.objectProperties,
                context: specPath,
                issues: &issues
            )
            collectOptionalParameterRoleIssues(
                in: spec.arrayItemProperties,
                context: "\(specPath)[]",
                issues: &issues
            )
        }
    }
}
