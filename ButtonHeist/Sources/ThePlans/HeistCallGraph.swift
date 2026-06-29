import Foundation

/// Directed graph of named local heist capability calls.
public struct HeistCallGraph: Sendable, Equatable {
    struct Node: Sendable, Equatable, Hashable, Comparable, CustomStringConvertible {
        let name: String

        init(_ name: String) {
            self.name = name
        }

        init(namePath: [String]) {
            self.init(HeistInvocationPath.render(namePath))
        }

        var description: String {
            name
        }

        static func < (lhs: Node, rhs: Node) -> Bool {
            lhs.name < rhs.name
        }
    }

    /// A resolved `RunHeist` edge from one definition body to another definition.
    public struct Edge: Sendable, Equatable, Hashable {
        public let caller: String
        public let callee: String

        public init(caller: String, callee: String) {
            self.caller = caller
            self.callee = callee
        }

        init(_ edge: NodeEdge) {
            self.init(caller: edge.caller.name, callee: edge.callee.name)
        }
    }

    struct NodeEdge: Sendable, Equatable, Hashable {
        let caller: Node
        let callee: Node

        init(caller: Node, callee: Node) {
            self.caller = caller
            self.callee = callee
        }

        init(_ edge: Edge) {
            self.init(caller: Node(edge.caller), callee: Node(edge.callee))
        }
    }

    /// A witnessed cycle in resolved definition-name order.
    public struct Cycle: Error, Sendable, Equatable {
        public let path: [String]

        public init(path: [String]) {
            self.path = path
        }

        init(_ cycle: NodeCycle) {
            self.init(path: cycle.path.map(\.name))
        }

        /// Human-readable cycle path, e.g. `A -> B -> A`.
        public var displayPath: String {
            path.joined(separator: " -> ")
        }
    }

    struct NodeCycle: Error, Sendable, Equatable {
        let path: [Node]

        var displayPath: String {
            path.map(\.name).joined(separator: " -> ")
        }
    }

    // MARK: - Properties

    public let nodes: Set<String>
    public let edges: Set<Edge>
    let typedNodes: Set<Node>
    let typedEdges: Set<NodeEdge>

    /// Whether every resolved `RunHeist` edge can be topologically ordered.
    public var isAcyclic: Bool {
        switch topologicalNodeOrder() {
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
        self.init(typedNodes: builder.nodes, typedEdges: builder.edges)
    }

    public init(nodes: Set<String>, edges: Set<Edge>) {
        self.init(
            typedNodes: Set(nodes.map(Node.init)),
            typedEdges: Set(edges.map(NodeEdge.init))
        )
    }

    private init(typedNodes: Set<Node>, typedEdges: Set<NodeEdge>) {
        var allTypedNodes = typedNodes
        for edge in typedEdges {
            allTypedNodes.insert(edge.caller)
            allTypedNodes.insert(edge.callee)
        }
        self.typedNodes = allTypedNodes
        self.typedEdges = typedEdges
        nodes = Set(allTypedNodes.map(\.name))
        edges = Set(typedEdges.map(Edge.init))
    }

    // MARK: - Ordering

    public func topologicalOrder() -> Result<[String], Cycle> {
        switch topologicalNodeOrder() {
        case .success(let order):
            return .success(order.map(\.name))
        case .failure(let cycle):
            return .failure(Cycle(cycle))
        }
    }

    func topologicalNodeOrder() -> Result<[Node], NodeCycle> {
        var incomingCounts = Dictionary(uniqueKeysWithValues: typedNodes.map { ($0, 0) })
        typedEdges.forEach { incomingCounts[$0.callee, default: 0] += 1 }

        let outgoing = Dictionary(grouping: typedEdges, by: \.caller)
        var ready = incomingCounts
            .filter { $0.value == 0 }
            .map(\.key)
            .sorted()
        var order: [Node] = []

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

        guard order.count == typedNodes.count else {
            return .failure(witnessNodeCycle())
        }
        return .success(order)
    }

    // MARK: - Cycle Witnesses

    func nodeCycle(closing callee: Node, in invocationStack: [Node]) -> NodeCycle? {
        guard let caller = invocationStack.last,
              typedEdges.contains(NodeEdge(caller: caller, callee: callee))
        else { return nil }
        return Self.nodeCycle(closing: callee, in: invocationStack)
    }

    static func nodeCycle(closing callee: Node, in invocationStack: [Node]) -> NodeCycle? {
        guard let startIndex = invocationStack.firstIndex(of: callee) else { return nil }
        return NodeCycle(path: Array(invocationStack[startIndex...]) + [callee])
    }

    private func witnessNodeCycle() -> NodeCycle {
        enum VisitState {
            case visiting
            case visited
        }

        let outgoing = Dictionary(grouping: typedEdges, by: \.caller)
        var states: [Node: VisitState] = [:]
        var stack: [Node] = []

        func cyclePath(closing node: Node) -> [Node] {
            guard let startIndex = stack.firstIndex(of: node) else { return stack + [node] }
            return Array(stack[startIndex...]) + [node]
        }

        func visit(_ node: Node) -> NodeCycle? {
            states[node] = .visiting
            stack.append(node)
            for callee in (outgoing[node] ?? []).map(\.callee).sorted() {
                switch states[callee] {
                case .visiting:
                    return NodeCycle(path: cyclePath(closing: callee))
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

        for node in typedNodes.sorted() where states[node] == nil {
            if let cycle = visit(node) {
                return cycle
            }
        }

        return NodeCycle(path: [])
    }
}

// MARK: - Graph Building

private struct HeistCallGraphBuilder {
    var nodes: Set<HeistCallGraph.Node> = []
    var edges: Set<HeistCallGraph.NodeEdge> = []

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
        let definitionNode = HeistCallGraph.Node(namePath: namePath)
        nodes.insert(definitionNode)

        let childScope = HeistDefinitionScope(definitions: definition.definitions, pathPrefix: namePath)
        collectEdges(
            in: definition.body,
            caller: definitionNode,
            definitionScope: childScope,
            rootDefinitionScope: rootDefinitionScope
        )
        collectDefinitions(definition.definitions, pathPrefix: namePath, rootDefinitionScope: rootDefinitionScope)
    }

    private mutating func collectEdges(
        in steps: [HeistStep],
        caller: HeistCallGraph.Node,
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
        caller: HeistCallGraph.Node,
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
            let callee = resolved.callGraphNode
            nodes.insert(callee)
            edges.insert(HeistCallGraph.NodeEdge(caller: caller, callee: callee))
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
