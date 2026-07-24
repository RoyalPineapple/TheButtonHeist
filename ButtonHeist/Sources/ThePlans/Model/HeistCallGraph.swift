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
        var nodes: Set<HeistInvocationPath> = []
        var edges: Set<Edge> = []
        HeistPlanTraversal(expandsInvocations: false).walk(plan) { event in
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
                nodes.insert(resolved.invocationPath)
                edges.insert(Edge(caller: caller, callee: resolved.invocationPath))
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
        self.init(nodes: nodes, edges: edges)
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
        var ready = incomingCounts.filter { $0.value == 0 }.map(\.key).sorted { $0.description < $1.description }
        var order: [HeistInvocationPath] = []

        while let node = ready.first {
            ready.removeFirst()
            order.append(node)
            for callee in (outgoing[node] ?? []).map(\.callee)
                .sorted(by: { $0.description < $1.description }) {
                incomingCounts[callee, default: 0] -= 1
                if incomingCounts[callee] == 0 {
                    ready.append(callee)
                    ready.sort { $0.description < $1.description }
                }
            }
        }

        guard order.count == nodes.count else {
            return .failure(witnessCycle())
        }
        return .success(order)
    }

    // MARK: - Cycle Witnesses

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
            for callee in (outgoing[node] ?? []).map(\.callee)
                .sorted(by: { $0.description < $1.description }) {
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

        for node in nodes.sorted(by: { $0.description < $1.description }) where states[node] == nil {
            if let cycle = visit(node) {
                return cycle
            }
        }

        return Cycle(path: [])
    }
}
