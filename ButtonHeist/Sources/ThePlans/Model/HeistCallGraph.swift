import Foundation

/// Directed graph of named local heist capability calls.
public struct HeistCallGraph: Sendable, Equatable {
    struct Node: Sendable, Equatable, Hashable, Comparable, CustomStringConvertible {
        let path: HeistInvocationPath

        init(_ path: HeistInvocationPath) {
            self.path = path
        }

        init(namePath: [HeistPlanName]) {
            guard let first = namePath.first else {
                preconditionFailure("call graph nodes require a non-empty heist path")
            }
            self.init(HeistInvocationPath(first: first, remaining: Array(namePath.dropFirst())))
        }

        var description: String {
            path.description
        }

        static func < (lhs: Node, rhs: Node) -> Bool {
            lhs.description < rhs.description
        }
    }

    /// A resolved `RunHeist` edge from one definition body to another definition.
    public struct Edge: Sendable, Equatable, Hashable {
        public let caller: HeistInvocationPath
        public let callee: HeistInvocationPath

        public init(caller: HeistInvocationPath, callee: HeistInvocationPath) {
            self.caller = caller
            self.callee = callee
        }

        init(_ edge: NodeEdge) {
            self.init(caller: edge.caller.path, callee: edge.callee.path)
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
        public let path: [HeistInvocationPath]

        public init(path: [HeistInvocationPath]) {
            self.path = path
        }

        init(_ cycle: NodeCycle) {
            self.init(path: cycle.path.map(\.path))
        }

        /// Human-readable cycle path, e.g. `A -> B -> A`.
        public var displayPath: String {
            path.map(\.description).joined(separator: " -> ")
        }
    }

    struct NodeCycle: Error, Sendable, Equatable {
        let path: [Node]

        var displayPath: String {
            path.map(\.description).joined(separator: " -> ")
        }
    }

    // MARK: - Properties

    let typedNodes: Set<Node>
    let typedEdges: Set<NodeEdge>

    public var nodes: Set<HeistInvocationPath> {
        Set(typedNodes.map(\.path))
    }

    public var edges: Set<Edge> {
        Set(typedEdges.map(Edge.init))
    }

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

    public init(nodes: Set<HeistInvocationPath>, edges: Set<Edge>) {
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
    }

    // MARK: - Ordering

    public func topologicalOrder() -> Result<[HeistInvocationPath], Cycle> {
        switch topologicalNodeOrder() {
        case .success(let order):
            return .success(order.map(\.path))
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

private struct HeistCallGraphBuilder: HeistPlanTraversalVisitor {
    var nodes: Set<HeistCallGraph.Node> = []
    var edges: Set<HeistCallGraph.NodeEdge> = []

    mutating func collect(plan: HeistPlan) {
        let traversal = HeistPlanTraversal(expandsInvocations: false)
        traversal.walk(plan, visitor: &self)
    }

    mutating func visitDefinition(_ plan: HeistPlan, context: HeistTraversalContext) {
        guard let name = plan.name else {
            preconditionFailure("admitted heist definitions must have names")
        }
        nodes.insert(HeistCallGraph.Node(namePath: context.definitionScope.pathPrefix + [name]))
    }

    mutating func visitInvoke(_ step: HeistInvocationStep, context: HeistTraversalContext) {
        guard let caller = context.invocationStack.last,
              let resolved = context.resolveInvocation(path: step.path)
        else { return }
        let callee = resolved.callGraphNode
        nodes.insert(callee)
        edges.insert(HeistCallGraph.NodeEdge(caller: caller, callee: callee))
    }
}
