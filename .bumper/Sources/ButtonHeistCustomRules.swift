import BumperBowlingCore
import Foundation
import SwiftSyntax

let customRules = CustomRuleSet {
    CustomRule("buttonheist.thescore.import_allow_list", severity: .error) { context in
        let allowedImports = Set([
            "AccessibilitySnapshotModel",
            "CoreGraphics",
            "CryptoKit",
            "Dispatch",
            "Foundation",
            "Network",
            "OSLog",
            "Security",
            "ThePlans",
            "zlib",
        ])
        let allowedDescription = allowedImports.sorted().joined(separator: ", ")

        return context.files(inComponent: "score").flatMap { file in
            Set(file.imports)
                .subtracting(allowedImports)
                .sorted()
                .map { module in
                    CustomRuleFailure(
                        path: file.path,
                        message: "TheScore imports non-allowlisted module \(module)",
                        evidence: ViolationEvidence(
                            observed: module,
                            expectation: "allowed imports: \(allowedDescription)"
                        )
                    )
                }
        }
    }

    CustomRule("buttonheist.thescore.folder_import_allow_list", severity: .error) { context in
        context.files(inComponent: "score").flatMap { file -> [CustomRuleFailure] in
            guard let allowedImports = scoreFolderAllowedImports(for: file.path.rawValue) else {
                return []
            }
            let allowedDescription = allowedImports.sorted().joined(separator: ", ")
            return Set(file.imports)
                .subtracting(allowedImports)
                .sorted()
                .map { module in
                    CustomRuleFailure(
                        path: file.path,
                        message: "TheScore folder imports non-allowlisted module \(module)",
                        evidence: ViolationEvidence(
                            observed: module,
                            expectation: "allowed imports for this TheScore folder/file: \(allowedDescription)"
                        )
                    )
                }
        }
    }

    CustomRule("buttonheist.framework_import_sandbox", severity: .error) { context in
        frameworkSandboxComponentIDs.flatMap { componentID in
            context.files(inComponent: componentID)
        }.flatMap { file -> [CustomRuleFailure] in
            file.imports.compactMap { importedModule in
                guard let sandbox = frameworkSandbox(for: importedModule),
                      !sandbox.allows(file.path.rawValue) else {
                    return nil
                }

                return CustomRuleFailure(
                    path: file.path,
                    message: "\(sandbox.displayName) import outside explicit fiefdom",
                    evidence: ViolationEvidence(
                        observed: importedModule,
                        expectation: sandbox.expectation
                    )
                )
            }
        }
    }

    CustomRule("buttonheist.architecture_currency_ownership", severity: .error) { context in
        architectureCurrencyOwnershipFailures(in: context)
    }

    CustomSyntaxRule("buttonheist.swift_source_shape", severity: .error) { file in
        let visitor = ButtonHeistSourceShapeRuleVisitor(file: file, viewMode: .sourceAccurate)
        visitor.walk(file.syntax)
        return visitor.failures
    }

    CustomSyntaxRule("buttonheist.insidejob_architectural_shape", severity: .error) { file in
        guard file.path.rawValue.hasPrefix(insideJobSourcePrefix) else { return [] }
        let visitor = InsideJobArchitecturalShapeRuleVisitor(file: file, viewMode: .sourceAccurate)
        visitor.walk(file.syntax)
        return visitor.failures
    }
}

private final class ButtonHeistSourceShapeRuleVisitor: SyntaxVisitor {
    private let file: SourceFileContext
    private let requiresExplicitAccess: Bool
    private let filePath: String
    private(set) var failures: [CustomRuleFailure] = []

    init(file: SourceFileContext, viewMode: SyntaxTreeViewMode) {
        self.file = file
        self.filePath = file.path.rawValue
        self.requiresExplicitAccess = explicitAccessRequiredPaths.contains(file.path.rawValue)
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        recordExplicitAccess(node: node, modifiers: node.modifiers, name: node.name.text)
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        recordActionObservationWireShape(node)
        recordExplicitAccess(node: node, modifiers: node.modifiers, name: node.name.text)
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        recordExplicitAccess(node: node, modifiers: node.modifiers, name: node.name.text)
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        recordExplicitAccess(node: node, modifiers: node.modifiers, name: node.name.text)
        return .visitChildren
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        recordExplicitAccess(node: node, modifiers: node.modifiers, name: node.name.text)
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        recordRetiredParameterLabels(node.signature.parameterClause.parameters)
        recordContainerSemanticIdentifierAlias(node)
        recordRawExecutableParameters(node)
        recordSelectorShortcut(node)
        recordCompatibilitySurface(
            node: node,
            modifiers: node.modifiers,
            attributes: node.attributes,
            name: node.name.text
        )
        recordTupleReturn(
            modifiers: node.modifiers,
            returnType: node.signature.returnClause?.type,
            message: "exported tuple return type",
            expectation: "exported function results use named Swift types"
        )
        recordNonPrivateTupleReturn(
            node: node.signature.returnClause?.type,
            modifiers: node.modifiers,
            message: "non-private tuple return type",
            expectation: "cross-file function results use named Swift types"
        )
        recordExportedTupleParameters(
            node: node,
            modifiers: node.modifiers,
            parameters: node.signature.parameterClause.parameters
        )
        recordExplicitAccess(node: node, modifiers: node.modifiers, name: node.name.text)
        return .visitChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        recordRetiredParameterLabels(node.signature.parameterClause.parameters)
        recordExportedTupleParameters(
            node: node,
            modifiers: node.modifiers,
            parameters: node.signature.parameterClause.parameters
        )
        return .visitChildren
    }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        recordRetiredParameterLabels(node.parameterClause.parameters)
        recordTupleReturn(
            modifiers: node.modifiers,
            returnType: node.returnClause.type,
            message: "exported tuple return type",
            expectation: "exported subscript results use named Swift types"
        )
        recordNonPrivateTupleReturn(
            node: node.returnClause.type,
            modifiers: node.modifiers,
            message: "non-private tuple return type",
            expectation: "cross-file subscript results use named Swift types"
        )
        recordExportedTupleParameters(
            node: node,
            modifiers: node.modifiers,
            parameters: node.parameterClause.parameters
        )
        return .visitChildren
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        recordExportedTupleTypealias(node)
        recordTopLevelTypealias(node)
        recordCompatibilitySurface(
            node: node,
            modifiers: node.modifiers,
            attributes: node.attributes,
            name: node.name.text
        )
        return .skipChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        recordRetiredVariableSymbols(node)
        recordSiblingReceiptWarnings(node)
        recordVariableCompatibilitySurface(node)
        recordTupleProperty(node)
        recordNonPrivateTupleProperty(node)
        return .visitChildren
    }

    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        recordAnyBoundaryUse(node)
        recordJSONBoundaryUse(node, observed: node.name.text)
        return .visitChildren
    }

    override func visit(_ node: AttributedTypeSyntax) -> SyntaxVisitorContinueKind {
        recordUncheckedSendableUse(node)
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        recordRetiredCallLabels(node)
        recordOldTraceSettlementJSON(node)
        recordOwnedPipelineConstruction(node)
        recordRawNotificationNormalization(node)
        return .visitChildren
    }

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        let observed = node.baseName.text
        recordJSONBoundaryUse(node, observed: observed)
        recordPurePipelineEffectUse(node, observed: observed)
        return .visitChildren
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        let observed = node.declName.baseName.text
        recordDemoAccessibilityIdentifierUse(node, observed: observed)
        recordJSONBoundaryUse(node, observed: observed)
        recordPurePipelineEffectUse(node, observed: observed)
        return .visitChildren
    }

    override func visit(_ node: EnumCaseDeclSyntax) -> SyntaxVisitorContinueKind {
        recordContainerSemanticIdentifierAlias(node)
        recordSiblingReceiptWarnings(node)
        return .visitChildren
    }

    private func recordRetiredVariableSymbols(_ node: VariableDeclSyntax) {
        for binding in node.bindings {
            guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
            recordRetiredSourceSymbol(node: identifier, observed: identifier.identifier.text)
        }
    }

    private func recordRetiredCallLabels(_ node: FunctionCallExprSyntax) {
        for argument in node.arguments {
            guard let label = argument.label?.text else { continue }
            recordRetiredSourceSymbol(node: argument, observed: label)
        }
    }

    private func recordRetiredParameterLabels(_ parameters: FunctionParameterListSyntax) {
        for parameter in parameters {
            recordRetiredSourceSymbol(node: parameter, observed: parameter.firstName.text)
            if let secondName = parameter.secondName?.text {
                recordRetiredSourceSymbol(node: parameter, observed: secondName)
            }
        }
    }

    private func recordRetiredSourceSymbol(node: some SyntaxProtocol, observed: String) {
        guard retiredProductionSymbols.contains(observed) else { return }
        failures.append(
            file.failure(
                at: node,
                message: "retired production source symbol",
                evidence: ViolationEvidence(
                    observed: observed,
                    expectation: "production source uses the canonical admitted and typed architecture"
                )
            )
        )
    }

    private func recordRawExecutableParameters(_ node: FunctionDeclSyntax) {
        guard filePath.hasPrefix("ButtonHeist/Sources/"),
              node.name.text.lowercased().hasPrefix("execute") else {
            return
        }

        for parameter in node.signature.parameterClause.parameters where isRawCommandArgumentType(parameter.type) {
            failures.append(
                file.failure(
                    at: parameter.type,
                    message: "raw command arguments in executable runtime API",
                    evidence: ViolationEvidence(
                        observed: parameter.type.trimmedDescription,
                        expectation: "execution accepts an admitted typed request"
                    )
                )
            )
        }
    }

    private func recordContainerSemanticIdentifierAlias(_ node: FunctionDeclSyntax) {
        guard node.name.text == "identifier",
              enclosingExtensionType(of: node) == "SemanticContainerPredicate" else {
            return
        }
        recordContainerSemanticIdentifierAlias(at: node)
    }

    private func recordContainerSemanticIdentifierAlias(_ node: EnumCaseDeclSyntax) {
        guard enclosingNominalType(of: node) == "SemanticContainerPredicate",
              node.elements.contains(where: { $0.name.text == "identifier" }) else {
            return
        }
        recordContainerSemanticIdentifierAlias(at: node)
    }

    private func recordContainerSemanticIdentifierAlias(at node: some SyntaxProtocol) {
        failures.append(
            file.failure(
                at: node,
                message: "container semantic identifier alias",
                evidence: ViolationEvidence(
                    observed: "SemanticContainerPredicate.identifier",
                    expectation: "container identifiers use ContainerPredicateCheck.identifier"
                )
            )
        )
    }

    private func recordSiblingReceiptWarnings(_ node: VariableDeclSyntax) {
        guard isTopLevelOrFirstLevelMember(node),
              enclosingNominalType(of: node) == "HeistExecutionEvidenceRollup",
              node.bindings.contains(where: {
                  $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "warnings"
              }) else {
            return
        }
        recordSiblingReceiptWarning(at: node, observed: "HeistExecutionEvidenceRollup.warnings")
    }

    private func recordSiblingReceiptWarnings(_ node: EnumCaseDeclSyntax) {
        guard enclosingNominalType(of: node) == "HeistExecutionEvidenceEvent",
              node.elements.contains(where: { $0.name.text == "warning" }) else {
            return
        }
        recordSiblingReceiptWarning(at: node, observed: "HeistExecutionEvidenceEvent.warning")
    }

    private func recordSiblingReceiptWarning(at node: some SyntaxProtocol, observed: String) {
        failures.append(
            file.failure(
                at: node,
                message: "sibling heist receipt warning pipeline",
                evidence: ViolationEvidence(
                    observed: observed,
                    expectation: "warnings are derived from canonical receipt nodes and action results"
                )
            )
        )
    }

    private func recordActionObservationWireShape(_ node: EnumDeclSyntax) {
        guard node.name.text == "ActionResultObservationEvidence",
              let kind = node.memberBlock.members.compactMap({ member in
                  member.decl.as(EnumDeclSyntax.self)
              }).first(where: { $0.name.text == "Kind" }) else {
            return
        }
        let cases = enumCaseNames(in: kind)
        guard cases.contains("trace"), !cases.contains("settledTrace") else { return }
        failures.append(
            file.failure(
                at: kind,
                message: "trace and settlement share an old JSON discriminator",
                evidence: ViolationEvidence(
                    observed: "trace without settledTrace",
                    expectation: "settled trace evidence has its own settledTrace wire kind"
                )
            )
        )
    }

    private func recordOldTraceSettlementJSON(_ node: FunctionCallExprSyntax) {
        guard node.calledExpression.trimmedDescription.hasSuffix(".decodeIfPresent"),
              node.arguments.first?.expression.trimmedDescription == "ActionSettlementEvidence.self" else {
            return
        }
        failures.append(
            file.failure(
                at: node,
                message: "optional settlement in trace JSON",
                evidence: ViolationEvidence(
                    observed: "decodeIfPresent(ActionSettlementEvidence.self)",
                    expectation: "trace and settledTrace decode as distinct wire kinds"
                )
            )
        )
    }

    private func recordTopLevelTypealias(_ node: TypeAliasDeclSyntax) {
        guard isTopLevel(node),
              isExported(node.modifiers),
              !isButtonHeistDSLFacade(file.path) else {
            return
        }

        failures.append(
            file.failure(
                at: node,
                message: "exported top-level typealias outside ButtonHeistDSL facade",
                evidence: ViolationEvidence(
                    observed: node.name.text,
                    expectation: "top-level exported typealiases live in ButtonHeistDSL.swift"
                )
            )
        )
    }

    private func recordSelectorShortcut(_ node: FunctionDeclSyntax) {
        guard isTopLevel(node),
              isExported(node.modifiers),
              ["predicateCandidates", "minimumUniquePredicate"].contains(node.name.text) else {
            return
        }

        failures.append(
            file.failure(
                at: node,
                message: "exported top-level minimum predicate selector shortcut",
                evidence: ViolationEvidence(
                    observed: node.name.text,
                    expectation: "selector shortcuts stay behind named types or internal helpers"
                )
            )
        )
    }

    private func recordCompatibilitySurface(
        node: some SyntaxProtocol,
        modifiers: DeclModifierListSyntax,
        attributes: AttributeListSyntax,
        name: String
    ) {
        guard isExported(modifiers) else {
            return
        }

        recordDeprecatedDeclaration(node: node, attributes: attributes)
        guard isCompatibilityName(name) else {
            return
        }

        failures.append(
            file.failure(
                at: node,
                message: "exported compatibility/legacy helper name",
                evidence: ViolationEvidence(
                    observed: name,
                    expectation: "exported API names avoid legacy/compatibility/deprecated spellings"
                )
            )
        )
    }

    private func recordVariableCompatibilitySurface(_ node: VariableDeclSyntax) {
        guard isExported(node.modifiers) else {
            return
        }

        recordDeprecatedDeclaration(node: node, attributes: node.attributes)
        for binding in node.bindings {
            guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                  isCompatibilityName(name) else {
                continue
            }
            failures.append(
                file.failure(
                    at: binding,
                    message: "exported compatibility/legacy helper name",
                    evidence: ViolationEvidence(
                        observed: name,
                        expectation: "exported API names avoid legacy/compatibility/deprecated spellings"
                    )
                )
            )
        }
    }

    private func recordDeprecatedDeclaration(
        node: some SyntaxProtocol,
        attributes: AttributeListSyntax
    ) {
        guard hasDeprecatedAttribute(attributes) else {
            return
        }

        failures.append(
            file.failure(
                at: node,
                message: "exported deprecated compatibility helper",
                evidence: ViolationEvidence(
                    observed: node.trimmedDescription,
                    expectation: "exported API should not carry deprecated compatibility shims"
                )
            )
        )
    }

    private func recordTupleReturn(
        modifiers: DeclModifierListSyntax,
        returnType: TypeSyntax?,
        message: String,
        expectation: String
    ) {
        guard isExported(modifiers),
              let returnType,
              isTupleType(returnType) else {
            return
        }

        failures.append(
            file.failure(
                at: returnType,
                message: message,
                evidence: ViolationEvidence(
                    observed: returnType.trimmedDescription,
                    expectation: expectation
                )
            )
        )
    }

    private func recordExportedTupleParameters(
        node: some SyntaxProtocol,
        modifiers: DeclModifierListSyntax,
        parameters: FunctionParameterListSyntax
    ) {
        guard isEffectivelyExported(node, modifiers: modifiers) else { return }

        for parameter in parameters where isTupleType(parameter.type) {
            failures.append(
                file.failure(
                    at: parameter.type,
                    message: "exported tuple parameter type",
                    evidence: ViolationEvidence(
                        observed: parameter.type.trimmedDescription,
                        expectation: "public and package parameters use named Swift types"
                    )
                )
            )
        }
    }

    private func recordExportedTupleTypealias(_ node: TypeAliasDeclSyntax) {
        let type = node.initializer.value
        guard isEffectivelyExported(node, modifiers: node.modifiers), isTupleType(type) else { return }

        failures.append(
            file.failure(
                at: type,
                message: "exported tuple typealias",
                evidence: ViolationEvidence(
                    observed: type.trimmedDescription,
                    expectation: "public and package aliases use named Swift types"
                )
            )
        )
    }

    private func recordTupleProperty(_ node: VariableDeclSyntax) {
        guard isExported(node.modifiers) else {
            return
        }

        for binding in node.bindings {
            guard let type = binding.typeAnnotation?.type, isTupleType(type) else {
                continue
            }

            failures.append(
                file.failure(
                    at: type,
                    message: "exported tuple property type",
                    evidence: ViolationEvidence(
                        observed: type.trimmedDescription,
                        expectation: "exported properties use named Swift types"
                    )
                )
            )
        }
    }

    private func recordNonPrivateTupleReturn(
        node: TypeSyntax?,
        modifiers: DeclModifierListSyntax,
        message: String,
        expectation: String
    ) {
        guard !isPrivate(modifiers),
              !isExported(modifiers),
              let node,
              isTupleType(node) else {
            return
        }

        failures.append(
            file.failure(
                at: node,
                message: message,
                evidence: ViolationEvidence(
                    observed: node.trimmedDescription,
                    expectation: expectation
                )
            )
        )
    }

    private func recordNonPrivateTupleProperty(_ node: VariableDeclSyntax) {
        guard !isPrivate(node.modifiers),
              !isExported(node.modifiers),
              isTopLevelOrFirstLevelMember(node) else {
            return
        }

        for binding in node.bindings {
            guard let type = binding.typeAnnotation?.type, isTupleType(type) else {
                continue
            }

            failures.append(
                file.failure(
                    at: type,
                    message: "non-private tuple property type",
                    evidence: ViolationEvidence(
                        observed: type.trimmedDescription,
                        expectation: "stored and cross-file properties use named Swift types"
                    )
                )
            )
        }
    }

    private func recordAnyBoundaryUse(_ node: IdentifierTypeSyntax) {
        guard node.name.text == "Any",
              !anyBoundaryAllowedPaths.contains(filePath) else {
            return
        }

        failures.append(
            file.failure(
                at: node,
                message: "Any outside explicit boundary file",
                evidence: ViolationEvidence(
                    observed: node.trimmedDescription,
                    expectation: "normalize Foundation/ObjC/SPI Any values at named boundary files"
                )
            )
        )
    }

    private func recordUncheckedSendableUse(_ node: AttributedTypeSyntax) {
        guard !filePath.hasPrefix(insideJobSourcePrefix),
              node.baseType.as(IdentifierTypeSyntax.self)?.name.text == "Sendable",
              node.attributes.contains(where: { element in
                  guard let attribute = element.as(AttributeSyntax.self),
                        let name = attribute.attributeName.as(IdentifierTypeSyntax.self)?.name else {
                      return false
                  }
                  return name.tokenKind == .keyword(.unchecked)
              }) else {
            return
        }

        failures.append(
            file.failure(
                at: node,
                message: "@unchecked Sendable outside TheInsideJob platform boundary",
                evidence: ViolationEvidence(
                    observed: node.trimmedDescription,
                    expectation: "@unchecked Sendable is allowed only under \(insideJobSourcePrefix)"
                )
            )
        )
    }

    private func recordJSONBoundaryUse(_ node: some SyntaxProtocol, observed: String) {
        guard jsonBoundarySymbols.contains(observed),
              !jsonBoundaryAllowedPaths.contains(filePath) else {
            return
        }

        failures.append(
            file.failure(
                at: node,
                message: "ad hoc JSON codec outside canonical boundary",
                evidence: ViolationEvidence(
                    observed: observed,
                    expectation: "JSON encoding/decoding lives in explicit codec, serializer, wire, or bridge files"
                )
            )
        )
    }

    private func recordPurePipelineEffectUse(_ node: some SyntaxProtocol, observed: String) {
        // These APIs are not forbidden globally. In reducer/state/evaluation files,
        // they are proxies for effects: time, scheduling, global event streams, live
        // UI mutation, or external I/O. Those files should transform snapshots into
        // state plus explicit effect descriptions; boundary files perform effects.
        guard purePipelineEffectCheckedPaths.contains(filePath),
              purePipelineEffectSymbols.contains(observed) else {
            return
        }

        failures.append(
            file.failure(
                at: node,
                message: "effectful API in reducer/state/evaluation pipeline file",
                evidence: ViolationEvidence(
                    observed: observed,
                    expectation: "reducers and evaluation pipelines stay pure; boundary code performs effects"
                )
            )
        )
    }

    private func recordOwnedPipelineConstruction(_ node: FunctionCallExprSyntax) {
        guard filePath.hasPrefix("ButtonHeist/Sources/"),
              let ownership = pipelineConstructionOwnership[node.calledExpression.trimmedDescription],
              !ownership.allowedPaths.contains(filePath) else {
            return
        }

        failures.append(
            file.failure(
                at: node.calledExpression,
                message: "pipeline value constructed outside its canonical owner",
                evidence: ViolationEvidence(
                    observed: "\(ownership.symbol) in \(filePath)",
                    expectation: ownership.expectation
                )
            )
        )
    }

    private func recordRawNotificationNormalization(_ node: FunctionCallExprSyntax) {
        guard filePath.hasPrefix("ButtonHeist/Sources/"),
              node.calledExpression.trimmedDescription == "AccessibilityNotificationKind",
              node.arguments.contains(where: { $0.label?.text == "rawCode" }),
              filePath != accessibilityNotificationRawCodeOwnerPath else {
            return
        }

        failures.append(
            file.failure(
                at: node,
                message: "raw accessibility notification normalized outside Tripwire",
                evidence: ViolationEvidence(
                    observed: filePath,
                    expectation: "raw UIKit notification codes enter through \(accessibilityNotificationRawCodeOwnerPath)"
                )
            )
        )
    }

    private func recordDemoAccessibilityIdentifierUse(_ node: some SyntaxProtocol, observed: String) {
        guard observed == "accessibilityIdentifier",
              filePath.hasPrefix("TestApp/Sources/"),
              !demoAccessibilityIdentifierAllowedPaths.contains(filePath) else {
            return
        }

        failures.append(
            file.failure(
                at: node,
                message: "demo screen uses accessibilityIdentifier",
                evidence: ViolationEvidence(
                    observed: observed,
                    expectation: "demo screens are findable through real accessibility labels, values, traits, hints, and actions"
                )
            )
        )
    }

    private func recordExplicitAccess(
        node: some SyntaxProtocol,
        modifiers: DeclModifierListSyntax,
        name: String
    ) {
        guard requiresExplicitAccess,
              isTopLevelOrFirstLevelMember(node),
              !hasProtocolAncestor(node),
              !hasAccessQualifiedExtensionAncestor(node),
              !hasExplicitAccess(modifiers) else {
            return
        }

        failures.append(
            file.failure(
                at: node,
                message: "implicit access in owner-scoped pipeline file",
                evidence: ViolationEvidence(
                    observed: name,
                    expectation: "owner-scoped pipeline declarations spell access explicitly"
                )
            )
        )
    }
}

private final class InsideJobArchitecturalShapeRuleVisitor: SyntaxVisitor {
    private let file: SourceFileContext
    private(set) var failures: [CustomRuleFailure] = []

    init(file: SourceFileContext, viewMode: SyntaxTreeViewMode) {
        self.file = file
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        recordForbiddenReference(node: node, observed: node.name.text)
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        recordForbiddenReference(node: node, observed: node.name.text)
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        recordForbiddenReference(node: node, observed: node.name.text)
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        recordForbiddenReference(node: node, observed: node.name.text)
        return .visitChildren
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        recordForbiddenReference(node: node, observed: node.name.text)
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        recordForbiddenReference(node: node, observed: node.name.text)
        recordRawSemanticCommit(node)
        return .visitChildren
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        recordForbiddenReference(node: node, observed: node.name.text)
        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for binding in node.bindings {
            guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
            recordForbiddenReference(node: identifier, observed: identifier.identifier.text)
        }
        return .visitChildren
    }

    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        recordForbiddenReference(node: node, observed: node.name.text)
        return .visitChildren
    }

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        recordForbiddenReference(node: node, observed: node.baseName.text)
        return .visitChildren
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        recordForbiddenReference(node: node, observed: node.declName.baseName.text)
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let callShape = node.calledExpression.trimmedDescription
        guard interfaceObservationTestingCallShapes.contains(callShape),
              enclosingFunctionName(of: node)?.hasSuffix("ForTesting") != true else {
            return .visitChildren
        }

        recordFailure(
            at: node.calledExpression,
            observed: "InterfaceObservationProof.testing",
            expectation: """
            InterfaceObservationProof.testing calls stay inside explicit \
            ForTesting fixture methods
            """
        )
        return .visitChildren
    }

    private func recordForbiddenReference(node: some SyntaxProtocol, observed: String) {
        guard isForbiddenInsideJobArchitectureSymbol(observed) else { return }
        recordFailure(
            at: node,
            observed: observed,
            expectation: """
            reveal retries await settled visible observations, refresh live \
            capture, and resolve before the action deadline
            """
        )
    }

    private func recordRawSemanticCommit(_ node: FunctionDeclSyntax) {
        let name = node.name.text
        let lowercasedName = name.lowercased()
        guard lowercasedName.hasPrefix("commit"),
              lowercasedName.contains("semantic") || lowercasedName.contains("observation"),
              !name.hasSuffix("ForTesting"),
              let firstType = node.signature.parameterClause.parameters.first?.type,
              rawSemanticCommitTypes.contains(unwrappedOptionalTypeName(firstType)) else {
            return
        }
        recordFailure(
            at: firstType,
            observed: "\(name)(\(firstType.trimmedDescription))",
            expectation: "semantic commits require settled or explored InterfaceObservationProof"
        )
    }

    private func recordFailure(
        at node: some SyntaxProtocol,
        observed: String,
        expectation: String
    ) {
        failures.append(file.failure(
            at: node,
            message: "forbidden InsideJob architectural source shape",
            evidence: ViolationEvidence(observed: observed, expectation: expectation)
        ))
    }
}

private struct PipelineConstructionOwnership {
    let symbol: String
    let allowedPaths: Set<String>
    let expectation: String
}

private let reportPipelineOwnerPath =
    "ButtonHeist/Sources/TheScore/Reports/HeistExecutionResult+Report.swift"

private let pipelineConstructionOwnership: [String: PipelineConstructionOwnership] = [
    "HeistExecutionEvidenceRollup": PipelineConstructionOwnership(
        symbol: "HeistExecutionEvidenceRollup",
        allowedPaths: [reportPipelineOwnerPath],
        expectation: "execution evidence rollup construction stays in \(reportPipelineOwnerPath)"
    ),
    "HeistExecutionStepReportFacts": PipelineConstructionOwnership(
        symbol: "HeistExecutionStepReportFacts",
        allowedPaths: [reportPipelineOwnerPath],
        expectation: "step report fact construction stays in \(reportPipelineOwnerPath)"
    ),
    "ActionResultEvidence": PipelineConstructionOwnership(
        symbol: "ActionResultEvidence",
        allowedPaths: [
            "ButtonHeist/Sources/TheInsideJob/TheBrains/PostActionObservation.swift",
            "ButtonHeist/Sources/TheInsideJob/TheBrains/TheBrains+HeistWaitExecution.swift",
            "ButtonHeist/Sources/TheInsideJob/TheBrains/TheBrains+ScreenCapture.swift",
            "ButtonHeist/Sources/TheScore/Reports/ActionResultPayloads.swift",
        ],
        expectation: "action result evidence is assembled only by its value owner or runtime evidence producers"
    ),
    "InterfaceObservation": PipelineConstructionOwnership(
        symbol: "InterfaceObservation",
        allowedPaths: [
            "ButtonHeist/Sources/TheInsideJob/TheStash/InterfaceObservation.swift",
        ],
        expectation: "production observations enter through InterfaceObservation.build"
    ),
    "LiveCapture": PipelineConstructionOwnership(
        symbol: "LiveCapture",
        allowedPaths: [
            "ButtonHeist/Sources/TheInsideJob/TheStash/LiveCapture.swift",
        ],
        expectation: "production live captures enter through LiveCapture.build"
    ),
]

private let accessibilityNotificationRawCodeOwnerPath =
    "ButtonHeist/Sources/TheInsideJob/TheTripwire/AccessibilityNotificationBus.swift"

private func scoreFolderAllowedImports(for path: String) -> Set<String>? {
    if path.hasPrefix("ButtonHeist/Sources/TheScore/Wire/") {
        return ["AccessibilitySnapshotModel", "CoreGraphics", "Foundation", "ThePlans"]
    }
    if path.hasPrefix("ButtonHeist/Sources/TheScore/Evidence/") {
        return ["AccessibilitySnapshotModel", "CryptoKit", "Foundation", "ThePlans"]
    }
    if path.hasPrefix("ButtonHeist/Sources/TheScore/Receipts/") {
        return ["CryptoKit", "Foundation", "OSLog", "ThePlans", "zlib"]
    }
    if path.hasPrefix("ButtonHeist/Sources/TheScore/Reports/")
        || path.hasPrefix("ButtonHeist/Sources/TheScore/Diagnostics/") {
        return ["Foundation", "ThePlans"]
    }
    if path == "ButtonHeist/Sources/TheScore/Core/TLSPreSharedKeyMaterial.swift" {
        return ["CryptoKit", "Dispatch", "Foundation", "Network", "Security"]
    }
    if path == "ButtonHeist/Sources/TheScore/Core/ButtonHeistLog.swift" {
        return ["OSLog"]
    }
    if path.hasPrefix("ButtonHeist/Sources/TheScore/Core/") {
        return ["AccessibilitySnapshotModel", "Foundation", "ThePlans"]
    }
    return nil
}

private let frameworkSandboxComponentIDs = [
    "plans",
    "score",
    "dsl",
    "doctor",
    "runtime",
    "testing",
    "tools",
    "mcp",
    "demo",
]

private struct FrameworkImportSandbox {
    let displayName: String
    let exactImports: Set<String>
    let importPrefixes: Set<String>
    let allowedPaths: Set<String>
    let allowedPathPrefixes: Set<String>
    let expectation: String

    func matches(_ importedModule: String) -> Bool {
        exactImports.contains(importedModule)
            || importPrefixes.contains { importedModule.hasPrefix($0) }
    }

    func allows(_ path: String) -> Bool {
        allowedPaths.contains(path)
            || allowedPathPrefixes.contains { path.hasPrefix($0) }
    }
}

// Frameworks below are not forbidden; they are boundary tools. The sandbox keeps
// each tool in its fiefdom so values flow inward as Button Heist types instead
// of letting live UI, network, security, SPI, or demo frameworks leak everywhere.
private let frameworkSandboxes: [FrameworkImportSandbox] = [
    FrameworkImportSandbox(
        displayName: "UIKit",
        exactImports: ["UIKit"],
        importPrefixes: [],
        allowedPaths: [
            "ButtonHeist/Sources/TheInsideJob/AccessibilityElement+Geometry.swift",
            "ButtonHeist/Sources/TheInsideJob/InsideJobAppLifecycle.swift",
            "ButtonHeist/Sources/TheInsideJob/InsideJobExposureRuntime.swift",
            "ButtonHeist/Sources/TheInsideJob/InsideJobRuntimeResources.swift",
            "ButtonHeist/Sources/TheInsideJob/InsideJobTransportRuntime.swift",
            "ButtonHeist/Sources/TheInsideJob/Lifecycle/AutoStart.swift",
            "ButtonHeist/Sources/TheInsideJob/SafeGeometryHashing.swift",
            "ButtonHeist/Sources/TheInsideJob/Server/TheMuscle.swift",
            "ButtonHeist/Sources/TheInsideJob/TheInsideJob.swift",
        ],
        allowedPathPrefixes: [
            "ButtonHeist/Sources/TheInsideJob/Support/",
            "ButtonHeist/Sources/TheInsideJob/TheBrains/",
            "ButtonHeist/Sources/TheInsideJob/TheBurglar/",
            "ButtonHeist/Sources/TheInsideJob/TheGetaway/",
            "ButtonHeist/Sources/TheInsideJob/TheSafecracker/",
            "ButtonHeist/Sources/TheInsideJob/TheStash/",
            "ButtonHeist/Sources/TheInsideJob/TheTripwire/",
            "TestApp/Sources/",
        ],
        expectation: """
        UIKit imports stay in runtime UI fiefdoms: app lifecycle, support bridges, \
        TheBrains action/navigation/capture boundaries, TheBurglar capture, \
        TheSafecracker input injection, TheStash live lookup/capture, TheTripwire \
        observation, TheGetaway UI status, or demo screens.
        """
    ),
    FrameworkImportSandbox(
        displayName: "SwiftUI",
        exactImports: ["SwiftUI"],
        importPrefixes: [],
        allowedPaths: [
            "ButtonHeist/Sources/TheInsideJob/TheBrains/TheBrains+AccessibilitySnapshot.swift",
            "ButtonHeist/Sources/TheInsideJob/TheSafecracker/TheFingerprints.swift",
        ],
        allowedPathPrefixes: [
            "TestApp/Sources/",
        ],
        expectation: "SwiftUI imports stay in demo screens or explicit preview/input-injection bridges."
    ),
    FrameworkImportSandbox(
        displayName: "Network",
        exactImports: ["Network"],
        importPrefixes: [],
        allowedPaths: [
            "ButtonHeist/Sources/ButtonHeistSupport/NetworkTransportFailure.swift",
            "ButtonHeist/Sources/TheButtonHeist/TheHandoff/DeviceDiscovery.swift",
            "ButtonHeist/Sources/TheButtonHeist/TheHandoff/DeviceDiscoveryAdvertisement.swift",
            "ButtonHeist/Sources/TheButtonHeist/TheHandoff/DeviceProtocols.swift",
            "ButtonHeist/Sources/TheInsideJob/Server/ServerSendOutcome.swift",
            "ButtonHeist/Sources/TheInsideJob/Server/ServerTransport.swift",
            "ButtonHeist/Sources/TheScore/Core/TLSPreSharedKeyMaterial.swift",
        ],
        allowedPathPrefixes: [
            "ButtonHeist/Sources/TheButtonHeist/TheHandoff/NetworkBoundary/",
            "ButtonHeist/Sources/TheInsideJob/Server/NetworkBoundary/",
        ],
        expectation: "Network imports stay in shared transport diagnostics, TheHandoff, server network boundaries, or TLS key material."
    ),
    FrameworkImportSandbox(
        displayName: "Security",
        exactImports: ["Security"],
        importPrefixes: [],
        allowedPaths: [
            "ButtonHeist/Sources/TheScore/Core/TLSPreSharedKeyMaterial.swift",
        ],
        allowedPathPrefixes: [],
        expectation: "Security imports stay in TLS key material."
    ),
    FrameworkImportSandbox(
        displayName: "Objective-C runtime",
        exactImports: ["ObjectiveC.runtime"],
        importPrefixes: ["ObjectiveC"],
        allowedPaths: [
            "ButtonHeist/Sources/TheInsideJob/Support/AXMethodOverrides.swift",
        ],
        allowedPathPrefixes: [],
        expectation: "Objective-C runtime imports stay in explicit SPI/method-override support files."
    ),
    FrameworkImportSandbox(
        displayName: "AccessibilitySnapshotParser",
        exactImports: [
            "AccessibilitySnapshotCore",
            "AccessibilitySnapshotParser",
            "AccessibilitySnapshotPreviews",
        ],
        importPrefixes: [],
        allowedPaths: [
            "ButtonHeist/Sources/TheInsideJob/AccessibilityElement+Geometry.swift",
            "ButtonHeist/Sources/TheInsideJob/SafeGeometryHashing.swift",
        ],
        allowedPathPrefixes: [
            "ButtonHeist/Sources/TheInsideJob/TheBrains/",
            "ButtonHeist/Sources/TheInsideJob/TheBurglar/",
            "ButtonHeist/Sources/TheInsideJob/TheStash/",
        ],
        expectation: """
        Accessibility snapshot SPI/parser imports stay at live capture, live lookup, \
        screen building, and action/navigation evidence boundaries.
        """
    ),
]

private func frameworkSandbox(for importedModule: String) -> FrameworkImportSandbox? {
    frameworkSandboxes.first { $0.matches(importedModule) }
}

private let explicitAccessRequiredPaths: Set<String> = [
    "ButtonHeist/Sources/TheButtonHeist/TheFence/FenceParameter.swift",
    "ButtonHeist/Sources/TheButtonHeist/TheFence/FenceParameter+Schema.swift",
    "ButtonHeist/Sources/TheButtonHeist/TheFence/FenceParameter+Decoding.swift",
    "ButtonHeist/Sources/TheButtonHeist/TheFence/FenceParameter+Factories.swift",
    "ButtonHeist/Sources/TheButtonHeist/TheFence/FenceParameterBlocks.swift",
    "ButtonHeist/Sources/ThePlans/Model/ElementPropertyKind.swift",
    "ButtonHeist/Sources/ThePlans/Model/ElementPropertyMatches.swift",
    "ButtonHeist/Sources/ThePlans/Model/ElementPropertyChange.swift",
    "ButtonHeist/Sources/ThePlans/Model/ElementPropertyChange+Any.swift",
    "ButtonHeist/Sources/ThePlans/Model/ElementPropertyChange+Codable.swift",
    "ButtonHeist/Sources/ThePlans/Model/ElementPropertyChange+Description.swift",
    "ButtonHeist/Sources/TheInsideJob/TheBrains/ElementInflation.swift",
    "ButtonHeist/Sources/TheInsideJob/TheBrains/ElementInflation+State.swift",
    "ButtonHeist/Sources/TheInsideJob/TheBrains/ElementInflation+Resolution.swift",
    "ButtonHeist/Sources/TheInsideJob/TheBrains/ElementInflation+Reveal.swift",
    "ButtonHeist/Sources/TheInsideJob/TheBrains/ElementInflation+Geometry.swift",
    "ButtonHeist/Sources/TheInsideJob/TheBrains/ElementInflation+Failures.swift",
    "ButtonHeist/Sources/TheInsideJob/TheBrains/ElementInflation+FirstResponder.swift",
    "ButtonHeist/Sources/TheInsideJob/TheBrains/PredicateWait.swift",
    "ButtonHeist/Sources/TheInsideJob/TheBrains/PredicateWait+Reducer.swift",
    "ButtonHeist/Sources/TheInsideJob/TheBrains/PredicateWait+ObservationStream.swift",
    "ButtonHeist/Sources/TheInsideJob/TheBrains/PredicateWait+Polling.swift",
    "ButtonHeist/Sources/TheInsideJob/TheBrains/PredicateWait+Evidence.swift",
    "ButtonHeist/Sources/TheInsideJob/TheBrains/PredicateWait+Receipts.swift",
    "ButtonHeist/Sources/TheInsideJob/TheBrains/TheBrains+HeistExecution.swift",
    "ButtonHeist/Sources/TheInsideJob/TheBrains/TheBrains+HeistExecutionAccumulator.swift",
    "ButtonHeist/Sources/TheInsideJob/TheBrains/TheBrains+HeistInvocationExecution.swift",
    "ButtonHeist/Sources/TheInsideJob/TheBrains/TheBrains+HeistExecutionReceipts.swift",
    "ButtonHeist/Sources/TheInsideJob/TheBrains/TheBrains+HeistExecutionFailures.swift",
    "ButtonHeist/Sources/TheInsideJob/TheBrains/TheBrains+HeistRepeatUntilExecution.swift",
    "ButtonHeist/Sources/TheInsideJob/TheBrains/TheBrains+RepeatUntilState.swift",
    "ButtonHeist/Sources/TheInsideJob/TheBrains/TheBrains+RepeatUntilPredicateEvaluation.swift",
    "ButtonHeist/Sources/TheInsideJob/TheBrains/TheBrains+RepeatUntilReceipts.swift",
    "ButtonHeist/Sources/TheInsideJob/TheBrains/TheBrains+RepeatUntilFailures.swift",
]

private struct ArchitectureCurrencyDeclaration {
    let path: RelativeFilePath
    let location: SourcePosition?
}

private func architectureCurrencyOwnershipFailures(
    in context: CustomRuleContext
) -> [CustomRuleFailure] {
    let configuredPathFailures = Set(architectureCurrencyOwnerPaths.values)
        .sorted()
        .compactMap { rawOwnerPath -> CustomRuleFailure? in
            let symbols = architectureCurrencyOwnerPaths
                .filter { $0.value == rawOwnerPath }
                .keys
                .sorted()
                .joined(separator: ", ")
            guard let ownerPath = try? RelativeFilePath(rawOwnerPath) else {
                return context.files.first.map { file in
                    CustomRuleFailure(
                        path: file.path,
                        message: "configured architecture currency owner path is invalid",
                        evidence: ViolationEvidence(
                            observed: rawOwnerPath,
                            expectation: "\(symbols) have a normalized repository-relative owner path"
                        )
                    )
                }
            }
            guard !context.files.contains(where: { $0.path == ownerPath }) else { return nil }
            return CustomRuleFailure(
                path: ownerPath,
                message: "configured architecture currency owner path does not exist",
                evidence: ViolationEvidence(
                    observed: rawOwnerPath,
                    expectation: "owner path for \(symbols) is present in Bumper's source input"
                )
            )
        }

    let missingOwnerPaths = Set(configuredPathFailures.map(\.path))
    let declarationFailures = architectureCurrencyOwnerPaths
        .sorted { $0.key < $1.key }
        .flatMap { ownership -> [CustomRuleFailure] in
            let (symbol, rawOwnerPath) = ownership
            guard let ownerPath = try? RelativeFilePath(rawOwnerPath),
                  !missingOwnerPaths.contains(ownerPath) else {
                return []
            }

            let declarations = context.files.flatMap { file in
                file.nominalTypes
                    .filter { $0.name == symbol }
                    .map { declaration in
                        ArchitectureCurrencyDeclaration(
                            path: file.path,
                            location: declaration.location
                        )
                    }
            }
            guard declarations.count == 1 else {
                return [
                    CustomRuleFailure(
                        path: ownerPath,
                        message: "architecture currency symbol must be declared exactly once",
                        evidence: ViolationEvidence(
                            observed: "\(symbol) has \(declarations.count) declarations",
                            expectation: "one declaration in \(rawOwnerPath)"
                        )
                    ),
                ]
            }

            let declaration = declarations[0]
            guard declaration.path == ownerPath else {
                return [
                    CustomRuleFailure(
                        path: declaration.path,
                        location: declaration.location,
                        message: "architecture currency declared outside its canonical owner",
                        evidence: ViolationEvidence(
                            observed: "\(symbol) in \(declaration.path.rawValue)",
                            expectation: "\(symbol) is declared only in \(rawOwnerPath)"
                        )
                    ),
                ]
            }
            return []
        }
    return configuredPathFailures + declarationFailures
}

private let architectureCurrencyOwnerPaths: [String: String] = [
    "AccessibilityContainerKind": "ButtonHeist/Sources/ThePlans/Model/ContainerPredicate.swift",
    "AccessibilityPredicate": "ButtonHeist/Sources/ThePlans/Model/AccessibilityPredicate.swift",
    "AccessibilityTarget": "ButtonHeist/Sources/ThePlans/Model/AccessibilityTarget.swift",
    "ContainerPredicate": "ButtonHeist/Sources/ThePlans/Model/ContainerPredicate.swift",
    "ContainerPredicateActions": "ButtonHeist/Sources/ThePlans/Model/ContainerPredicate.swift",
    "ContainerPredicateCheck": "ButtonHeist/Sources/ThePlans/Model/ContainerPredicate.swift",
    "ContainerPredicateCount": "ButtonHeist/Sources/ThePlans/Model/ContainerPredicate.swift",
    "ContainerPredicateExpr": "ButtonHeist/Sources/ThePlans/Model/ContainerPredicate.swift",
    "ContainerPredicateFacts": "ButtonHeist/Sources/ThePlans/Model/ContainerPredicate.swift",
    "ContainerPredicateRoleFacts": "ButtonHeist/Sources/ThePlans/Model/ContainerPredicate.swift",
    "SemanticContainerPredicate": "ButtonHeist/Sources/ThePlans/Model/ContainerPredicate.swift",
    "AccessibilityTrace": "ButtonHeist/Sources/TheScore/Evidence/AccessibilityTrace.swift",
    "ChangeFact": "ButtonHeist/Sources/TheScore/Evidence/AccessibilityTrace+ChangeFacts.swift",
    "ElementMatchGraph": "ButtonHeist/Sources/TheScore/Core/ElementPredicate+HeistElement.swift",
    "ActionResultEvidence": "ButtonHeist/Sources/TheScore/Reports/ActionResultPayloads.swift",
    "HeistExecutionStepReportFacts": "ButtonHeist/Sources/TheScore/Reports/HeistExecutionResult+Report.swift",
    "InterfaceQuery": "ButtonHeist/Sources/TheScore/Wire/InterfaceQuery.swift",
    "ObservationWindow": "ButtonHeist/Sources/TheInsideJob/TheBrains/ObservationWindow.swift",
    "SettleLoopMachine": "ButtonHeist/Sources/TheInsideJob/TheBrains/SettleSession.swift",
    "SettleLoopRunner": "ButtonHeist/Sources/TheInsideJob/TheBrains/SettleSession.swift",
    "SettlePolicy": "ButtonHeist/Sources/TheInsideJob/TheBrains/SettleSession.swift",
    "InterfaceObservation": "ButtonHeist/Sources/TheInsideJob/TheStash/InterfaceObservation.swift",
    "InterfaceTree": "ButtonHeist/Sources/TheInsideJob/TheStash/InterfaceTree.swift",
    "LiveCapture": "ButtonHeist/Sources/TheInsideJob/TheStash/LiveCapture.swift",
]

private let anyBoundaryAllowedPaths: Set<String> = [
    "ButtonHeist/Sources/TheButtonHeist/Storage/PrivateStorage.swift",
    "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandArguments.swift",
    "ButtonHeist/Sources/TheInsideJob/Lifecycle/StartupConfiguration.swift",
]

private let insideJobSourcePrefix = "ButtonHeist/Sources/TheInsideJob/"

private let retiredProductionSymbols: Set<String> = [
    "runtimeValidatedVersion",
]

private let forbiddenInsideJobArchitectureSymbols: Set<String> = [
    "refreshCurrentVisibleTree",
    "refreshTreeAfterViewportMove",
]

private let rawSemanticCommitTypes: Set<String> = ["InterfaceObservation", "Screen"]

private let interfaceObservationTestingCallShapes: Set<String> = [
    ".testing",
    "InterfaceObservationProof.testing",
]

private let jsonBoundarySymbols: Set<String> = [
    "JSONDecoder",
    "JSONEncoder",
    "JSONSerialization",
]

private let jsonBoundaryAllowedPaths: Set<String> = [
    "ButtonHeistCLI/Sources/Commands/WaitCommand.swift",
    "ButtonHeistMCP/Sources/MCPValueBridge.swift",
    "ButtonHeist/Sources/HeistDoctorTool/main.swift",
    "ButtonHeist/Sources/TheButtonHeist/Config/TargetConfig.swift",
    "ButtonHeist/Sources/TheButtonHeist/TheFence/FenceResponsePresenter.swift",
    "ButtonHeist/Sources/TheButtonHeist/TheFence/PublicJSONInputLimits.swift",
    "ButtonHeist/Sources/TheButtonHeist/TheFence/PublicJSONSerializer.swift",
    "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandArguments.swift",
    "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+Formatting+Compact+Interface.swift",
    "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+Formatting+JSON.swift",
    "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+HeistPlanning.swift",
    "ButtonHeist/Sources/TheButtonHeist/TheHandoff/NetworkBoundary/DeviceConnection+Messages.swift",
    "ButtonHeist/Sources/TheButtonHeist/TheHandoff/NetworkBoundary/DeviceConnectionSending.swift",
    "ButtonHeist/Sources/TheInsideJob/Server/NetworkBoundary/SimpleSocketServer+Sending.swift",
    "ButtonHeist/Sources/TheInsideJob/TheBurglar/TheBurglar+InterfaceObservationBuilding.swift",
    "ButtonHeist/Sources/TheInsideJob/TheStash/InterfaceTree.swift",
    "ButtonHeist/Sources/ThePlans/Compilation/HeistPlanning.swift",
    "ButtonHeist/Sources/ThePlans/Compilation/HeistSwiftFileCompiler.swift",
    "ButtonHeist/Sources/ThePlans/Model/HeistActionCommand.swift",
    "ButtonHeist/Sources/ThePlans/Model/HeistArtifact.swift",
    "ButtonHeist/Sources/ThePlans/Model/HeistPlanJSONCodec.swift",
    "ButtonHeist/Sources/ThePlans/Parsing/HeistPlanSourceDiagnostics.swift",
    "ButtonHeist/Sources/ThePlans/Rendering/HeistCanonicalSwiftDSLRenderer+Formatting.swift",
    "ButtonHeist/Sources/ThePlans/Rendering/ScoreDescription.swift",
    "ButtonHeist/Sources/ThePlans/Validation/HeistPlan+RuntimeValidationPayloads.swift",
    "ButtonHeist/Sources/TheScore/Evidence/AccessibilityTraceCaptures.swift",
    "ButtonHeist/Sources/TheScore/Receipts/HeistReceiptCodec.swift",
    "ButtonHeist/Sources/TheScore/Wire/ClientMessages.swift",
    "ButtonHeist/Sources/TheScore/Wire/ServerMessages.swift",
]

private let purePipelineEffectCheckedPaths: Set<String> = [
    "ButtonHeist/Sources/TheInsideJob/TheBrains/ElementInflation+State.swift",
    "ButtonHeist/Sources/TheInsideJob/TheBrains/PredicatePollingReducer.swift",
    "ButtonHeist/Sources/TheInsideJob/TheBrains/PredicateEvaluation.swift",
    "ButtonHeist/Sources/TheInsideJob/TheBrains/PredicateWait+Reducer.swift",
    "ButtonHeist/Sources/TheInsideJob/TheBrains/TheBrains+RepeatUntilPredicateEvaluation.swift",
    "ButtonHeist/Sources/TheInsideJob/TheBrains/TheBrains+RepeatUntilState.swift",
]

// Effect and effect-handle symbols blocked from pure pipeline files:
// - Task, DispatchQueue, ContinuousClock, and Date reach into scheduling or time.
// - NotificationCenter reaches into ambient process-wide event streams.
// - NWConnection, NWListener, and URLSession reach into external I/O.
// UIKit live-object mutation is enforced by keeping the checked files effect-free;
// runtime boundary files are still allowed to use UIKit where actions are performed.
private let purePipelineEffectSymbols: Set<String> = [
    "ContinuousClock",
    "Date",
    "DispatchQueue",
    "NWConnection",
    "NWListener",
    "NotificationCenter",
    "Task",
    "URLSession",
]

private let demoAccessibilityIdentifierAllowedPaths: Set<String> = [
    "TestApp/Sources/ScrollSPIHarnessView.swift",
    "TestApp/Sources/TraitProbeView.swift",
    "TestApp/Sources/TraitValidationView.swift",
]

private func isExported(_ modifiers: DeclModifierListSyntax) -> Bool {
    let names = Set(modifiers.map(\.name.text))
    return !names.isDisjoint(with: ["open", "public", "package"])
}

private func isEffectivelyExported(
    _ node: some SyntaxProtocol,
    modifiers: DeclModifierListSyntax
) -> Bool {
    if isExported(modifiers) { return true }

    var ancestor = Syntax(node).parent
    while let current = ancestor {
        if current.is(CodeBlockSyntax.self) { return false }
        if let declaration = current.as(ExtensionDeclSyntax.self) {
            return isExported(declaration.modifiers)
        }
        if let declaration = current.as(ProtocolDeclSyntax.self) {
            return isExported(declaration.modifiers)
        }
        ancestor = current.parent
    }
    return false
}

private func isPrivate(_ modifiers: DeclModifierListSyntax) -> Bool {
    let names = Set(modifiers.map(\.name.text))
    return !names.isDisjoint(with: ["private", "fileprivate"])
}

private func hasExplicitAccess(_ modifiers: DeclModifierListSyntax) -> Bool {
    let names = Set(modifiers.map(\.name.text))
    return !names.isDisjoint(with: ["open", "public", "package", "internal", "private", "fileprivate"])
}

private func hasDeprecatedAttribute(_ attributes: AttributeListSyntax) -> Bool {
    attributes.contains { element in
        guard let attribute = element.as(AttributeSyntax.self) else {
            return false
        }
        return attribute.attributeName.trimmedDescription == "available"
            && attribute.trimmedDescription.contains("deprecated")
    }
}

private func isTopLevel(_ node: some SyntaxProtocol) -> Bool {
    var ancestor = Syntax(node).parent
    while let current = ancestor {
        if current.is(MemberBlockItemSyntax.self) || current.is(CodeBlockSyntax.self) {
            return false
        }
        if current.is(SourceFileSyntax.self) {
            return true
        }
        ancestor = current.parent
    }
    return false
}

private func enclosingFunctionName(of node: some SyntaxProtocol) -> String? {
    var ancestor = Syntax(node).parent
    while let current = ancestor {
        if let function = current.as(FunctionDeclSyntax.self) {
            return function.name.text
        }
        ancestor = current.parent
    }
    return nil
}

private func enclosingNominalType(of node: some SyntaxProtocol) -> String? {
    var ancestor = Syntax(node).parent
    while let current = ancestor {
        if let declaration = current.as(StructDeclSyntax.self) {
            return declaration.name.text
        }
        if let declaration = current.as(EnumDeclSyntax.self) {
            return declaration.name.text
        }
        if let declaration = current.as(ClassDeclSyntax.self) {
            return declaration.name.text
        }
        if let declaration = current.as(ActorDeclSyntax.self) {
            return declaration.name.text
        }
        ancestor = current.parent
    }
    return nil
}

private func enclosingExtensionType(of node: some SyntaxProtocol) -> String? {
    var ancestor = Syntax(node).parent
    while let current = ancestor {
        if current.is(CodeBlockSyntax.self) { return nil }
        if let declaration = current.as(ExtensionDeclSyntax.self) {
            return declaration.extendedType.trimmedDescription
        }
        ancestor = current.parent
    }
    return nil
}

private func enumCaseNames(in declaration: EnumDeclSyntax) -> Set<String> {
    Set(declaration.memberBlock.members.flatMap { member in
        member.decl.as(EnumCaseDeclSyntax.self)?.elements.map(\.name.text) ?? []
    })
}

private func isTopLevelOrFirstLevelMember(_ node: some SyntaxProtocol) -> Bool {
    var memberDepth = 0
    var ancestor = Syntax(node).parent
    while let current = ancestor {
        if current.is(CodeBlockSyntax.self) {
            return false
        }
        if current.is(MemberBlockItemSyntax.self) {
            memberDepth += 1
            if memberDepth > 1 {
                return false
            }
        }
        if current.is(SourceFileSyntax.self) {
            return true
        }
        ancestor = current.parent
    }
    return false
}

private func hasProtocolAncestor(_ node: some SyntaxProtocol) -> Bool {
    var ancestor = Syntax(node).parent
    while let current = ancestor {
        if current.is(ProtocolDeclSyntax.self) {
            return true
        }
        ancestor = current.parent
    }
    return false
}

private func hasAccessQualifiedExtensionAncestor(_ node: some SyntaxProtocol) -> Bool {
    var ancestor = Syntax(node).parent
    while let current = ancestor {
        if let extensionDecl = current.as(ExtensionDeclSyntax.self),
           hasExplicitAccess(extensionDecl.modifiers) {
            return true
        }
        ancestor = current.parent
    }
    return false
}

private func isButtonHeistDSLFacade(_ path: RelativeFilePath) -> Bool {
    path.rawValue == "ButtonHeist/Sources/ButtonHeistDSL/ButtonHeistDSL.swift"
}

private func isCompatibilityName(_ name: String) -> Bool {
    let lowercased = name.lowercased()
    if lowercased.hasPrefix("legacy")
        || lowercased.hasPrefix("compatibility")
        || lowercased.hasPrefix("deprecated") {
        return true
    }
    if lowercased.hasPrefix("compat") && !lowercased.hasPrefix("compatible") {
        return true
    }
    if name.contains("Legacy")
        || name.contains("Compatibility")
        || name.contains("Deprecated") {
        return true
    }
    return name.contains("Compat") && !name.contains("Compatible")
}

private func isForbiddenInsideJobArchitectureSymbol(_ observed: String) -> Bool {
    if forbiddenInsideJobArchitectureSymbols.contains(observed) { return true }
    let lowercased = observed.lowercased()
    return lowercased.contains("reveal")
        && (lowercased.contains("grace") || lowercased.contains("silentreparse"))
}

private func isRawCommandArgumentType(_ type: TypeSyntax) -> Bool {
    let compact = type.trimmedDescription.filter { !$0.isWhitespace }
    return compact.contains("CommandArgumentEnvelope")
        || compact.contains("[String:HeistValue]")
        || compact.contains("Dictionary<String,HeistValue>")
}

private func unwrappedOptionalTypeName(_ type: TypeSyntax) -> String {
    type.trimmedDescription.trimmingCharacters(in: CharacterSet(charactersIn: "?!"))
}

private func isTupleType(_ type: TypeSyntax) -> Bool {
    if let tuple = type.as(TupleTypeSyntax.self) {
        return tuple.elements.count > 1
    }
    if let optional = type.as(OptionalTypeSyntax.self) {
        return isTupleType(optional.wrappedType)
    }
    if let attributed = type.as(AttributedTypeSyntax.self) {
        return isTupleType(attributed.baseType)
    }
    return false
}
