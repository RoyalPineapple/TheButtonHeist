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
    heistContentOpacityRule
    planElseOwnershipRule
    exportedTupleContractRule
    Rules.boundaryOnly(
        function: "commitObservation",
        allowed: .files([semanticObservationSettlementPath]),
        id: "buttonheist.semantic_observation_commit_ownership"
    )
}

private let runtimeScope = RuleScope.component(ButtonHeistComponent.runtime)
private let scoreScope = RuleScope.component(ButtonHeistComponent.score)
private let demoScope = RuleScope.component(ButtonHeistComponent.demo)
private let plansScope = RuleScope.component(ButtonHeistComponent.plans)

private let demoAccessibilityIdentifierResearchFixtures: Set<RelativeFilePath> = [
    "TestApp/Sources/ScrollSPIHarnessView.swift",
    "TestApp/Sources/TraitProbeView.swift",
    "TestApp/Sources/TraitValidationView.swift",
]

private let semanticObservationSettlementPath: RelativeFilePath =
    "ButtonHeist/Sources/TheInsideJob/TheVault/SemanticObservationStream+Settlement.swift"

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
        .matches(in: file)
        .map { match in
            match.failure(
                message: "production nonisolated(unsafe) escape hatch",
                evidence: ViolationEvidence(
                    observed: match.node.trimmedDescription,
                    expectation: "production state remains checked by Swift concurrency"
                )
            )
        }

    return preconcurrencyFailures + unsafeNonisolatedFailures
}

private let heistContentOpacityRule = Rules.repository(
    "buttonheist.heist_content_opacity",
    severity: .error,
    summary: "HeistContent remains an opaque public authoring fragment.",
    scope: plansScope
) { context in
    try context.facts(BuiltInFacts.storedProperties)
        .filter { occurrence in
            plansScope.includes(SourceFileDescriptor(path: occurrence.path, component: occurrence.component))
                && occurrence.property.owner?.rawValue == "HeistContent"
                && [.public, .open].contains(occurrence.property.access)
        }
        .map { occurrence in
            RuleFailure(
                path: occurrence.path,
                location: occurrence.property.location,
                message: "HeistContent exposes stored builder bookkeeping.",
                evidence: ViolationEvidence(
                    observed: occurrence.property.name.rawValue,
                    expectation: "HeistContent has no public stored properties"
                )
            )
        }
}

private let planElseOwnershipRule = Rules.files(
    "buttonheist.plan_else_ownership",
    severity: .error,
    summary: "Only wait and conditional DSL fragments expose an else branch."
) { file in
    functions()
        .within(plansScope)
        .filter { match in
            functionName(match.node) == "else" && !isAllowedPlanElseOwner(match.node)
        }
        .matches(in: file)
        .map { match in
            match.failure(
                message: "unsupported DSL else branch",
                evidence: ViolationEvidence(
                    observed: match.node.bumper.lexicalContext.enclosingNominalNames.first
                        ?? match.node.trimmedDescription,
                    expectation: "only WaitFor and IfContent expose func `else`"
                )
            )
        }
}

private let exportedTupleContractRule = Rules.files(
    "buttonheist.exported_tuple_return",
    severity: .error,
    summary: "Exported declarations use named contract types, not multi-value tuples."
) { file in
    declarationContracts(in: file).compactMap { contract in
        guard contract.effectiveAccess.isExported,
              let observed = contract.observedTupleContract else {
            return nil
        }
        return file.failure(
            at: contract.node,
            message: "exported \(contract.kind.rawValue) contains a tuple contract",
            evidence: ViolationEvidence(
                observed: observed,
                expectation: "use named Swift types for public, open, or package API"
            )
        )
    }
}

private struct DeclarationContract {
    let node: Syntax
    let kind: Kind
    let effectiveAccess: ContractAccess
    let types: [TypeSyntax]

    enum Kind: String {
        case function
        case property
        case subscriptDeclaration = "subscript"
    }

    var observedTupleContract: String? {
        let tuples = types.flatMap { type in
            type.descendants(of: TupleTypeSyntax.self).filter { tuple in
                tuple.elements.count > 1
            }
        }
        guard !tuples.isEmpty else {
            return nil
        }
        return tuples.map(\.trimmedDescription).joined(separator: ", ")
    }
}

private enum ContractAccess: Int, Comparable {
    case `private`
    case `fileprivate`
    case `internal`
    case `package`
    case `public`
    case open

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var isExported: Bool {
        self >= .package
    }
}

private let contractDeclarationScope = SyntaxScope.fileScope.union(.typeMembers)

private func declarationContracts(in file: SourceFileContext) -> [DeclarationContract] {
    let functionContracts = functions()
        .lexically(within: contractDeclarationScope)
        .matches(in: file)
        .map { match in
            DeclarationContract(
                node: Syntax(match.node),
                kind: .function,
                effectiveAccess: effectiveAccess(
                    of: match.node,
                    modifiers: match.node.modifiers
                ),
                types: functionContractTypes(match.node)
            )
        }

    let propertyContracts = variables()
        .lexically(within: contractDeclarationScope)
        .matches(in: file)
        .flatMap { match -> [DeclarationContract] in
            let access = effectiveAccess(of: match.node, modifiers: match.node.modifiers)
            return match.node.bindings.compactMap { binding -> DeclarationContract? in
                guard let type = binding.typeAnnotation?.type else {
                    return nil
                }
                return DeclarationContract(
                    node: Syntax(binding),
                    kind: .property,
                    effectiveAccess: access,
                    types: [type]
                )
            }
        }

    let subscriptContracts = SyntaxQuery<SubscriptDeclSyntax>()
        .lexically(within: contractDeclarationScope)
        .matches(in: file)
        .map { match in
            DeclarationContract(
                node: Syntax(match.node),
                kind: .subscriptDeclaration,
                effectiveAccess: effectiveAccess(
                    of: match.node,
                    modifiers: match.node.modifiers
                ),
                types: subscriptContractTypes(match.node)
            )
        }

    return functionContracts + propertyContracts + subscriptContracts
}

private func functionContractTypes(_ node: FunctionDeclSyntax) -> [TypeSyntax] {
    let parameterTypes = node.signature.parameterClause.parameters.map(\.type)
    return parameterTypes + [node.signature.returnClause?.type].compactMap { $0 }
}

private func subscriptContractTypes(_ node: SubscriptDeclSyntax) -> [TypeSyntax] {
    node.parameterClause.parameters.map(\.type) + [node.returnClause.type]
}

private func effectiveAccess(
    of node: some SyntaxProtocol,
    modifiers: DeclModifierListSyntax
) -> ContractAccess {
    let declared = explicitAccess(modifiers) ?? inheritedDefaultAccess(of: node) ?? .internal
    return node.ancestors.compactMap(accessCap).reduce(declared, min)
}

private func inheritedDefaultAccess(of node: some SyntaxProtocol) -> ContractAccess? {
    for ancestor in node.ancestors {
        if let declaration = ancestor.as(ProtocolDeclSyntax.self) {
            return effectiveAccess(of: declaration, modifiers: declaration.modifiers)
        }
        if let declaration = ancestor.as(ExtensionDeclSyntax.self) {
            return explicitAccess(declaration.modifiers) ?? .internal
        }
        if nominalModifiers(ancestor) != nil {
            return .internal
        }
    }
    return nil
}

private func accessCap(_ ancestor: Syntax) -> ContractAccess? {
    if let declaration = ancestor.as(ExtensionDeclSyntax.self) {
        return explicitAccess(declaration.modifiers)
    }
    guard let modifiers = nominalModifiers(ancestor) else {
        return nil
    }
    return effectiveAccess(of: ancestor, modifiers: modifiers)
}

private func nominalModifiers(_ node: Syntax) -> DeclModifierListSyntax? {
    node.asProtocol(DeclGroupSyntax.self)?.modifiers
}

private func explicitAccess(_ modifiers: DeclModifierListSyntax) -> ContractAccess? {
    for modifier in modifiers {
        switch modifier.name.text {
        case "private":
            return .private
        case "fileprivate":
            return .fileprivate
        case "internal":
            return .internal
        case "package":
            return .package
        case "public":
            return .public
        case "open":
            return .open
        default:
            continue
        }
    }
    return nil
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

private func functionName(_ node: FunctionDeclSyntax) -> String {
    let name = node.name.text
    if name.first == "`", name.last == "`" {
        return String(name.dropFirst().dropLast())
    }
    return name
}

private func isAllowedPlanElseOwner(_ node: FunctionDeclSyntax) -> Bool {
    let owner = node.bumper.lexicalContext.enclosingNominalNames.first
    return owner == "WaitFor" || owner == "IfContent"
}
