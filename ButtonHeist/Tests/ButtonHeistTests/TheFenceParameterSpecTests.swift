import XCTest
@testable import ButtonHeist
import TheScore

final class TheFenceParameterSpecTests: XCTestCase {

    func testRemovedCompatibilityFieldsStayOutOfCommandSpecs() {
        let removedFieldsByCommand: [TheFence.Command: Set<String>] = [
            .getInterface: ["full"],
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
            XCTAssertEqual(descriptor.requestPayloadKind, command.requestPayloadKind)
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

    func testRequestPayloadFamiliesAreDescriptorOwned() {
        let commandsByKind = Dictionary(grouping: TheFence.Command.allCases, by: \.requestPayloadKind)

        XCTAssertEqual(
            Set(commandsByKind[.none] ?? []),
            [
                .help, .status, .ping, .quit, .exit, .listDevices,
                .getPasteboard, .dismissKeyboard, .getSessionState,
                .listTargets, .getSessionLog,
            ]
        )
        XCTAssertEqual(Set(commandsByKind[.observation] ?? []), [.getInterface, .getScreen, .stopRecording])
        XCTAssertEqual(Set(commandsByKind[.waitForChange] ?? []), [.waitForChange])
        XCTAssertEqual(
            Set(commandsByKind[.gesture] ?? []),
            [
                .oneFingerTap, .longPress, .swipe, .drag, .pinch, .rotate,
                .twoFingerTap, .drawPath, .drawBezier,
            ]
        )
        XCTAssertEqual(
            Set(commandsByKind[.elementAction] ?? []),
            [
                .scroll, .scrollToVisible, .elementSearch, .scrollToEdge,
                .activate, .increment, .decrement, .performCustomAction,
                .rotor, .typeText, .editAction, .setPasteboard, .waitFor,
            ]
        )
        XCTAssertEqual(
            Set(commandsByKind[.session] ?? []),
            [
                .startRecording, .runBatch, .connect, .archiveSession,
                .startHeist, .stopHeist, .playHeist,
            ]
        )
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

    func testRepresentativeDescriptorParametersOwnRenderedSchemaProperties() throws {
        let text = try parameter("text", in: .typeText)
        XCTAssertEqual(text.required, true)
        XCTAssertEqual(try schemaString("type", in: text), "string")
        XCTAssertEqual(try schemaInt("minLength", in: text), 1)

        let editAction = try parameter("action", in: .editAction)
        XCTAssertEqual(editAction.required, true)
        XCTAssertEqual(editAction.enumValues, EditAction.allCases.map(\.rawValue))
        XCTAssertEqual(try schemaEnumValues(in: editAction), Set(EditAction.allCases.map(\.rawValue)))

        let drawPathPoints = try parameter("points", in: .drawPath)
        XCTAssertEqual(drawPathPoints.required, true)
        XCTAssertEqual(try schemaInt("minItems", in: drawPathPoints), 2)
        XCTAssertEqual(try schemaInt("maxItems", in: drawPathPoints), TheFence.DecodeLimits.maxDrawPathPoints)
        let pointProperties = try itemProperties(in: drawPathPoints)
        XCTAssertEqual(Set(pointProperties.keys), ["x", "y"])
        XCTAssertEqual(try requiredKeys(in: itemSchema(in: drawPathPoints)), Set(["x", "y"]))

        let expect = try parameter("expect", in: .activate)
        XCTAssertEqual(
            try propertyKeys(in: expect),
            Set(["expectations", "heistId", "matcher", "newValue", "oldValue", "property", "type"])
        )
    }

    private func parameter(_ key: String, in command: TheFence.Command) throws -> FenceParameterSpec {
        try XCTUnwrap(command.parameters.first { $0.key == key }, "\(command.rawValue) missing \(key)")
    }

    private func schemaObject(in spec: FenceParameterSpec) throws -> [String: FenceJSONSchemaValue] {
        try schemaObject(spec.jsonSchemaProperty)
    }

    private func schemaObject(_ value: FenceJSONSchemaValue) throws -> [String: FenceJSONSchemaValue] {
        guard case .object(let object) = value else {
            XCTFail("Expected object schema, got \(value)")
            return [:]
        }
        return object
    }

    private func schemaString(_ key: String, in spec: FenceParameterSpec) throws -> String? {
        guard case .string(let value)? = try schemaObject(in: spec)[key] else { return nil }
        return value
    }

    private func schemaInt(_ key: String, in spec: FenceParameterSpec) throws -> Int? {
        guard case .int(let value)? = try schemaObject(in: spec)[key] else { return nil }
        return value
    }

    private func schemaEnumValues(in spec: FenceParameterSpec) throws -> Set<String> {
        guard case .array(let values)? = try schemaObject(in: spec)["enum"] else { return [] }
        return Set(values.compactMap {
            guard case .string(let value) = $0 else { return nil }
            return value
        })
    }

    private func propertyKeys(in spec: FenceParameterSpec) throws -> Set<String> {
        Set(try properties(in: spec).keys)
    }

    private func properties(in spec: FenceParameterSpec) throws -> [String: FenceJSONSchemaValue] {
        guard case .object(let properties)? = try schemaObject(in: spec)["properties"] else { return [:] }
        return properties
    }

    private func itemSchema(in spec: FenceParameterSpec) throws -> [String: FenceJSONSchemaValue] {
        guard let items = try schemaObject(in: spec)["items"] else { return [:] }
        return try schemaObject(items)
    }

    private func itemProperties(in spec: FenceParameterSpec) throws -> [String: FenceJSONSchemaValue] {
        guard case .object(let properties)? = try itemSchema(in: spec)["properties"] else { return [:] }
        return properties
    }

    private func requiredKeys(in schema: [String: FenceJSONSchemaValue]) throws -> Set<String> {
        guard case .array(let values)? = schema["required"] else { return [] }
        return Set(values.compactMap {
            guard case .string(let value) = $0 else { return nil }
            return value
        })
    }
}
