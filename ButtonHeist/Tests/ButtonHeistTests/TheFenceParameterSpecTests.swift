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
            XCTAssertFalse(descriptor.description.isEmpty)
        }
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
                case .compatibility:
                    issues.append("\(specPath) is compatibility optionality; delete the field instead")
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
