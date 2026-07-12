import XCTest
@_spi(ButtonHeistTooling) @testable import ButtonHeist
import TheScore

final class ElementActionRequestContractTests: XCTestCase {

    func testElementTargetFenceSchemaFollowsCanonicalMetadata() throws {
        let targetSpec = try XCTUnwrap(
            TheFence.Command.activate.descriptor.parameters.first { $0.key == FenceParameterKey.target.rawValue }
        )
        let schemaFields = ElementTarget.inlineSchemaFields

        XCTAssertEqual(targetSpec.objectProperties.map(\.key), schemaFields.map(\.name))

        let specsByKey = Dictionary(uniqueKeysWithValues: targetSpec.objectProperties.map { ($0.key, $0) })
        for field in schemaFields {
            let spec = try XCTUnwrap(specsByKey[field.name])
            switch field.kind {
            case .predicateChecks:
                XCTAssertEqual(spec.type, .array)
                assertPredicateChecksSchema(spec, file: #filePath, line: #line)
            case .string:
                XCTAssertEqual(spec.type, .string)
            case .stringMatch:
                XCTAssertEqual(spec.type, .stringMatch)
                assertStringMatchObjectSchema(spec, file: #filePath, line: #line)
            case .stringArray:
                XCTAssertEqual(spec.type, .stringArray)
            case .stringMatchArray:
                XCTAssertEqual(spec.type, .array)
                assertArraySchema(spec, file: #filePath, line: #line)
            case .actionArray:
                XCTAssertEqual(spec.type, .array)
                assertArraySchema(spec, file: #filePath, line: #line)
            case .customContentMatch:
                XCTAssertEqual(spec.type, .object)
            case .nonNegativeInteger:
                XCTAssertEqual(spec.type, .integer)
                XCTAssertEqual(projectedJSONSchemaProperty("minimum", in: spec), .int(0))
            case .containerPredicate:
                XCTAssertEqual(spec.type, .object)
                assertContainerPredicateSchema(spec, file: #filePath, line: #line)
            case .nestedElementTarget:
                XCTAssertEqual(spec.type, .object)
                XCTAssertEqual(projectedJSONSchemaProperty("additionalProperties", in: spec), .bool(true))
            }
        }
    }

    func testNestedElementTargetFenceSchemaFollowsCanonicalMetadata() throws {
        let targetSpec = try XCTUnwrap(
            TheFence.Command.activate.descriptor.parameters.first { $0.key == FenceParameterKey.target.rawValue }
        )
        let nestedTargetSpec = try XCTUnwrap(
            targetSpec.objectProperties.first { $0.key == FenceParameterKey.target.rawValue }
        )

        XCTAssertEqual(nestedTargetSpec.objectProperties.map(\.key), ElementTarget.inlineFieldNames)

        let secondLevelTargetSpec = try XCTUnwrap(
            nestedTargetSpec.objectProperties.first { $0.key == FenceParameterKey.target.rawValue }
        )
        XCTAssertEqual(projectedJSONSchemaProperty("additionalProperties", in: secondLevelTargetSpec), .bool(true))
    }

    func testAccessibilityPredicateFenceSchemaUsesCanonicalDiscriminators() throws {
        let waitDescriptor = TheFence.Command.wait.descriptor
        let predicateSpec = try XCTUnwrap(waitDescriptor.parameters.first { $0.key == FenceParameterKey.predicate.rawValue })
        let predicateType = try XCTUnwrap(predicateSpec.objectProperties.first { $0.key == FenceParameterKey.type.rawValue })
        XCTAssertEqual(predicateType.enumValues, AccessibilityPredicateContract.PredicateWireType.values)

        let stateProperties = try arrayItemProperties(
            named: .states,
            in: predicateSpec,
            file: #filePath,
            line: #line
        )
        let stateType = try XCTUnwrap(stateProperties.first { $0.key == FenceParameterKey.type.rawValue })
        XCTAssertEqual(stateType.enumValues, AccessibilityPredicateContract.StateWireType.values)

        let scopeProperties = try arrayItemProperties(
            named: .scopes,
            in: predicateSpec,
            file: #filePath,
            line: #line
        )
        let scopeType = try XCTUnwrap(scopeProperties.first { $0.key == FenceParameterKey.type.rawValue })
        XCTAssertEqual(scopeType.enumValues, AccessibilityPredicateContract.ChangeScopeWireType.values)

        let assertionsSpec = try XCTUnwrap(scopeProperties.first { $0.key == FenceParameterKey.assertions.rawValue })
        let assertionProperties = assertionsSpec.arrayItemProperties
        let assertionType = try XCTUnwrap(assertionProperties.first { $0.key == FenceParameterKey.type.rawValue })
        XCTAssertEqual(
            assertionType.enumValues,
            AccessibilityPredicateContract.StateWireType.values + canonicalElementDeltaPredicateTypeValues()
        )
    }

    func testHeistValuePayloadEncoderBridgesEncodableContracts() throws {
        let value = try TheFence.HeistValuePayloadEncoder.encode(AccessibilityPredicate.state(.exists(.label("Pay"))))

        guard case .object(let object) = value else {
            return XCTFail("Expected object bridge output")
        }
        XCTAssertEqual(object["type"], .string(AccessibilityPredicateContract.StateWireType.exists.rawValue))
        XCTAssertNotNil(object["element"])
    }

    func testNormalParametersNamedLikeCustomPayloadsStillUseSchemaValidation() throws {
        for key in [FenceParameterKey.target, .predicate, .expect, .argument] {
            let descriptor = schemaValidationDescriptor(parameter: param(key, .string, required: true))
            XCTAssertThrowsError(
                try descriptor.validatePublicRequestArguments(TheFence.CommandArgumentEnvelope(values: [
                    key.rawValue: .object([:]),
                ])),
                key.rawValue
            ) { error in
                guard let error = error as? SchemaValidationError else {
                    return XCTFail("Expected SchemaValidationError, got \(error)")
                }
                XCTAssertEqual(error.field, key.rawValue)
                XCTAssertEqual(error.observed, "object")
                XCTAssertEqual(error.expected, "string")
            }
        }
    }

    @ButtonHeistActor
    func testActivateMissingTargetKeepsContractDiagnostics() async throws {
        let (fence, _) = makeConnectedFence()
        let response = try await fence.execute(command: .activate)

        guard case .error(let failure) = response else {
            return XCTFail("Expected error response")
        }
        let message = failure.message
        XCTAssertTrue(message.contains("activate request contract failed: missing target"))
        XCTAssertTrue(message.contains("Next: get_interface()"))
        XCTAssertEqual(failure.details.code, .requestMissingTarget)
        XCTAssertEqual(failure.details.phase, .request)
        XCTAssertEqual(failure.details.retryable, false)
        XCTAssertEqual(failure.details.hint, "get_interface()")
    }

    @ButtonHeistActor
    func testTypeTextEmptyStringKeepsObservedValueDiagnostic() async {
        await assertExecutionError(
            command: .typeText,
            arguments: ["text": .string("")],
            contains: "schema validation failed for text: observed string \"\"; expected non-empty string"
        )
    }

    @ButtonHeistActor
    func testScrollRejectsContainerObjectAtTypedBoundary() async {
        await assertExecutionError(
            command: .scroll,
            arguments: [
                "container": .object(["containerName": .string("list")]),
            ],
            contains: "schema validation failed for container"
        )
    }

    @ButtonHeistActor
    func testActivateRejectsContainerNameAsSemanticTarget() async {
        await assertExecutionError(
            command: .activate,
            arguments: ["target": .object(["containerName": .string("main_scroll")])],
            contains: "Unknown element target field \"containerName\""
        )
    }

    @ButtonHeistActor
    func testSwipeRejectsNestedObjectMissingRequiredCoordinateThroughTypedSchema() async {
        await assertExecutionError(
            command: .swipe,
            arguments: [
                "pointToPoint": .object([
                    "start": .object(["x": .double(0.1)]),
                    "end": .object([
                        "x": .double(0.8),
                        "y": .double(0.9),
                    ]),
                ]),
            ],
            contains: "schema validation failed for pointToPoint.start.y: observed missing; expected number"
        )
    }

    @ButtonHeistActor
    func testGetInterfaceRejectsArrayItemUnknownPropertyThroughTypedSchema() async {
        await assertExecutionError(
            command: .getInterface,
            arguments: [
                "checks": .array([
                    .object([
                        "kind": .string("label"),
                        "extra": .string("unexpected"),
                    ]),
                ]),
            ],
            contains: "schema validation failed for checks[0].extra"
        )
    }

    @ButtonHeistActor
    private func assertExecutionError(
        command: TheFence.Command,
        arguments: [String: HeistValue] = [:],
        contains expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let (fence, _) = makeConnectedFence()
        do {
            let response = try await fence.execute(
                command: command,
                values: arguments
            )
            guard case .error(let failure) = response else {
                return XCTFail("Expected error response", file: file, line: line)
            }
            XCTAssertTrue(
                failure.message.contains(expected),
                "Expected error containing '\(expected)', got: \(failure.message)",
                file: file,
                line: line
            )
        } catch {
            XCTFail("Unexpected throw: \(error)", file: file, line: line)
        }
    }
}

private func schemaValidationDescriptor(parameter: FenceParameterSpec) -> FenceCommandDescriptor {
    TheFence.Command.ping.makeDescriptor(
        family: .session,
        requestDecoder: { _, _, _, _ in fatalError("unused") },
        requiresConnectionBeforeDispatch: false,
        parameters: [parameter],
        responseProjection: .pong,
        projection: .cliOnly("test")
    )
}

private func projectedJSONSchemaProperty(_ key: String, in spec: FenceParameterSpec) -> HeistValue? {
    guard case .object(let schema) = spec.schema.heistValue else { return nil }
    return schema[key]
}

private func assertStringMatchObjectSchema(
    _ spec: FenceParameterSpec,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard case .object(let schema) = spec.schema.heistValue
    else {
        return XCTFail("Expected StringMatch object schema", file: file, line: line)
    }

    XCTAssertEqual(schema["type"], .string("object"), file: file, line: line)
    XCTAssertEqual(schema["additionalProperties"], .bool(false), file: file, line: line)
    XCTAssertEqual(schema["required"], .array([.string("mode")]), file: file, line: line)

    guard case .object(let properties)? = schema["properties"] else {
        return XCTFail("Expected StringMatch properties", file: file, line: line)
    }
    XCTAssertEqual(properties["mode"], .object([
        "type": .string("string"),
        "enum": .array(StringMatch<String>.Mode.allCases.map { .string($0.rawValue) }),
    ]), file: file, line: line)
    XCTAssertEqual(properties["value"], .object(["type": .string("string")]), file: file, line: line)
}

private func assertPredicateChecksSchema(
    _ spec: FenceParameterSpec,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard case .object(let schema) = spec.schema.heistValue else {
        return XCTFail("Expected predicate checks array schema", file: file, line: line)
    }
    XCTAssertEqual(schema["type"], .string("array"), file: file, line: line)

    guard case .object(let items)? = schema["items"] else {
        return XCTFail("Expected predicate check item schema", file: file, line: line)
    }
    XCTAssertEqual(items["type"], .string("object"), file: file, line: line)
    XCTAssertEqual(items["additionalProperties"], .bool(false), file: file, line: line)
    XCTAssertEqual(items["required"], .array([.string("kind")]), file: file, line: line)

    guard case .object(let properties)? = items["properties"] else {
        return XCTFail("Expected predicate check item properties", file: file, line: line)
    }
    XCTAssertEqual(properties["kind"], .object([
        "type": .string("string"),
        "enum": .array(ElementPredicateCheck<String>.Kind.allCases.map { .string($0.rawValue) }),
    ]), file: file, line: line)

    guard case .object? = properties["match"] else {
        return XCTFail("Expected match StringMatch object schema", file: file, line: line)
    }
    guard case .object(let values)? = properties["values"] else {
        return XCTFail("Expected values string array schema", file: file, line: line)
    }
    XCTAssertEqual(values["type"], .string("array"), file: file, line: line)
    guard case .object? = properties["check"] else {
        return XCTFail("Expected nested check object schema", file: file, line: line)
    }
}

private func assertContainerPredicateSchema(
    _ spec: FenceParameterSpec,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard case .object(let schema) = spec.schema.heistValue else {
        return XCTFail("Expected container predicate object schema", file: file, line: line)
    }
    XCTAssertEqual(schema["type"], .string("object"), file: file, line: line)
    XCTAssertEqual(schema["required"], .array([.string("checks")]), file: file, line: line)
    guard case .object(let properties)? = schema["properties"] else {
        return XCTFail("Expected container predicate properties", file: file, line: line)
    }
    guard case .object(let checksSchema)? = properties["checks"] else {
        return XCTFail("Expected container checks array schema", file: file, line: line)
    }
    XCTAssertEqual(checksSchema["type"], .string("array"), file: file, line: line)
    XCTAssertEqual(checksSchema["minItems"], .int(1), file: file, line: line)
    guard case .object(let items)? = checksSchema["items"] else {
        return XCTFail("Expected container check item schema", file: file, line: line)
    }
    XCTAssertEqual(items["additionalProperties"], .bool(false), file: file, line: line)
    guard case .object(let checkProperties)? = items["properties"] else {
        return XCTFail("Expected container check item properties", file: file, line: line)
    }
    XCTAssertEqual(checkProperties["kind"], .object([
        "type": .string("string"),
        "enum": .array(ContainerPredicateCheck<String>.wireKindValues.map { .string($0) }),
    ]), file: file, line: line)
    XCTAssertEqual(checkProperties["type"], .object([
        "type": .string("string"),
        "enum": .array(AccessibilityContainerKind.allCases.map { .string($0.rawValue) }),
    ]), file: file, line: line)
    guard case .object(let semantic)? = checkProperties["semantic"],
          case .object(let semanticProperties)? = semantic["properties"] else {
        return XCTFail("Expected semantic container predicate schema", file: file, line: line)
    }
    XCTAssertEqual(semantic["required"], .array([.string("kind"), .string("match")]), file: file, line: line)
    XCTAssertEqual(semanticProperties["kind"], .object([
        "type": .string("string"),
        "enum": .array(canonicalSemanticContainerPredicateKindValues().map { .string($0) }),
    ]), file: file, line: line)
    guard case .object? = semanticProperties["match"] else {
        return XCTFail("Expected semantic match StringMatch object schema", file: file, line: line)
    }
    guard case .object? = checkProperties["values"] else {
        return XCTFail("Expected container check values array schema", file: file, line: line)
    }
    XCTAssertNotNil(checkProperties["value"], file: file, line: line)
}

private func arrayItemProperties(
    named key: FenceParameterKey,
    in spec: FenceParameterSpec,
    file: StaticString,
    line: UInt
) throws -> [FenceParameterSpec] {
    let child = try XCTUnwrap(
        spec.objectProperties.first { $0.key == key.rawValue },
        file: file,
        line: line
    )
    return child.arrayItemProperties
}

private func canonicalElementDeltaPredicateTypeValues() -> [String] {
    [
        ElementDeltaPredicate.appearedElement(.label("sample")),
        ElementDeltaPredicate.disappearedElement(.label("sample")),
        ElementDeltaPredicate.updatedElement(.any),
    ].map { wireDiscriminatorValue($0, discriminator: FenceParameterKey.type.rawValue) }
}

private func canonicalSemanticContainerPredicateKindValues() -> [String] {
    [
        SemanticContainerPredicate<String>.label("sample"),
        SemanticContainerPredicate<String>.value("sample"),
        SemanticContainerPredicate<String>.identifier("sample"),
    ].map { wireDiscriminatorValue($0, discriminator: FenceParameterKey.kind.rawValue) }
}

private func assertArraySchema(
    _ spec: FenceParameterSpec,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard case .object(let schema) = spec.schema.heistValue else {
        return XCTFail("Expected array schema", file: file, line: line)
    }
    XCTAssertEqual(schema["type"], .string("array"), file: file, line: line)
}
