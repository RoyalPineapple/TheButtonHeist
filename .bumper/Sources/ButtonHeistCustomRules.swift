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
        return .skipChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
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
        recordExplicitAccess(node: node, modifiers: node.modifiers, name: node.name.text)
        return .visitChildren
    }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
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
        return .visitChildren
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
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
        guard forbiddenInsideJobArchitectureSymbols.contains(observed) else { return }
        recordFailure(
            at: node,
            observed: observed,
            expectation: """
            reveal retries await settled visible observations, refresh live \
            capture, and resolve before the action deadline
            """
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
]

private let anyBoundaryAllowedPaths: Set<String> = [
    "ButtonHeist/Sources/TheButtonHeist/Storage/PrivateStorage.swift",
    "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandArguments.swift",
    "ButtonHeist/Sources/TheInsideJob/Lifecycle/StartupConfiguration.swift",
]

private let insideJobSourcePrefix = "ButtonHeist/Sources/TheInsideJob/"

private let forbiddenInsideJobArchitectureSymbols: Set<String> = [
    "RevealPathGraceMachine",
    "refreshCurrentVisibleTree",
    "refreshTreeAfterViewportMove",
    "revealPathGraceTimeout",
    "revealPathSilentReparseInterval",
]

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

private func isTupleType(_ type: some TypeSyntaxProtocol) -> Bool {
    isTupleTypeDescription(type.trimmedDescription)
}

private func isTupleTypeDescription(_ rawText: String) -> Bool {
    let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    let characters = Array(text)
    guard characters.first == "(" else {
        return false
    }

    guard let closeIndex = matchingCloseParenIndex(in: characters, openIndex: 0) else {
        return false
    }

    let suffix = String(characters[(closeIndex + 1)...])
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if suffix.hasPrefix("->") {
        return false
    }

    let content = Array(characters[1..<closeIndex])
    var depth = 0
    var hasComma = false
    var hasColon = false
    var hasTopLevelArrow = false
    var index = 0

    while index < content.count {
        let character = content[index]
        if "([{".contains(character) {
            depth += 1
        } else if ")]}".contains(character) {
            depth = max(0, depth - 1)
        } else if depth == 0 {
            if character == "," {
                hasComma = true
            } else if character == ":" {
                hasColon = true
            } else if character == "-", index + 1 < content.count, content[index + 1] == ">" {
                hasTopLevelArrow = true
                index += 1
            }
        }
        index += 1
    }

    return (hasComma || hasColon) && !hasTopLevelArrow
}

private func matchingCloseParenIndex(in characters: [Character], openIndex: Int) -> Int? {
    var depth = 0
    for index in openIndex..<characters.count {
        if characters[index] == "(" {
            depth += 1
        } else if characters[index] == ")" {
            depth -= 1
            if depth == 0 {
                return index
            }
        }
    }
    return nil
}
