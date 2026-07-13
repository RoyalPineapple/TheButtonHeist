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
        recordTupleResult(
            node: node,
            modifiers: node.modifiers,
            returnType: node.signature.returnClause?.type,
            declaration: "function \(node.name.text)"
        )
        recordTupleParameters(
            node: node,
            modifiers: node.modifiers,
            parameters: node.signature.parameterClause.parameters,
            declaration: "function \(node.name.text)"
        )
        recordExplicitAccess(node: node, modifiers: node.modifiers, name: node.name.text)
        return .visitChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        recordRetiredParameterLabels(node.signature.parameterClause.parameters)
        recordLooseObservationInitializer(node)
        recordTupleParameters(
            node: node,
            modifiers: node.modifiers,
            parameters: node.signature.parameterClause.parameters,
            declaration: "initializer of \(enclosingNominalType(of: node) ?? "unknown type")"
        )
        return .visitChildren
    }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        recordRetiredParameterLabels(node.parameterClause.parameters)
        recordTupleResult(
            node: node,
            modifiers: node.modifiers,
            returnType: node.returnClause.type,
            declaration: "subscript"
        )
        recordTupleParameters(
            node: node,
            modifiers: node.modifiers,
            parameters: node.parameterClause.parameters,
            declaration: "subscript"
        )
        return .visitChildren
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        recordAccessibilityTargetAlias(node)
        recordExportedTupleTypealias(node)
        recordCompatibilitySurface(
            node: node,
            modifiers: node.modifiers,
            attributes: node.attributes,
            name: node.name.text
        )
        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        recordRetiredVariableSymbols(node)
        recordSiblingReceiptWarnings(node)
        recordVariableCompatibilitySurface(node)
        recordUnannotatedCallback(node)
        recordTupleProperties(node)
        recordSettledValueLiveStorage(node)
        return .visitChildren
    }

    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        recordAnyBoundaryUse(node)
        recordRawHeistValueDictionary(node)
        recordJSONBoundaryUse(node, observed: node.name.text)
        return .visitChildren
    }

    override func visit(_ node: DictionaryTypeSyntax) -> SyntaxVisitorContinueKind {
        recordRawHeistValueDictionary(node)
        return .visitChildren
    }

    override func visit(_ node: AttributedTypeSyntax) -> SyntaxVisitorContinueKind {
        recordUncheckedSendableUse(node)
        return .visitChildren
    }

    override func visit(_ node: AttributeSyntax) -> SyntaxVisitorContinueKind {
        recordPreconcurrencyUse(node)
        return .visitChildren
    }

    override func visit(_ node: DeclModifierSyntax) -> SyntaxVisitorContinueKind {
        recordUnsafeNonisolatedUse(node)
        return .visitChildren
    }

    override func visit(_ token: TokenSyntax) -> SyntaxVisitorContinueKind {
        recordSuppressionDirectives(token)
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
        recordSettledValueLiveStorage(node)
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
        guard node.calledExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text == "decodeIfPresent",
              let decodedType = node.arguments.first?.expression,
              isMetatypeReference(decodedType, named: "ActionSettlementEvidence") else {
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
        guard isEffectivelyExported(node, modifiers: modifiers) else {
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
        guard isEffectivelyExported(node, modifiers: node.modifiers) else {
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

    private func recordAccessibilityTargetAlias(_ node: TypeAliasDeclSyntax) {
        guard isNamedType(node.initializer.value, "AccessibilityTarget"),
              !(isButtonHeistDSLFacade(file.path) && node.name.text == "AccessibilityTarget") else {
            return
        }

        failures.append(
            file.failure(
                at: node,
                message: "alternate AccessibilityTarget typealias",
                evidence: ViolationEvidence(
                    observed: "\(node.name.text) = \(node.initializer.value.trimmedDescription)",
                    expectation: "AccessibilityTarget is the canonical target spelling"
                )
            )
        )
    }

    private func recordUnannotatedCallback(_ node: VariableDeclSyntax) {
        guard isFileOrTypeMember(node) else { return }

        for binding in node.bindings {
            guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                  isCallbackName(identifier.identifier.text),
                  let type = binding.typeAnnotation?.type,
                  containsFunctionType(type),
                  !hasCallbackIsolationAnnotation(type) else {
                continue
            }

            failures.append(
                file.failure(
                    at: type,
                    message: "callback without isolation annotation",
                    evidence: ViolationEvidence(
                        observed: "\(identifier.identifier.text): \(type.trimmedDescription)",
                        expectation: "onFoo callbacks declare a global actor or @Sendable in the closure type"
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

    private func recordTupleResult(
        node: some SyntaxProtocol,
        modifiers: DeclModifierListSyntax,
        returnType: TypeSyntax?,
        declaration: String
    ) {
        guard isCrossFileVisible(node, modifiers: modifiers),
              let returnType,
              isTupleType(returnType) else {
            return
        }

        let visibility = isEffectivelyExported(node, modifiers: modifiers)
            ? "exported"
            : "cross-file"
        failures.append(
            file.failure(
                at: returnType,
                message: "\(visibility) tuple result in \(declaration)",
                evidence: ViolationEvidence(
                    observed: "\(declaration): \(returnType.trimmedDescription)",
                    expectation: "function and subscript results use named Swift types"
                )
            )
        )
    }

    private func recordTupleParameters(
        node: some SyntaxProtocol,
        modifiers: DeclModifierListSyntax,
        parameters: FunctionParameterListSyntax,
        declaration: String
    ) {
        guard isCrossFileVisible(node, modifiers: modifiers) else { return }

        for parameter in parameters where isTupleType(parameter.type) {
            let label = parameter.secondName?.text ?? parameter.firstName.text
            failures.append(
                file.failure(
                    at: parameter.type,
                    message: "tuple parameter \(label) in \(declaration)",
                    evidence: ViolationEvidence(
                        observed: "\(declaration).\(label): \(parameter.type.trimmedDescription)",
                        expectation: "cross-file parameters use named Swift types"
                    )
                )
            )
        }
    }

    private func recordExportedTupleTypealias(_ node: TypeAliasDeclSyntax) {
        let type = node.initializer.value
        guard !isButtonHeistDSLFacade(file.path),
              node.genericParameterClause == nil,
              !hasExtensionAncestor(node),
              isCrossFileVisible(node, modifiers: node.modifiers),
              isTupleType(type) else {
            return
        }

        failures.append(
            file.failure(
                at: type,
                message: "tuple typealias \(node.name.text) in cross-file API",
                evidence: ViolationEvidence(
                    observed: "\(node.name.text) = \(type.trimmedDescription)",
                    expectation: "cross-file tuple shapes use named Swift structs"
                )
            )
        )
    }

    private func recordTupleProperties(_ node: VariableDeclSyntax) {
        guard isFileOrTypeMember(node) else { return }
        for binding in node.bindings {
            let name = binding.pattern.trimmedDescription
            let isStored = isStoredBinding(binding)
            let crossesFiles = isCrossFileVisible(node, modifiers: node.modifiers)
            guard isStored || crossesFiles else { continue }

            if let type = binding.typeAnnotation?.type, isTupleType(type) {
                recordTupleProperty(name: name, shape: type, isStored: isStored)
                continue
            }
            guard isStored,
                  let tuple = binding.initializer?.value.as(TupleExprSyntax.self),
                  tuple.elements.count > 1 else {
                continue
            }
            recordTupleProperty(name: name, shape: tuple, isStored: true)
        }
    }

    private func recordTupleProperty(
        name: String,
        shape: some SyntaxProtocol,
        isStored: Bool
    ) {
        let reason = isStored ? "stored" : "cross-file computed"
        failures.append(
            file.failure(
                at: shape,
                message: "\(reason) tuple property \(name)",
                evidence: ViolationEvidence(
                    observed: "\(name): \(shape.trimmedDescription)",
                    expectation: "stored and cross-file properties use named Swift types"
                )
            )
        )
    }

    private func recordLooseObservationInitializer(_ node: InitializerDeclSyntax) {
        guard let owner = enclosingNominalType(of: node),
              canonicalBuilderOwnedTypes.contains(owner),
              !hasModifier("private", in: node.modifiers) else {
            return
        }

        failures.append(
            file.failure(
                at: node,
                message: "loose \(owner) initializer",
                evidence: ViolationEvidence(
                    observed: node.signature.trimmedDescription,
                    expectation: "\(owner) initializers are private; production construction uses \(owner).build"
                )
            )
        )
    }

    private func recordAnyBoundaryUse(_ node: IdentifierTypeSyntax) {
        guard node.name.text == "Any",
              !isAllowedAnyBoundaryUse(node, path: filePath) else {
            return
        }

        failures.append(
            file.failure(
                at: node,
                message: "Any in \(enclosingDeclarationDescription(of: node))",
                evidence: ViolationEvidence(
                    observed: node.trimmedDescription,
                    expectation: "normalize Foundation/Objective-C Any values in the immediate boundary declaration"
                )
            )
        )
    }

    private func recordUncheckedSendableUse(_ node: AttributedTypeSyntax) {
        guard node.baseType.as(IdentifierTypeSyntax.self)?.name.text == "Sendable",
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
                message: "production @unchecked Sendable escape hatch",
                evidence: ViolationEvidence(
                    observed: "\(enclosingDeclarationDescription(of: node)): \(node.trimmedDescription)",
                    expectation: "production declarations satisfy Sendable through checked isolation and value ownership"
                )
            )
        )
    }

    private func recordPreconcurrencyUse(_ node: AttributeSyntax) {
        guard node.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "preconcurrency" else { return }
        failures.append(
            file.failure(
                at: node,
                message: "production @preconcurrency escape hatch",
                evidence: ViolationEvidence(
                    observed: enclosingDeclarationDescription(of: node),
                    expectation: "production imports and conformances use checked concurrency"
                )
            )
        )
    }

    private func recordUnsafeNonisolatedUse(_ node: DeclModifierSyntax) {
        guard node.name.text == "nonisolated",
              node.tokens(viewMode: .sourceAccurate).contains(where: { $0.text == "unsafe" }),
              !isAllowedUnsafeNonisolated(node, path: filePath) else {
            return
        }
        failures.append(
            file.failure(
                at: node,
                message: "production nonisolated(unsafe) escape hatch",
                evidence: ViolationEvidence(
                    observed: enclosingDeclarationDescription(of: node),
                    expectation: "unsafe nonisolated storage is confined to the documented IOHID SPI loader"
                )
            )
        )
    }

    private func recordSuppressionDirectives(_ token: TokenSyntax) {
        let trivia = token.leadingTrivia.description + token.trailingTrivia.description
        let directives = trivia
            .split(whereSeparator: { $0.isNewline })
            .map(String.init)
            .filter(isLintSuppressionDirective)

        for directive in directives where !isAllowedSPISuppression(
            directive,
            path: filePath,
            declaration: enclosingDeclarationDescription(of: token)
        ) {
            failures.append(
                file.failure(
                    at: token,
                    message: "production warning/lint suppression escape hatch",
                    evidence: ViolationEvidence(
                        observed: directive.trimmingCharacters(in: .whitespaces),
                        expectation: "fix the diagnostic instead of suppressing it"
                    )
                )
            )
        }
    }

    private func recordRawHeistValueDictionary(_ node: DictionaryTypeSyntax) {
        guard isNamedType(node.key, "String"),
              isNamedType(node.value, "HeistValue") else {
            return
        }
        recordRawHeistValueDictionary(at: node)
    }

    private func recordRawHeistValueDictionary(_ node: IdentifierTypeSyntax) {
        guard node.name.text == "Dictionary",
              let arguments = node.genericArgumentClause?.arguments,
              arguments.count == 2,
              let key = arguments.first?.argument,
              let value = arguments.last?.argument,
              isNamedType(key, "String"),
              isNamedType(value, "HeistValue") else {
            return
        }
        recordRawHeistValueDictionary(at: node)
    }

    private func recordRawHeistValueDictionary(at node: some SyntaxProtocol) {
        guard !isAllowedRawHeistValueDictionary(node, path: filePath) else { return }
        failures.append(
            file.failure(
                at: node,
                message: "raw [String: HeistValue] in \(enclosingDeclarationDescription(of: node))",
                evidence: ViolationEvidence(
                    observed: node.trimmedDescription,
                    expectation: "raw command objects exist only at HeistValue decoding and CommandArgumentEnvelope admission"
                )
            )
        )
    }

    private func recordSettledValueLiveStorage(_ node: VariableDeclSyntax) {
        guard isSettledValueStorageOwner(node) else { return }

        for binding in node.bindings {
            guard isStoredBinding(binding) else { continue }
            let name = binding.pattern.trimmedDescription
            if let type = binding.typeAnnotation?.type,
               let liveType = forbiddenLiveStorageType(in: type) {
                recordSettledValueLiveStorage(name: name, shape: type, liveType: liveType)
                continue
            }
            guard let initializer = binding.initializer?.value.as(FunctionCallExprSyntax.self),
                  let liveType = calledConstructorName(initializer.calledExpression),
                  isForbiddenLiveStorageName(liveType) else {
                continue
            }
            recordSettledValueLiveStorage(name: name, shape: initializer, liveType: liveType)
        }
    }

    private func recordSettledValueLiveStorage(
        name: String,
        shape: some SyntaxProtocol,
        liveType: String
    ) {
        failures.append(
            file.failure(
                at: shape,
                message: "settled value property \(name) retains live UIKit evidence",
                evidence: ViolationEvidence(
                    observed: "\(name): \(shape.trimmedDescription) via \(liveType)",
                    expectation: "settled values retain semantic value data; live UIKit references stay in LiveCapture"
                )
            )
        )
    }

    private func recordSettledValueLiveStorage(_ node: EnumCaseDeclSyntax) {
        guard isSettledValueStorageOwner(node) else { return }

        for element in node.elements {
            guard let parameters = element.parameterClause?.parameters else { continue }
            for parameter in parameters {
                guard let liveType = forbiddenLiveStorageType(in: parameter.type) else { continue }
                failures.append(
                    file.failure(
                        at: parameter.type,
                        message: "settled value case \(element.name.text) retains live UIKit evidence",
                        evidence: ViolationEvidence(
                            observed: "\(element.name.text): \(parameter.type.trimmedDescription) via \(liveType)",
                            expectation: "settled enum cases retain semantic values; live UIKit references stay in LiveCapture"
                        )
                    )
                )
            }
        }
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
              let calledSymbol = calledConstructorName(node.calledExpression),
              let symbol = calledSymbol == "Self" ? enclosingNominalType(of: node) : calledSymbol,
              let ownership = pipelineConstructionOwnership[symbol],
              !isAllowedPipelineConstruction(symbol: symbol, ownership: ownership, call: node) else {
            return
        }

        failures.append(
            file.failure(
                at: node.calledExpression,
                message: "pipeline value constructed outside its canonical owner",
                evidence: ViolationEvidence(
                    observed: "\(ownership.symbol) in \(enclosingDeclarationDescription(of: node))",
                    expectation: ownership.expectation
                )
            )
        )
    }

    private func isAllowedPipelineConstruction(
        symbol: String,
        ownership: PipelineConstructionOwnership,
        call: FunctionCallExprSyntax
    ) -> Bool {
        guard ownership.allowedPaths.contains(filePath) else { return false }
        guard canonicalBuilderOwnedTypes.contains(symbol) else { return true }
        return enclosingFunctionName(of: call) == "build"
            && enclosingNominalType(of: call) == symbol
    }

    private func recordRawNotificationNormalization(_ node: FunctionCallExprSyntax) {
        guard filePath.hasPrefix("ButtonHeist/Sources/"),
              calledConstructorName(node.calledExpression) == "AccessibilityNotificationKind",
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
        guard isMemberCall(node, named: "testing", on: "InterfaceObservationProof"),
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
              let firstTypeName = typeNameUnwrappingOptional(firstType),
              rawSemanticCommitTypes.contains(firstTypeName) else {
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

private let privateStorageBoundaryPath =
    "ButtonHeist/Sources/TheButtonHeist/Storage/PrivateStorage.swift"

private let commandArgumentBoundaryPath =
    "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandArguments.swift"

private let startupConfigurationBoundaryPath =
    "ButtonHeist/Sources/TheInsideJob/Lifecycle/StartupConfiguration.swift"

private let heistValueBoundaryPath =
    "ButtonHeist/Sources/TheScore/Wire/HeistValue.swift"

private let unsafeNonisolatedSPIBoundaryPath =
    "ButtonHeist/Sources/TheInsideJob/TheSafecracker/TheSafecracker+IOHIDEventBuilder.swift"

private let allowedUnsafeNonisolatedSPIVariables: Set<String> = [
    "_IOHIDEventAppendEvent",
    "_IOHIDEventCreateDigitizerEvent",
    "_IOHIDEventCreateDigitizerFingerEventWithQuality",
    "_IOHIDEventSetFloatValue",
    "ioHIDFunctionsLoaded",
]

private let allowedSPISwiftLintDeclarations: [String: Set<String>] = [
    "agent_main_actor_value_type": ["struct TouchEvent"],
    "function_parameter_count": [
        "function IOHIDEventCreateDigitizerEvent",
        "function IOHIDEventCreateDigitizerFingerEventWithQuality",
    ],
]

private let canonicalBuilderOwnedTypes: Set<String> = [
    "InterfaceObservation",
    "LiveCapture",
]

private let settledValueOwnerNames: Set<String> = [
    "InterfaceTree",
    "ObservationWindow",
]

private let explicitLiveStorageTypeNames: Set<String> = [
    "CALayer",
    "ContainerRef",
    "DispatchReferences",
    "ElementRef",
    "InterfaceObservation",
    "LiveCapture",
    "LiveElementEntry",
    "LiveElementIndex",
    "LiveElementTable",
    "NSObject",
    "ScrollableViewRef",
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

private func isCrossFileVisible(
    _ node: some SyntaxProtocol,
    modifiers: DeclModifierListSyntax
) -> Bool {
    guard !isPrivate(modifiers) else { return false }

    var ancestor = Syntax(node).parent
    while let current = ancestor {
        if current.is(CodeBlockSyntax.self) { return false }
        if let declaration = current.as(StructDeclSyntax.self), isPrivate(declaration.modifiers) {
            return false
        }
        if let declaration = current.as(EnumDeclSyntax.self), isPrivate(declaration.modifiers) {
            return false
        }
        if let declaration = current.as(ClassDeclSyntax.self), isPrivate(declaration.modifiers) {
            return false
        }
        if let declaration = current.as(ActorDeclSyntax.self), isPrivate(declaration.modifiers) {
            return false
        }
        if let declaration = current.as(ProtocolDeclSyntax.self), isPrivate(declaration.modifiers) {
            return false
        }
        if let declaration = current.as(ExtensionDeclSyntax.self), isPrivate(declaration.modifiers) {
            return false
        }
        if current.is(SourceFileSyntax.self) { return true }
        ancestor = current.parent
    }
    return false
}

private func isPrivate(_ modifiers: DeclModifierListSyntax) -> Bool {
    let names = Set(modifiers.map(\.name.text))
    return !names.isDisjoint(with: ["private", "fileprivate"])
}

private func hasModifier(_ name: String, in modifiers: DeclModifierListSyntax) -> Bool {
    modifiers.contains { $0.name.text == name }
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
        return attribute.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "available"
            && attribute.tokens(viewMode: .sourceAccurate).contains { $0.text == "deprecated" }
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

private func isFileOrTypeMember(_ node: some SyntaxProtocol) -> Bool {
    var ancestor = Syntax(node).parent
    while let current = ancestor {
        if current.is(CodeBlockSyntax.self) { return false }
        if current.is(SourceFileSyntax.self) { return true }
        ancestor = current.parent
    }
    return false
}

private func hasExtensionAncestor(_ node: some SyntaxProtocol) -> Bool {
    var ancestor = Syntax(node).parent
    while let current = ancestor {
        if current.is(CodeBlockSyntax.self) { return false }
        if current.is(ExtensionDeclSyntax.self) { return true }
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

private func enclosingTypeAliasName(of node: some SyntaxProtocol) -> String? {
    var ancestor = Syntax(node).parent
    while let current = ancestor {
        if let typealiasDecl = current.as(TypeAliasDeclSyntax.self) {
            return typealiasDecl.name.text
        }
        ancestor = current.parent
    }
    return nil
}

private func enclosingVariableNames(of node: some SyntaxProtocol) -> Set<String>? {
    var ancestor = Syntax(node).parent
    while let current = ancestor {
        if let variable = current.as(VariableDeclSyntax.self) {
            return Set(variable.bindings.map { $0.pattern.trimmedDescription })
        }
        ancestor = current.parent
    }
    return nil
}

private func enclosingDeclarationDescription(of node: some SyntaxProtocol) -> String {
    var ancestor = Syntax(node).parent
    while let current = ancestor {
        if let function = current.as(FunctionDeclSyntax.self) {
            return "function \(function.name.text)"
        }
        if current.is(InitializerDeclSyntax.self) {
            return "initializer of \(enclosingNominalType(of: current) ?? "unknown type")"
        }
        if let typealiasDecl = current.as(TypeAliasDeclSyntax.self) {
            return "typealias \(typealiasDecl.name.text)"
        }
        if let variable = current.as(VariableDeclSyntax.self) {
            let names = variable.bindings.map { $0.pattern.trimmedDescription }.joined(separator: ", ")
            return "property \(names)"
        }
        if let nominal = current.as(StructDeclSyntax.self) {
            return "struct \(nominal.name.text)"
        }
        if let nominal = current.as(EnumDeclSyntax.self) {
            return "enum \(nominal.name.text)"
        }
        if let nominal = current.as(ClassDeclSyntax.self) {
            return "class \(nominal.name.text)"
        }
        if let nominal = current.as(ActorDeclSyntax.self) {
            return "actor \(nominal.name.text)"
        }
        ancestor = current.parent
    }
    return "file scope"
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

private func enclosingNominalTypes(of node: some SyntaxProtocol) -> [String] {
    var names: [String] = []
    var ancestor = Syntax(node).parent
    while let current = ancestor {
        if let declaration = current.as(StructDeclSyntax.self) {
            names.append(declaration.name.text)
        } else if let declaration = current.as(EnumDeclSyntax.self) {
            names.append(declaration.name.text)
        } else if let declaration = current.as(ClassDeclSyntax.self) {
            names.append(declaration.name.text)
        } else if let declaration = current.as(ActorDeclSyntax.self) {
            names.append(declaration.name.text)
        }
        ancestor = current.parent
    }
    return names
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

private func isCallbackName(_ name: String) -> Bool {
    guard name.hasPrefix("on") else { return false }
    return name.dropFirst(2).first?.isUppercase == true
}

private func containsFunctionType(_ type: TypeSyntax) -> Bool {
    if type.is(FunctionTypeSyntax.self) { return true }
    if let optional = type.as(OptionalTypeSyntax.self) {
        return containsFunctionType(optional.wrappedType)
    }
    if let attributed = type.as(AttributedTypeSyntax.self) {
        return containsFunctionType(attributed.baseType)
    }
    if let tuple = type.as(TupleTypeSyntax.self), tuple.elements.count == 1,
       let element = tuple.elements.first {
        return containsFunctionType(element.type)
    }
    return false
}

private func hasCallbackIsolationAnnotation(_ type: TypeSyntax) -> Bool {
    if let function = type.as(FunctionTypeSyntax.self) {
        return hasCallbackIsolationAnnotation(function.attributes)
    }
    if let optional = type.as(OptionalTypeSyntax.self) {
        return hasCallbackIsolationAnnotation(optional.wrappedType)
    }
    if let attributed = type.as(AttributedTypeSyntax.self) {
        return hasCallbackIsolationAnnotation(attributed.attributes)
            || hasCallbackIsolationAnnotation(attributed.baseType)
    }
    if let tuple = type.as(TupleTypeSyntax.self), tuple.elements.count == 1,
       let element = tuple.elements.first {
        return hasCallbackIsolationAnnotation(element.type)
    }
    return false
}

private func hasCallbackIsolationAnnotation(_ attributes: AttributeListSyntax) -> Bool {
    attributes.contains { element in
        guard let attribute = element.as(AttributeSyntax.self) else { return false }
        let name = attribute.attributeName.trimmedDescription
        return name == "Sendable" || name.hasSuffix("Actor")
    }
}

private func isAllowedAnyBoundaryUse(_ node: IdentifierTypeSyntax, path: String) -> Bool {
    switch path {
    case privateStorageBoundaryPath:
        return enclosingTypeAliasName(of: node) == "FoundationFileAttributeDictionary"
    case commandArgumentBoundaryPath:
        return enclosingFunctionName(of: node) == "expectedDescription"
    case startupConfigurationBoundaryPath:
        return enclosingFunctionName(of: node) == "value"
            && enclosingNominalType(of: node) == "FoundationInfoPlistBridge"
    default:
        return false
    }
}

private func isAllowedRawHeistValueDictionary(
    _ node: some SyntaxProtocol,
    path: String
) -> Bool {
    if path == heistValueBoundaryPath {
        return enclosingNominalType(of: node) == "HeistValue"
    }
    guard path == commandArgumentBoundaryPath else { return false }
    return enclosingNominalType(of: node) == "CommandArgumentEnvelope"
        || enclosingExtensionType(of: node) == "TheFence.CommandArgumentEnvelope"
}

private func isLintSuppressionDirective(_ line: String) -> Bool {
    let compact = line.lowercased().filter { !$0.isWhitespace }
    return compact.contains("swiftlint:disable")
        || compact.contains("swiftformat:disable")
        || compact.contains("nolint")
}

private func isAllowedUnsafeNonisolated(_ node: DeclModifierSyntax, path: String) -> Bool {
    guard path == unsafeNonisolatedSPIBoundaryPath else { return false }
    guard let names = enclosingVariableNames(of: node) else { return false }
    return !names.isEmpty && names.isSubset(of: allowedUnsafeNonisolatedSPIVariables)
}

private func isAllowedSPISuppression(
    _ directive: String,
    path: String,
    declaration: String
) -> Bool {
    guard path == unsafeNonisolatedSPIBoundaryPath else { return false }
    return allowedSPISwiftLintDeclarations.contains { rule, declarations in
        directive.contains(rule) && declarations.contains(declaration)
    }
}

private func isNamedType(_ type: TypeSyntax, _ expectedName: String) -> Bool {
    if let identifier = type.as(IdentifierTypeSyntax.self) {
        return identifier.name.text == expectedName
    }
    return type.as(MemberTypeSyntax.self)?.name.text == expectedName
}

private func isStoredBinding(_ binding: PatternBindingSyntax) -> Bool {
    guard let accessors = binding.accessorBlock else { return true }
    let tokens = Set(accessors.tokens(viewMode: .sourceAccurate).map(\.text))
    return tokens.contains("willSet") || tokens.contains("didSet")
}

private func isSettledValueStorageOwner(_ node: some SyntaxProtocol) -> Bool {
    let names = enclosingNominalTypes(of: node)
    if names.contains(where: { $0.hasPrefix("Settled") }) { return true }
    if !settledValueOwnerNames.isDisjoint(with: names) { return true }
    if names.first == "Snapshot", names.dropFirst().contains("LiveCapture") { return true }
    return names.first == "Outcome" && names.dropFirst().contains("SettleSession")
}

private func forbiddenLiveStorageType(in type: TypeSyntax) -> String? {
    let tokens = type.tokens(viewMode: .sourceAccurate).map(\.text)
    if tokens.indices.contains(where: { index in
        tokens[index] == "LiveCapture"
            && Array(tokens.dropFirst(index + 1).prefix(2)) != [".", "Snapshot"]
    }) {
        return "LiveCapture"
    }
    var names = Set(tokens)
    names.remove("LiveCapture")
    return names.sorted().first(where: isForbiddenLiveStorageName)
}

private func isForbiddenLiveStorageName(_ name: String) -> Bool {
    explicitLiveStorageTypeNames.contains(name)
        || (name.hasPrefix("UI") && !name.hasPrefix("UInt"))
}

private func calledConstructorName(_ expression: ExprSyntax) -> String? {
    if let reference = expression.as(DeclReferenceExprSyntax.self) {
        return reference.baseName.text
    }
    guard let member = expression.as(MemberAccessExprSyntax.self) else { return nil }
    if member.declName.baseName.text != "init" {
        return member.declName.baseName.text
    }
    guard let base = member.base else { return "Self" }
    return calledConstructorName(base)
}

private func isMetatypeReference(_ expression: ExprSyntax, named expectedName: String) -> Bool {
    guard let member = expression.as(MemberAccessExprSyntax.self),
          member.declName.baseName.text == "self",
          let base = member.base else {
        return false
    }
    return calledConstructorName(base) == expectedName
}

private func isMemberCall(
    _ call: FunctionCallExprSyntax,
    named memberName: String,
    on ownerName: String
) -> Bool {
    guard let member = call.calledExpression.as(MemberAccessExprSyntax.self),
          member.declName.baseName.text == memberName else {
        return false
    }
    guard let base = member.base else { return true }
    return calledConstructorName(base) == ownerName
}

private func isForbiddenInsideJobArchitectureSymbol(_ observed: String) -> Bool {
    if forbiddenInsideJobArchitectureSymbols.contains(observed) { return true }
    let lowercased = observed.lowercased()
    return lowercased.contains("reveal")
        && (lowercased.contains("grace") || lowercased.contains("silentreparse"))
}

private func isRawCommandArgumentType(_ type: TypeSyntax) -> Bool {
    type.tokens(viewMode: .sourceAccurate).contains { $0.text == "CommandArgumentEnvelope" }
}

private func typeNameUnwrappingOptional(_ type: TypeSyntax) -> String? {
    if let optional = type.as(OptionalTypeSyntax.self) {
        return typeNameUnwrappingOptional(optional.wrappedType)
    }
    if let identifier = type.as(IdentifierTypeSyntax.self) {
        return identifier.name.text
    }
    return type.as(MemberTypeSyntax.self)?.name.text
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
