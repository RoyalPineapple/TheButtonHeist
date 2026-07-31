import Foundation

public enum HeistCatalogRole: String, Codable, Sendable, Equatable {
    case entry
    case capability
}

public enum HeistTargetPredicateFact: Sendable, Equatable, Hashable {
    case predicate(ElementPredicate)
    case container(ContainerPredicate)
    case targetReference(HeistReferenceName)
}

public enum HeistCatalogIdentity: Sendable, Equatable, Hashable {
    case entry(HeistPlanName?)
    case capability(HeistDefinitionPath)

    public var role: HeistCatalogRole {
        switch self {
        case .entry: .entry
        case .capability: .capability
        }
    }

    public var displayName: String {
        switch self {
        case .entry(let name): name?.description ?? "entry"
        case .capability(let path): path.description
        }
    }

    package var lookupPath: HeistDefinitionPath? {
        switch self {
        case .entry(let name): name.map { HeistDefinitionPath(first: $0) }
        case .capability(let path): path
        }
    }
}

public struct HeistSemanticSurface: Sendable, Equatable {
    public let actionCommands: [HeistActionCommandType]
    public let targetPredicates: [HeistTargetPredicateFact]
    package let waits: [AccessibilityPredicate]
    package let expectations: [AccessibilityPredicate]
    public let nestedRunHeists: [HeistInvocationPath]
    public let semanticSurfaces: [ElementPredicateCheck]

    package init(
        actionCommands: [HeistActionCommandType] = [],
        targetPredicates: [HeistTargetPredicateFact] = [],
        waits: [AccessibilityPredicate] = [],
        expectations: [AccessibilityPredicate] = [],
        nestedRunHeists: [HeistInvocationPath] = [],
        semanticSurfaces: [ElementPredicateCheck] = []
    ) {
        self.actionCommands = actionCommands
        self.targetPredicates = targetPredicates
        self.waits = waits
        self.expectations = expectations
        self.nestedRunHeists = nestedRunHeists
        self.semanticSurfaces = semanticSurfaces
    }

    package var expectedEffects: [AccessibilityPredicate] {
        (waits + expectations).reduce(into: []) { effects, predicate in
            if !effects.contains(predicate) {
                effects.append(predicate)
            }
        }
    }
}

public struct HeistDescription: Sendable, Equatable {
    public let identity: HeistCatalogIdentity
    public var role: HeistCatalogRole { identity.role }
    public let parameterKind: HeistParameterKind
    public let parameterName: HeistReferenceName?
    public var requiresArgument: Bool { parameterKind.requiresArgument }
    public let semanticSurface: HeistSemanticSurface

    public init(
        identity: HeistCatalogIdentity,
        parameterKind: HeistParameterKind,
        parameterName: HeistReferenceName?,
        semanticSurface: HeistSemanticSurface
    ) {
        self.identity = identity
        self.parameterKind = parameterKind
        self.parameterName = parameterName
        self.semanticSurface = semanticSurface
    }
}

public struct HeistDescriptionLookupError: Error, Sendable, Equatable, CustomStringConvertible {
    public let requestedPath: HeistDefinitionPath
    public let availableIdentities: [HeistCatalogIdentity]

    public init(requestedPath: HeistDefinitionPath, availableIdentities: [HeistCatalogIdentity]) {
        self.requestedPath = requestedPath
        self.availableIdentities = availableIdentities
    }

    public var description: String {
        let available = availableIdentities.isEmpty
            ? "none"
            : availableIdentities.map(\.displayName).joined(separator: ", ")
        return "heist \"\(requestedPath)\" was not found. Available heists: \(available)"
    }
}

public struct HeistCatalogError: Error, Sendable, Equatable, CustomStringConvertible {
    public let duplicateIdentities: [HeistCatalogIdentity]

    public init(duplicateIdentities: [HeistCatalogIdentity]) {
        self.duplicateIdentities = duplicateIdentities
    }

    public var description: String {
        "heist catalog has duplicate names: \(duplicateIdentities.map(\.displayName).joined(separator: ", "))"
    }
}

public extension HeistPlan {
    func heistDescriptions() throws -> [HeistDescription] {
        var identities: [HeistCatalogIdentity] = []
        var descriptions: [HeistDescription] = []
        HeistPlanTraversal(expandsInvocations: false).walk(self) { event in
            let plan: HeistPlan
            let context: HeistTraversalContext
            let identity: HeistCatalogIdentity
            let definitionComponents: [HeistPlanName]
            switch event {
            case .enterPlan(let observedPlan, let observedContext):
                plan = observedPlan
                context = observedContext
                identity = .entry(plan.name)
                definitionComponents = []
            case .enterDefinition(let observedPlan, let observedContext):
                guard let name = observedPlan.name else {
                    preconditionFailure("admitted heist definitions must have names")
                }
                plan = observedPlan
                context = observedContext
                definitionComponents = context.definitionScope.pathPrefix + [name]
                guard let first = definitionComponents.first else {
                    preconditionFailure("definition catalog paths must not be empty")
                }
                identity = .capability(HeistDefinitionPath(first: first, remaining: Array(definitionComponents.dropFirst())))
            default:
                return
            }
            identities.append(identity)
            descriptions.append(HeistDescription(
                identity: identity,
                parameterKind: plan.parameter.kind,
                parameterName: plan.parameter.name,
                semanticSurface: semanticSurface(
                    plan: plan,
                    context: context,
                    definitionComponents: definitionComponents
                )
            ))
        }
        try validateUniqueCatalogPaths(identities)
        return descriptions
    }

    func describeHeist(at requestedPath: HeistDefinitionPath) throws -> HeistDescription {
        let descriptions = try heistDescriptions()
        guard let description = descriptions.first(where: { $0.identity.lookupPath == requestedPath }) else {
            throw HeistDescriptionLookupError(
                requestedPath: requestedPath,
                availableIdentities: descriptions.map(\.identity)
            )
        }
        return description
    }
}

private extension HeistPlan {
    func validateUniqueCatalogPaths(_ identities: [HeistCatalogIdentity]) throws {
        var seen = Set<HeistDefinitionPath>()
        var duplicateSet = Set<HeistCatalogIdentity>()
        var duplicates: [HeistCatalogIdentity] = []
        for identity in identities {
            guard let path = identity.lookupPath else { continue }
            if !seen.insert(path).inserted, duplicateSet.insert(identity).inserted {
                duplicates.append(identity)
            }
        }
        guard duplicates.isEmpty else {
            throw HeistCatalogError(duplicateIdentities: duplicates)
        }
    }

    func semanticSurface(
        plan: HeistPlan,
        context: HeistTraversalContext,
        definitionComponents: [HeistPlanName]
    ) -> HeistSemanticSurface {
        var actionCommands: [HeistActionCommandType] = [], actionCommandSet = Set<HeistActionCommandType>()
        var targetPredicates: [HeistTargetPredicateFact] = [], targetPredicateSet = Set<HeistTargetPredicateFact>()
        var waits: [AccessibilityPredicate] = [], waitIndexes = Set<Int>()
        var expectations: [AccessibilityPredicate] = [], expectationIndexes = Set<Int>()
        var nestedRunHeists: [HeistInvocationPath] = [], nestedRunHeistSet = Set<HeistInvocationPath>()
        var semanticFacets: [ElementPredicateCheck] = [], semanticFacetSet = Set<ElementPredicateCheck>()

        let definitionScope = HeistDefinitionScope(definitions: plan.definitions, pathPrefix: definitionComponents)
        HeistPlanTraversal().walk(
            steps: plan.body,
            path: .root.child(.body),
            depth: 1,
            referenceBindings: context.referenceBindings,
            definitionScope: definitionScope,
            rootDefinitionScope: context.rootDefinitionScope,
            invocationStack: definitionComponents.isEmpty ? [] : [HeistInvocationPath(namePath: definitionComponents)]
        ) { event in
            var observedTargets: [AccessibilityTarget] = []
            var observedPredicate: AccessibilityPredicate?
            var isWait = false
            switch event {
            case .action(let action, _):
                if actionCommandSet.insert(action.command.wireType).inserted { actionCommands.append(action.command.wireType) }
                observedTargets = action.command.targetOccurrences.map(\.target)
                observedPredicate = action.expectationPolicy.expectedExpectation?.predicate
            case .wait(let wait, let context):
                guard !context.path.ends(in: .expectation) else { return }
                observedPredicate = wait.predicate
                isWait = true
            case .forEachElement(let step, _):
                observedTargets = [.predicate(step.matching)]
            case .invoke(let invocation, let context):
                observedPredicate = invocation.expectation?.predicate
                if let resolved = context.resolveInvocation(path: invocation.path),
                   nestedRunHeistSet.insert(resolved.invocationPath).inserted {
                    nestedRunHeists.append(resolved.invocationPath)
                }
            default:
                return
            }
            if let predicate = observedPredicate {
                if isWait {
                    if waitIndexes.insert(waits.firstIndex(of: predicate) ?? waits.endIndex).inserted { waits.append(predicate) }
                } else {
                    if expectationIndexes.insert(expectations.firstIndex(of: predicate) ?? expectations.endIndex).inserted { expectations.append(predicate) }
                }
                switch predicate.core {
                case .presence(.exists(let target)), .presence(.missing(let target)):
                    observedTargets.append(target)
                // A screen boundary names no elements, so it observes no targets.
                case .screenChanged: break
                case .elementsChanged(let assertions):
                    for assertion in assertions {
                        switch assertion {
                        case .exists(let target), .missing(let target),
                             .appeared(let target), .disappeared(let target):
                            observedTargets.append(target)
                        case .updated(let target, _):
                            observedTargets.append(target.accessibilityTarget)
                        }
                    }
                case .notification(let notification):
                    if let element = notification.element {
                        observedTargets.append(.predicate(element))
                    }
                }
            }
            for var target in observedTargets {
                targetTraversal: while true {
                    let fact: HeistTargetPredicateFact
                    switch target {
                    case .predicate(let predicate, _):
                        fact = .predicate(predicate)
                        for check in predicate.checks where check.hasPredicateLiteral && semanticFacetSet.insert(check).inserted {
                            semanticFacets.append(check)
                        }
                    case .container(let predicate, _): fact = .container(predicate)
                    case .ref(let reference): fact = .targetReference(reference)
                    case .within(_, let nestedTarget):
                        target = nestedTarget
                        continue targetTraversal
                    }
                    if targetPredicateSet.insert(fact).inserted { targetPredicates.append(fact) }
                    break targetTraversal
                }
            }
        }
        return HeistSemanticSurface(
            actionCommands: actionCommands,
            targetPredicates: targetPredicates,
            waits: waits,
            expectations: expectations,
            nestedRunHeists: nestedRunHeists,
            semanticSurfaces: semanticFacets
        )
    }
}
