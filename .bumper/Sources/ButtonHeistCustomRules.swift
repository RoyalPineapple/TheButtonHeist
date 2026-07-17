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
    Rules.boundaryOnly(
        function: "reduceInterfaceGraph",
        allowed: .files([semanticObservationPublicationPath]),
        id: "buttonheist.semantic_observation_commit_ownership"
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

private let semanticObservationPublicationPath: RelativeFilePath =
    "ButtonHeist/Sources/TheInsideJob/TheStash/SemanticObservationStream+Publication.swift"

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
