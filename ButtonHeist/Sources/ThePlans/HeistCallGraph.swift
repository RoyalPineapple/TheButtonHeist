import Foundation

/// Directed graph of named local heist capability calls.
public struct HeistCallGraph: Sendable, Equatable {
    /// A resolved `RunHeist` edge from one definition body to another definition.
    public struct Edge: Sendable, Equatable, Hashable {
        public let caller: String
        public let callee: String

        public init(caller: String, callee: String) {
            self.caller = caller
            self.callee = callee
        }
    }

    /// A witnessed cycle in resolved definition-name order.
    public struct Cycle: Error, Sendable, Equatable {
        public let path: [String]

        public init(path: [String]) {
            self.path = path
        }

        /// Human-readable cycle path, e.g. `A -> B -> A`.
        public var displayPath: String {
            path.joined(separator: " -> ")
        }
    }

    // MARK: - Properties

    public let nodes: Set<String>
    public let edges: Set<Edge>

    /// Whether every resolved `RunHeist` edge can be topologically ordered.
    public var isAcyclic: Bool {
        switch topologicalOrder() {
        case .success:
            return true
        case .failure:
            return false
        }
    }

    // MARK: - Init

    public init(plan: HeistPlan) {
        var builder = HeistCallGraphBuilder()
        builder.collect(plan: plan)
        nodes = builder.nodes
        edges = builder.edges
    }

    public init(nodes: Set<String>, edges: Set<Edge>) {
        self.nodes = nodes.union(edges.flatMap { [$0.caller, $0.callee] })
        self.edges = edges
    }

    // MARK: - Ordering

    public func topologicalOrder() -> Result<[String], Cycle> {
        var incomingCounts = Dictionary(uniqueKeysWithValues: nodes.map { ($0, 0) })
        edges.forEach { incomingCounts[$0.callee, default: 0] += 1 }

        let outgoing = Dictionary(grouping: edges, by: \.caller)
        var ready = incomingCounts
            .filter { $0.value == 0 }
            .map(\.key)
            .sorted()
        var order: [String] = []

        while let node = ready.first {
            ready.removeFirst()
            order.append(node)
            for callee in (outgoing[node] ?? []).map(\.callee).sorted() {
                incomingCounts[callee, default: 0] -= 1
                if incomingCounts[callee] == 0 {
                    ready.append(callee)
                    ready.sort()
                }
            }
        }

        guard order.count == nodes.count else {
            return .failure(witnessCycle())
        }
        return .success(order)
    }

    // MARK: - Cycle Witnesses

    func cycle(closing callee: String, in invocationStack: [String]) -> Cycle? {
        guard let caller = invocationStack.last,
              edges.contains(Edge(caller: caller, callee: callee))
        else { return nil }
        return Self.cycle(closing: callee, in: invocationStack)
    }

    static func cycle(closing callee: String, in invocationStack: [String]) -> Cycle? {
        guard let startIndex = invocationStack.firstIndex(of: callee) else { return nil }
        return Cycle(path: Array(invocationStack[startIndex...]) + [callee])
    }

    private func witnessCycle() -> Cycle {
        enum VisitState {
            case visiting
            case visited
        }

        let outgoing = Dictionary(grouping: edges, by: \.caller)
        var states: [String: VisitState] = [:]
        var stack: [String] = []

        func cyclePath(closing node: String) -> [String] {
            guard let startIndex = stack.firstIndex(of: node) else { return stack + [node] }
            return Array(stack[startIndex...]) + [node]
        }

        func visit(_ node: String) -> Cycle? {
            states[node] = .visiting
            stack.append(node)
            for callee in (outgoing[node] ?? []).map(\.callee).sorted() {
                switch states[callee] {
                case .visiting:
                    return Cycle(path: cyclePath(closing: callee))
                case .visited:
                    continue
                case nil:
                    if let cycle = visit(callee) {
                        return cycle
                    }
                }
            }
            _ = stack.popLast()
            states[node] = .visited
            return nil
        }

        for node in nodes.sorted() where states[node] == nil {
            if let cycle = visit(node) {
                return cycle
            }
        }

        return Cycle(path: [])
    }
}

// MARK: - Graph Building

private struct HeistCallGraphBuilder {
    var nodes: Set<String> = []
    var edges: Set<HeistCallGraph.Edge> = []

    mutating func collect(plan: HeistPlan) {
        let rootScope = HeistDefinitionScope(definitions: plan.definitions)
        collectDefinitions(plan.definitions, pathPrefix: [], rootDefinitionScope: rootScope)
        collectAnonymousDefinitionScopes(in: plan.body)
    }

    private mutating func collectDefinitions(
        _ definitions: [HeistPlan],
        pathPrefix: [String],
        rootDefinitionScope: HeistDefinitionScope
    ) {
        let definitionScope = HeistDefinitionScope(definitions: definitions, pathPrefix: pathPrefix)
        definitions.forEach {
            collectDefinition($0, definitionScope: definitionScope, rootDefinitionScope: rootDefinitionScope)
        }
    }

    private mutating func collectDefinition(
        _ definition: HeistPlan,
        definitionScope: HeistDefinitionScope,
        rootDefinitionScope: HeistDefinitionScope
    ) {
        let namePath = definitionScope.pathPrefix + [definition.name ?? ""]
        let qualifiedName = HeistInvocationPath.render(namePath)
        nodes.insert(qualifiedName)

        let childScope = HeistDefinitionScope(definitions: definition.definitions, pathPrefix: namePath)
        collectEdges(
            in: definition.body,
            caller: qualifiedName,
            definitionScope: childScope,
            rootDefinitionScope: rootDefinitionScope
        )
        collectDefinitions(definition.definitions, pathPrefix: namePath, rootDefinitionScope: rootDefinitionScope)
    }

    private mutating func collectEdges(
        in steps: [HeistStep],
        caller: String,
        definitionScope: HeistDefinitionScope,
        rootDefinitionScope: HeistDefinitionScope
    ) {
        steps.forEach {
            collectEdges(
                in: $0,
                caller: caller,
                definitionScope: definitionScope,
                rootDefinitionScope: rootDefinitionScope
            )
        }
    }

    private mutating func collectEdges(
        in step: HeistStep,
        caller: String,
        definitionScope: HeistDefinitionScope,
        rootDefinitionScope: HeistDefinitionScope
    ) {
        switch step {
        case .action, .wait, .warn, .fail:
            break
        case .conditional(let conditional):
            conditional.cases.forEach {
                collectEdges(
                    in: $0.body,
                    caller: caller,
                    definitionScope: definitionScope,
                    rootDefinitionScope: rootDefinitionScope
                )
            }
            if let elseBody = conditional.elseBody {
                collectEdges(
                    in: elseBody,
                    caller: caller,
                    definitionScope: definitionScope,
                    rootDefinitionScope: rootDefinitionScope
                )
            }
        case .forEachElement(let forEach):
            collectEdges(
                in: forEach.body,
                caller: caller,
                definitionScope: definitionScope,
                rootDefinitionScope: rootDefinitionScope
            )
        case .forEachString(let forEach):
            collectEdges(
                in: forEach.body,
                caller: caller,
                definitionScope: definitionScope,
                rootDefinitionScope: rootDefinitionScope
            )
        case .repeatUntil(let repeatUntil):
            collectEdges(
                in: repeatUntil.body,
                caller: caller,
                definitionScope: definitionScope,
                rootDefinitionScope: rootDefinitionScope
            )
            if let elseBody = repeatUntil.elseBody {
                collectEdges(
                    in: elseBody,
                    caller: caller,
                    definitionScope: definitionScope,
                    rootDefinitionScope: rootDefinitionScope
                )
            }
        case .heist(let plan):
            let inlineScope = HeistDefinitionScope(definitions: plan.definitions)
            collectDefinitions(plan.definitions, pathPrefix: [], rootDefinitionScope: inlineScope)
            collectEdges(in: plan.body, caller: caller, definitionScope: inlineScope, rootDefinitionScope: inlineScope)
        case .invoke(let invocation):
            guard let resolved = definitionScope.resolveInvocation(
                path: invocation.invocationPath,
                rootScope: rootDefinitionScope
            ) else { return }
            nodes.insert(resolved.qualifiedName)
            edges.insert(HeistCallGraph.Edge(caller: caller, callee: resolved.qualifiedName))
        }
    }

    private mutating func collectAnonymousDefinitionScopes(in steps: [HeistStep]) {
        steps.forEach { collectAnonymousDefinitionScopes(in: $0) }
    }

    private mutating func collectAnonymousDefinitionScopes(in step: HeistStep) {
        switch step {
        case .action, .wait, .warn, .fail, .invoke:
            break
        case .conditional(let conditional):
            conditional.cases.forEach { collectAnonymousDefinitionScopes(in: $0.body) }
            if let elseBody = conditional.elseBody {
                collectAnonymousDefinitionScopes(in: elseBody)
            }
        case .forEachElement(let forEach):
            collectAnonymousDefinitionScopes(in: forEach.body)
        case .forEachString(let forEach):
            collectAnonymousDefinitionScopes(in: forEach.body)
        case .repeatUntil(let repeatUntil):
            collectAnonymousDefinitionScopes(in: repeatUntil.body)
            if let elseBody = repeatUntil.elseBody {
                collectAnonymousDefinitionScopes(in: elseBody)
            }
        case .heist(let plan):
            collect(plan: plan)
        }
    }
}
