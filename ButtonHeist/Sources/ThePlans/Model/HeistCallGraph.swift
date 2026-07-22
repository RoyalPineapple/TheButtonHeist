import Foundation

/// Directed graph of named local heist capability calls.
public struct HeistCallGraph: Sendable, Equatable {
    /// A resolved `RunHeist` edge from one definition body to another definition.
    public struct Edge: Sendable, Equatable, Hashable {
        public let caller: HeistInvocationPath
        public let callee: HeistInvocationPath

        public init(caller: HeistInvocationPath, callee: HeistInvocationPath) {
            self.caller = caller
            self.callee = callee
        }
    }

    /// A witnessed cycle in resolved definition-name order.
    public struct Cycle: Error, Sendable, Equatable {
        public let path: [HeistInvocationPath]

        public init(path: [HeistInvocationPath]) {
            self.path = path
        }

        /// Human-readable cycle path, e.g. `A -> B -> A`.
        public var displayPath: String {
            path.map(\.description).joined(separator: " -> ")
        }
    }

    // MARK: - Properties

    public let nodes: Set<HeistInvocationPath>
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
        var collector = HeistCallGraphCollector()
        collector.collect(plan: plan)
        self.init(nodes: collector.nodes, edges: collector.edges)
    }

    public init(nodes: Set<HeistInvocationPath>, edges: Set<Edge>) {
        var allNodes = nodes
        for edge in edges {
            allNodes.insert(edge.caller)
            allNodes.insert(edge.callee)
        }
        self.nodes = allNodes
        self.edges = edges
    }

    // MARK: - Ordering

    public func topologicalOrder() -> Result<[HeistInvocationPath], Cycle> {
        var incomingCounts = Dictionary(uniqueKeysWithValues: nodes.map { ($0, 0) })
        edges.forEach { incomingCounts[$0.callee, default: 0] += 1 }

        let outgoing = Dictionary(grouping: edges, by: \.caller)
        var ready = Self.sorted(incomingCounts.filter { $0.value == 0 }.map(\.key))
        var order: [HeistInvocationPath] = []

        while let node = ready.first {
            ready.removeFirst()
            order.append(node)
            for callee in Self.sorted((outgoing[node] ?? []).map(\.callee)) {
                incomingCounts[callee, default: 0] -= 1
                if incomingCounts[callee] == 0 {
                    ready.append(callee)
                    ready = Self.sorted(ready)
                }
            }
        }

        guard order.count == nodes.count else {
            return .failure(witnessCycle())
        }
        return .success(order)
    }

    // MARK: - Cycle Witnesses

    func nodeCycle(closing callee: HeistInvocationPath, in invocationStack: [HeistInvocationPath]) -> Cycle? {
        guard let caller = invocationStack.last,
              edges.contains(Edge(caller: caller, callee: callee))
        else { return nil }
        return Self.nodeCycle(closing: callee, in: invocationStack)
    }

    static func nodeCycle(closing callee: HeistInvocationPath, in invocationStack: [HeistInvocationPath]) -> Cycle? {
        guard let startIndex = invocationStack.firstIndex(of: callee) else { return nil }
        return Cycle(path: Array(invocationStack[startIndex...]) + [callee])
    }

    private func witnessCycle() -> Cycle {
        enum VisitState {
            case visiting
            case visited
        }

        let outgoing = Dictionary(grouping: edges, by: \.caller)
        var states: [HeistInvocationPath: VisitState] = [:]
        var stack: [HeistInvocationPath] = []

        func cyclePath(closing node: HeistInvocationPath) -> [HeistInvocationPath] {
            guard let startIndex = stack.firstIndex(of: node) else { return stack + [node] }
            return Array(stack[startIndex...]) + [node]
        }

        func visit(_ node: HeistInvocationPath) -> Cycle? {
            states[node] = .visiting
            stack.append(node)
            for callee in Self.sorted((outgoing[node] ?? []).map(\.callee)) {
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

        for node in Self.sorted(nodes) where states[node] == nil {
            if let cycle = visit(node) {
                return cycle
            }
        }

        return Cycle(path: [])
    }

    private static func sorted<S: Sequence>(_ paths: S) -> [HeistInvocationPath] where S.Element == HeistInvocationPath {
        paths.sorted { $0.description < $1.description }
    }
}

// MARK: - Graph Collection

private struct HeistCallGraphCollector {
    var nodes: Set<HeistInvocationPath> = []
    var edges: Set<HeistCallGraph.Edge> = []

    mutating func collect(plan: HeistPlan) {
        let traversal = HeistPlanTraversal(expandsInvocations: false)
        traversal.walk(plan) { event in
            collect(event)
        }
    }

    private mutating func collect(_ event: HeistPlanTraversal.Event) {
        switch event {
        case .enterDefinition(let plan, let context):
            guard let name = plan.name else {
                preconditionFailure("admitted heist definitions must have names")
            }
            nodes.insert(HeistInvocationPath(namePath: context.definitionScope.pathPrefix + [name]))
        case .invoke(let invocation, let context):
            guard let caller = context.invocationStack.last,
                  let resolved = context.resolveInvocation(path: invocation.path)
            else { return }
            let callee = resolved.invocationPath
            nodes.insert(callee)
            edges.insert(HeistCallGraph.Edge(caller: caller, callee: callee))
        case .enterPlan,
             .leavePlan,
             .enterDefinitions,
             .leaveDefinitions,
             .leaveDefinition,
             .enterSteps,
             .leaveSteps,
             .enterStep,
             .leaveStep,
             .action,
             .wait,
             .conditional,
             .predicateCase,
             .elseBody,
             .forEachElement,
             .forEachString,
             .repeatUntil,
             .warn,
             .fail,
             .heist:
            break
        }
    }
}
