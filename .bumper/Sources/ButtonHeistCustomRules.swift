import BumperBowlingCore
import SwiftSyntax

let buttonHeistRules = RuleSet {
    Rules.importOwnership(
        ["UIKit", "SwiftUI"],
        allowed: runtimeScope.union(demoScope),
        id: "buttonheist.ui_framework_ownership"
    )
    Rules.importOwnership(
        ["Network"],
        allowed: runtimeScope.union(scoreScope),
        id: "buttonheist.network_framework_ownership"
    )
    Rules.importOwnership(
        ["Security"],
        allowed: scoreScope,
        id: "buttonheist.security_framework_ownership"
    )
    Rules.importOwnership(
        ["ObjectiveC", "ObjectiveC.runtime"],
        allowed: runtimeScope,
        id: "buttonheist.objective_c_framework_ownership"
    )
    Rules.importOwnership(
        ["AccessibilitySnapshotCore", "AccessibilitySnapshotParser", "AccessibilitySnapshotPreviews"],
        allowed: runtimeScope,
        id: "buttonheist.accessibility_parser_ownership"
    )
    Rules.memberReferenceOwnership(
        "accessibilityIdentifier",
        allowed: RuleScope.repository
            .excluding(demoScope)
            .union(.files(demoAccessibilityIdentifierResearchFixtures)),
        id: "buttonheist.demo_accessibility_identifier"
    )
    anyBoundaryRule
    callbackIsolationRule
    checkedConcurrencyRule

    Rules.canonicalConstruction(
        "SemanticObservationLog",
        owners: .files([semanticObservationStreamPath]),
        id: "buttonheist.semantic_observation_log_ownership"
    )
    Rules.boundaryOnly(
        function: "observationLog.publish",
        allowed: .files([semanticObservationStreamPath]),
        id: "buttonheist.semantic_observation_publication_ownership"
    )
    settledObservationCommitOwnershipRule

    Rules.singleDeclaration(
        "Expr",
        owner: expressionOwnerPath,
        id: "buttonheist.expr_ownership"
    )
    Rules.canonicalTraversal(
        root: "HeistStep",
        structuralCase: "heist",
        owners: heistStepTraversalOwners,
        id: "buttonheist.canonical_plan_traversal"
    )
    Rules.canonicalTraversal(
        root: "AccessibilityHierarchy",
        structuralCase: "container",
        owners: .files([accessibilityHierarchyTraversalPath]),
        id: "buttonheist.canonical_accessibility_hierarchy_traversal"
    )
}

private let runtimeScope = RuleScope.component(ButtonHeistComponent.runtime)
private let scoreScope = RuleScope.component(ButtonHeistComponent.score)
private let demoScope = RuleScope.component(ButtonHeistComponent.demo)

private let demoAccessibilityIdentifierResearchFixtures: Set<RelativeFilePath> = [
    "TestApp/Sources/ScrollSPIHarnessView.swift",
    "TestApp/Sources/TraitProbeView.swift",
    "TestApp/Sources/TraitValidationView.swift",
]

private let unsafeNonisolatedSPIBoundary: Set<RelativeFilePath> = [
    "ButtonHeist/Sources/TheInsideJob/TheSafecracker/TheSafecracker+IOHIDEventBuilder.swift",
]

private let insideJobSourcePrefix: RelativePathPrefix = "ButtonHeist/Sources/TheInsideJob/"
private let semanticObservationStreamPath: RelativeFilePath =
    "ButtonHeist/Sources/TheInsideJob/TheStash/SemanticObservationStream.swift"
private let interfaceStatePath: RelativeFilePath =
    "ButtonHeist/Sources/TheInsideJob/TheStash/TheStash+InterfaceState.swift"
private let expressionOwnerPath: RelativePathPrefix =
    "ButtonHeist/Sources/ThePlans/Model/StringExpressions.swift"
private let heistPlanTraversalPath: RelativeFilePath =
    "ButtonHeist/Sources/ThePlans/Model/HeistPlanTraversal.swift"
private let accessibilityHierarchyTraversalPath: RelativeFilePath =
    "ButtonHeist/Sources/TheScore/Core/AccessibilityHierarchy+Traversal.swift"

private let heistStepTraversalOwners = RuleScope.files([heistPlanTraversalPath])
    .union(.under("ButtonHeist/Sources/TheInsideJob/TheBrains/"))

private let settledObservationCommitOwnershipRule = Rules.repository(
    "buttonheist.settled_observation_commit_ownership",
    severity: .error,
    summary: "Settled proof publication is the sole path into the InterfaceTree reducer."
) { context in
    settledObservationCommitFailures(in: context)
}

private let anyBoundaryRule = Rules.files(
    "buttonheist.any_boundary",
    severity: .error,
    summary: "Untyped Foundation and Objective-C values are normalized at named boundaries."
) { file in
    SyntaxQuery<IdentifierTypeSyntax>()
        .filter { match in
            match.node.name.text == "Any" && !isAllowedAnyBoundary(match.node)
        }
        .matches(in: file)
        .map { match in
            match.failure(
                message: "Any outside a named system boundary",
                evidence: ViolationEvidence(
                    observed: match.node.bumper.lexicalContext.enclosingFunctionName
                        ?? match.node.trimmedDescription,
                    expectation: "normalize Any into a typed Button Heist value at the boundary"
                )
            )
        }
}

private let callbackIsolationRule = Rules.files(
    "buttonheist.callback_isolation",
    severity: .error,
    summary: "Stored onFoo callbacks declare their actor or Sendable isolation."
) { file in
    let aliases = typeAliases().matches(in: file).map { match in
        CallbackAlias(
            name: match.node.name.text,
            enclosingNominalNames: match.node.bumper.lexicalContext.enclosingNominalNames,
            shape: match.node.bumper.aliasedTypeShape
        )
    }
    return variables()
        .lexically(within: SyntaxScope.fileScope.union(.typeMembers))
        .matches(in: file)
        .flatMap { match in
            match.node.bindings.compactMap { binding -> RuleFailure? in
                guard let name = binding.bumper.identifierName,
                      name.hasPrefix("on"),
                      name.dropFirst(2).first?.isUppercase == true,
                      let declaredShape = binding.bumper.explicitTypeShape,
                      let shape = callbackShape(
                          declaredShape,
                          context: binding.bumper.lexicalContext,
                          aliases: aliases
                      ),
                      shape.isFunction,
                      !shape.outerFunctionAttributes.contains(where: isIsolationAttribute) else {
                    return nil
                }
                return file.failure(
                    at: binding,
                    message: "callback without explicit isolation: \(name)",
                    evidence: ViolationEvidence(
                        observed: "\(name): \(shape.spelling)",
                        expectation: "stored callbacks declare a global actor or @Sendable"
                    )
                )
            }
        }
}

private let checkedConcurrencyRule = Rules.files(
    "buttonheist.checked_concurrency",
    severity: .error,
    summary: "Production code uses checked Swift concurrency without broad escape hatches."
) { file in
    let preconcurrencyFailures = SyntaxQuery<AttributeSyntax>()
        .filter { match in
            match.node.attributeName.trimmedDescription == "preconcurrency"
        }
        .matches(in: file)
        .map { match in
            match.failure(
                message: "production @preconcurrency escape hatch",
                evidence: ViolationEvidence(
                    observed: match.node.trimmedDescription,
                    expectation: "production imports and conformances use checked concurrency"
                )
            )
        }

    let unsafeNonisolatedFailures = SyntaxQuery<DeclModifierSyntax>()
        .filter { match in
            match.node.name.text == "nonisolated"
                && match.node.tokens(viewMode: .sourceAccurate).contains { $0.text == "unsafe" }
        }
        .excluding(.files(unsafeNonisolatedSPIBoundary))
        .matches(in: file)
        .map { match in
            match.failure(
                message: "production nonisolated(unsafe) escape hatch",
                evidence: ViolationEvidence(
                    observed: match.node.trimmedDescription,
                    expectation: "unsafe nonisolated storage stays inside the documented private-SPI loader"
                )
            )
        }

    return preconcurrencyFailures + unsafeNonisolatedFailures
}

private func settledObservationCommitFailures(in context: RuleContext) -> [RuleFailure] {
    let files = context.files(in: .under(insideJobSourcePrefix))
    let reducerCalls = files.flatMap { file in
        functionCalls()
            .filter { $0.node.calleeBaseName == "reduceInterfaceGraph" }
            .matches(in: file)
    }
    var failures = reducerCalls.compactMap(reducerCallFailure)
    if reducerCalls.count != 1 {
        failures.append(RuleFailure(
            path: semanticObservationStreamPath,
            message: "settled observation commit calls the InterfaceTree reducer \(reducerCalls.count) times",
            evidence: ViolationEvidence(
                observed: "reduceInterfaceGraph calls: \(reducerCalls.count)",
                expectation: "one call from proof-bearing SemanticObservationStream.publishCommittedObservation"
            )
        ))
    }

    var reducerMutations = 0
    for file in files {
        for match in SyntaxQuery<SequenceExprSyntax>().matches(in: file) {
            let elements = Array(match.node.elements)
            for index in elements.indices where elements[index].is(AssignmentExprSyntax.self) {
                guard index > elements.startIndex,
                      isInterfaceTreeReference(elements[elements.index(before: index)]) else {
                    continue
                }
                let lexicalContext = match.node.bumper.lexicalContext
                let isStashOwner = file.path == interfaceStatePath
                    && lexicalContext.enclosingNominalNames.contains("TheStash")
                switch lexicalContext.enclosingFunctionName {
                case "reduceInterfaceGraph" where isStashOwner:
                    reducerMutations += 1
                case "clearInterfaceForLifecycleReset" where isStashOwner:
                    break
                default:
                    failures.append(file.failure(
                        at: elements[index],
                        message: "InterfaceTree bypasses settled observation commit ownership",
                        evidence: ViolationEvidence(
                            observed: file.path.rawValue,
                            expectation: "settled proof reduction or explicit lifecycle reset owns InterfaceTree mutation"
                        )
                    ))
                }
            }
        }
    }
    if reducerMutations == 0 {
        failures.append(RuleFailure(
            path: interfaceStatePath,
            message: "settled observation reducer does not update InterfaceTree",
            evidence: ViolationEvidence(
                observed: "no reducer-owned interfaceTree assignment",
                expectation: "InterfaceTree assignments live in TheStash.reduceInterfaceGraph"
            )
        ))
    }
    return failures
}

private func reducerCallFailure(
    _ match: SyntaxMatch<FunctionCallExprSyntax>
) -> RuleFailure? {
    let lexicalContext = match.node.bumper.lexicalContext
    let function = match.node.ancestors.compactMap { $0.as(FunctionDeclSyntax.self) }.first
    let acceptsProof = function?.signature.parameterClause.parameters.contains { parameter in
        parameter.type.tokens(viewMode: .sourceAccurate).contains { $0.text == "InterfaceObservationProof" }
    } == true
    guard match.file.path == semanticObservationStreamPath,
          lexicalContext.enclosingNominalNames.contains("SemanticObservationStream"),
          lexicalContext.enclosingFunctionName == "publishCommittedObservation",
          acceptsProof else {
        return match.failure(
            message: "InterfaceTree bypasses settled observation commit ownership",
            evidence: ViolationEvidence(
                observed: match.file.path.rawValue,
                expectation: "one call from proof-bearing SemanticObservationStream.publishCommittedObservation"
            )
        )
    }
    return nil
}

private func isInterfaceTreeReference(_ expression: ExprSyntax) -> Bool {
    if let reference = expression.as(DeclReferenceExprSyntax.self) {
        return reference.baseName.text == "interfaceTree"
    }
    return expression.as(MemberAccessExprSyntax.self)?.declName.baseName.text == "interfaceTree"
}

private func isAllowedAnyBoundary(_ node: IdentifierTypeSyntax) -> Bool {
    if node.ancestors.contains(where: { ancestor in
        ancestor.as(TypeAliasDeclSyntax.self)?.name.text == "FoundationFileAttributeDictionary"
    }) {
        return true
    }

    let context = node.bumper.lexicalContext
    if context.enclosingFunctionName == "expectedDescription" {
        return context.enclosingNominalNames.contains("HeistValuePayloadDecoder")
    }
    return context.enclosingFunctionName == "value"
        && context.enclosingNominalNames.contains("FoundationInfoPlistBridge")
}

private func isIsolationAttribute(_ name: String) -> Bool {
    name == "Sendable" || name.hasSuffix("Actor")
}

private struct CallbackAlias {
    let name: String
    let enclosingNominalNames: [String]
    let shape: TypeShape
}

private func callbackShape(
    _ declaredShape: TypeShape,
    context: LexicalContext,
    aliases: [CallbackAlias]
) -> TypeShape? {
    if declaredShape.isFunction {
        return declaredShape
    }
    guard let name = declaredShape.outerTypeName else {
        return nil
    }
    return aliases.first { alias in
        alias.name == name
            && alias.enclosingNominalNames == context.enclosingNominalNames
    }?.shape ?? aliases.first { alias in
        alias.name == name && alias.enclosingNominalNames.isEmpty
    }?.shape
}
