import Foundation
import ButtonHeistTestSupport
import Testing
@_spi(ButtonHeistInternals) @testable import ThePlans

private struct EncodedInvocationStepContract: Decodable {
    let path: String
}

@Test func `empty call graph is acyclic`() throws {
    let graph = HeistCallGraph(nodes: [], edges: [])

    #expect(graph.isAcyclic)
    #expect(try graph.requireTopologicalOrder() == [])
}

@Test func `single node call graph is acyclic`() throws {
    let graph = HeistCallGraph(nodes: ["A"], edges: [])

    #expect(graph.isAcyclic)
    #expect(try graph.requireTopologicalOrder() == ["A"])
}

@Test func `call graph stores canonical nodes and edges`() throws {
    let graph = callGraph(edges: [("A", "C"), ("B", "C")])

    #expect(graph.nodes == ["A", "B", "C"])
    #expect(graph.edges == Set([
        HeistCallGraph.Edge(caller: "A", callee: "C"),
        HeistCallGraph.Edge(caller: "B", callee: "C"),
    ]))
    let publicOrder = try graph.requireTopologicalOrder()
    #expect(publicOrder == ["A", "B", "C"])
}

@Test func `linear call graph returns forward order`() throws {
    let graph = callGraph(edges: [("A", "B"), ("B", "C")])
    let order = try graph.requireTopologicalOrder()

    #expect(graph.isAcyclic)
    #expect(order.respects(graph.edges))
}

@Test func `diamond call graph returns forward order`() throws {
    let graph = callGraph(edges: [("A", "B"), ("A", "C"), ("B", "D"), ("C", "D")])
    let order = try graph.requireTopologicalOrder()

    #expect(graph.isAcyclic)
    #expect(order.respects(graph.edges))
}

@Test func `self loop reports witnessed cycle`() throws {
    let graph = callGraph(edges: [("A", "A")])

    #expect(!graph.isAcyclic)
    #expect(graph.requireCycle().path == ["A", "A"])
}

@Test func `two node cycle reports witnessed cycle`() throws {
    let graph = callGraph(edges: [("A", "B"), ("B", "A")])

    #expect(!graph.isAcyclic)
    #expect(graph.requireCycle().path == ["A", "B", "A"])
    #expect(graph.requireCycle().displayPath == "A -> B -> A")
}

@Test func `longer cycle reports witnessed cycle`() throws {
    let graph = callGraph(edges: [("A", "B"), ("B", "C"), ("C", "D"), ("D", "B")])

    #expect(!graph.isAcyclic)
    #expect(graph.requireCycle().path == ["B", "C", "D", "B"])
}

@Test func `cycle in one component makes whole call graph cyclic`() throws {
    let graph = callGraph(edges: [("A", "B"), ("C", "D"), ("D", "C")])

    #expect(!graph.isAcyclic)
    #expect(graph.requireCycle().path == ["C", "D", "C"])
}

@Test func `cycle api accepts invocation path stacks`() throws {
    let node: HeistInvocationPath = "A"
    let graph = callGraph(edges: [("A", "A")])
    let graphCycle = try #require(graph.nodeCycle(closing: node, in: [node]))
    let stackCycle = try #require(HeistCallGraph.nodeCycle(closing: node, in: [node]))

    #expect(graphCycle.path == [node, node])
    #expect(stackCycle.path == [node, node])
    #expect(graphCycle.path == ["A", "A"])
    #expect(stackCycle.displayPath == "A -> A")
}

@Test func `plan call graph resolves invocations in their definition scope`() throws {
    let raw = HeistPlanAdmissionCandidate(definitions: [
        HeistPlanAdmissionCandidate(name: "Cart", definitions: [
            HeistPlanAdmissionCandidate(name: "addToCart", definitions: [
                HeistPlanAdmissionCandidate(name: "tapAddButton", body: [
                    .warn(WarnStep(message: "tap")),
                ]),
            ], body: [
                .invoke(HeistInvocationStep(path: "tapAddButton")),
            ]),
        ], body: []),
    ], body: [.warn(WarnStep(message: "root"))])

    let graph = HeistCallGraph(plan: try raw.validatedForRuntimeSafety())

    #expect(graph.nodes == ["Cart", "Cart.addToCart", "Cart.addToCart.tapAddButton"])
    #expect(graph.edges == [
        HeistCallGraph.Edge(caller: "Cart.addToCart", callee: "Cart.addToCart.tapAddButton"),
    ])
}

@Test func `plan call graph resolves qualified exported namespace invocations from definition bodies`() throws {
    let typedPath: HeistInvocationPath = "lib.b"
    let raw = HeistPlanAdmissionCandidate(definitions: [
        HeistPlanAdmissionCandidate(name: "lib", definitions: [
            HeistPlanAdmissionCandidate(name: "a", body: [
                .invoke(HeistInvocationStep(path: typedPath)),
            ]),
            HeistPlanAdmissionCandidate(name: "b", body: [
                .warn(WarnStep(message: "b")),
            ]),
        ], body: []),
    ], body: [.invoke(HeistInvocationStep(path: "lib.a"))])

    let graph = HeistCallGraph(plan: try raw.validatedForRuntimeSafety())

    #expect(graph.edges.contains(HeistCallGraph.Edge(caller: "lib.a", callee: "lib.b")))
}

@Test func `plan call graph includes invocations in wait else bodies`() throws {
    let raw = HeistPlanAdmissionCandidate(definitions: [
        HeistPlanAdmissionCandidate(name: "checkout", definitions: [
            HeistPlanAdmissionCandidate(name: "fallback", body: [
                .warn(WarnStep(message: "fallback")),
            ]),
        ], body: [
            .wait(WaitStep(
                predicate: .exists(.label("Ready")),
                timeout: 0.001,
                elseBody: [.invoke(HeistInvocationStep(path: "fallback"))]
            )),
        ]),
    ], body: [.warn(WarnStep(message: "root"))])

    let graph = HeistCallGraph(plan: try raw.validatedForRuntimeSafety())

    #expect(graph.edges.contains(HeistCallGraph.Edge(caller: "checkout", callee: "checkout.fallback")))
}

@Test func `duplicate definition candidates cannot yield an executable plan`() throws {
    let candidate = HeistPlanAdmissionCandidate(definitions: [
        HeistPlanAdmissionCandidate(name: "duplicate", body: [.warn(WarnStep(message: "one"))]),
        HeistPlanAdmissionCandidate(name: "duplicate", body: [.warn(WarnStep(message: "two"))]),
    ], body: [.warn(WarnStep(message: "root"))])

    let diagnostics = try runtimeSafetyDiagnostics(candidate)
    #expect(diagnostics.contains {
        $0.path == "$.definitions[1].name"
            && $0.code == .planRuntimeSafety
    })
}

@Test func `typed invocation path owns single value invoke JSON`() throws {
    let invocationPath: HeistInvocationPath = "LibraryScreen.addToCart"
    let invocation = HeistInvocationStep(path: invocationPath)

    #expect(invocation.path == invocationPath)
    #expect(invocation.path.components == ["LibraryScreen", "addToCart"])
    #expect(invocation.path == invocationPath)

    let encoded = try JSONEncoder().encode(invocation)
    let json = try JSONDecoder().decode(EncodedInvocationStepContract.self, from: encoded)
    #expect(json.path == "LibraryScreen.addToCart")

    let decoded = try JSONDecoder().decode(HeistInvocationStep.self, from: encoded)
    #expect(decoded == invocation)
    #expect(decoded.path == invocationPath)
}

@Test func `traversal path builder renders stable diagnostic paths`() {
    let path = HeistPlanPath.root
        .child(.body)
        .index(0)
        .child(.conditional)
        .child(.cases)
        .index(1)
        .child(.body)

    #expect(path.description == "$.body[0].conditional.cases[1].body")
}

@Test func `reference binding context keeps scope and placeholders aligned`() throws {
    let target = try AccessibilityTarget.predicate(.label("Pay"), ordinal: 1)
        .resolve(in: .empty)
    let context = HeistReferenceBindingContext.empty
        .binding(string: "milk", to: "query")
        .binding(target: target, to: "button")

    #expect(context.invariantFailures.isEmpty)
    #expect(context.bindings == [
        HeistReferenceBinding(reference: "query", value: .string("milk")),
        HeistReferenceBinding(reference: "button", value: .accessibilityTarget(target)),
    ])
    #expect(context.scope.stringRefs == ["query"])
    #expect(context.scope.targetRefs == ["button"])
    #expect(context.environment.strings["query"] == "milk")
    #expect(context.environment.targets["button"] == target)

    let rootParameter = HeistReferenceBindingContext.runtimeSafetyPlaceholder(for: .string(name: "term"))
    #expect(rootParameter.invariantFailures.isEmpty)
    #expect(rootParameter.bindings == [
        HeistReferenceBinding(
            reference: "term",
            value: .string(HeistReferenceBinding.runtimeSafetyStringPlaceholder)
        ),
    ])
    #expect(rootParameter.scope.stringRefs == ["term"])
    #expect(rootParameter.environment.strings["term"] == HeistReferenceBinding.runtimeSafetyStringPlaceholder)

    let invocation = try context.binding(
        argument: HeistArgument.string(reference: "query"),
        to: HeistParameter.string(name: "copy")
    )
    #expect(invocation.invariantFailures.isEmpty)
    #expect(invocation.bindings.last == HeistReferenceBinding(reference: "copy", value: .string("milk")))
    #expect(invocation.scope.stringRefs == ["copy", "query"])
    #expect(invocation.scope.targetRefs == ["button"])
    #expect(invocation.environment.strings["copy"] == "milk")
    #expect(invocation.environment.targets["button"] == target)
}

@Test func `definition resolution preserves typed invocation identity`() throws {
    let checkout = try HeistPlan(
        name: "Checkout",
        body: [.warn(WarnStep(message: "checkout"))]
    )
    let cart = try HeistPlan(
        name: "Cart",
        definitions: [checkout],
        body: []
    )
    let scope = HeistDefinitionScope(definitions: [cart])
    let invocationPath: HeistInvocationPath = "Cart.Checkout"

    let resolved = try #require(scope.resolveInvocation(path: invocationPath, rootScope: scope))

    #expect(resolved.invocationPath == invocationPath)
    #expect(resolved.qualifiedName == "Cart.Checkout")
    #expect(resolved.namePath == ["Cart", "Checkout"])
}

@Test func `random generated definition graphs agree with reference cycle checker`() throws {
    var rng = SeededGenerator(seed: 0xAC1DCA11)

    for caseIndex in 0..<200 {
        let model = try RandomDefinitionGraph(caseIndex: caseIndex, rng: &rng)
        let graph = HeistCallGraph(nodes: Set(model.nodes), edges: model.edges)
        let expectedAcyclic = referenceIsAcyclic(nodes: model.nodes, edges: model.edges)

        #expect(graph.isAcyclic == expectedAcyclic, "case \(caseIndex)")
        switch graph.topologicalOrder() {
        case .success(let order):
            #expect(expectedAcyclic, "case \(caseIndex)")
            #expect(Set(order) == Set(model.nodes), "case \(caseIndex)")
            #expect(order.respects(graph.edges), "case \(caseIndex)")
        case .failure(let cycle):
            #expect(!expectedAcyclic, "case \(caseIndex)")
            #expect(cycle.path.count >= 2, "case \(caseIndex)")
            #expect(cycle.path.first == cycle.path.last, "case \(caseIndex)")
            #expect(cycle.path.adjacentPairs().allSatisfy { graph.edges.contains(.init(caller: $0.0, callee: $0.1)) })
        }
    }
}

@Test func `runtime admission recursive failures are deterministic cycle witnesses`() throws {
    let cases: [RuntimeAdmissionCallGraphCase] = [
        RuntimeAdmissionCallGraphCase(candidate: inlineChainCase(["A", "B", "C"]), expectedCycle: nil),
        RuntimeAdmissionCallGraphCase(candidate: inlineCycleCase(["A"]), expectedCycle: "A -> A"),
        RuntimeAdmissionCallGraphCase(candidate: inlineCycleCase(["A", "B"]), expectedCycle: "A -> B -> A"),
        RuntimeAdmissionCallGraphCase(candidate: inlineCycleCase(["A", "B", "C"]), expectedCycle: "A -> B -> C -> A"),
    ]

    for testCase in cases {
        let recursiveFailures = runtimeSafetyFailures(for: testCase.candidate).filter {
            $0.contract == recursiveHeistRunContract
        }

        if let expectedCycle = testCase.expectedCycle {
            #expect(throws: HeistPlanRuntimeSafetyError.self) {
                _ = try testCase.candidate.validatedSemantics()
            }
            #expect(!recursiveFailures.isEmpty)
            #expect(Set(recursiveFailures.map(\.contract)) == [recursiveHeistRunContract])
            #expect(Set(recursiveFailures.map(\.observed)) == [expectedCycle])
            #expect(Set(recursiveFailures.map(\.correction)) == [recursiveHeistRunCorrection])
        } else {
            _ = try testCase.candidate.validatedSemantics()
            #expect(recursiveFailures.isEmpty)
        }
    }
}

private let recursiveHeistRunContract = "heist runs must not be recursive"
private let recursiveHeistRunCorrection = "Remove the recursive heist run cycle."

private func runtimeSafetyDiagnostics(
    _ candidate: HeistPlanAdmissionCandidate
) throws -> [HeistBuildDiagnostic] {
    do {
        _ = try candidate.validatedSemantics()
        throw CallGraphTestFailure.expectedRuntimeSafetyFailure
    } catch let error as HeistPlanRuntimeSafetyError {
        return error.diagnostics
    }
}

private enum CallGraphTestFailure: Error {
    case expectedRuntimeSafetyFailure
}

private struct RuntimeAdmissionCallGraphCase {
    let candidate: HeistPlanAdmissionCandidate
    let expectedCycle: String?
}

private func callGraph(edges: [(String, String)]) -> HeistCallGraph {
    let graphEdges = edges.map { caller, callee in
        HeistCallGraph.Edge(caller: typedPath(caller), callee: typedPath(callee))
    }
    return HeistCallGraph(
        nodes: Set(graphEdges.flatMap { [$0.caller, $0.callee] }),
        edges: Set(graphEdges)
    )
}

private func inlineChainCase(_ names: [HeistPlanName]) -> HeistPlanAdmissionCandidate {
    let definition = inlineChainDefinition(names)
    return HeistPlanAdmissionCandidate(
        definitions: [definition],
        body: [.invoke(HeistInvocationStep(path: invocationPath(definition.name)))]
    )
}

private func inlineCycleCase(_ names: [HeistPlanName]) -> HeistPlanAdmissionCandidate {
    guard let first = names.first else {
        return HeistPlanAdmissionCandidate(body: [.warn(WarnStep(message: "empty"))])
    }
    let definition = inlineCycleDefinition(name: first, remaining: Array(names.dropFirst()), first: first)
    return HeistPlanAdmissionCandidate(
        definitions: [definition],
        body: [.invoke(HeistInvocationStep(path: invocationPath(first)))]
    )
}

private func inlineChainDefinition(_ names: [HeistPlanName]) -> HeistPlanAdmissionCandidate {
    guard let name = names.first else {
        return HeistPlanAdmissionCandidate(name: "empty", body: [.warn(WarnStep(message: "empty"))])
    }
    guard names.count > 1 else {
        return HeistPlanAdmissionCandidate(name: name, body: [
            .warn(WarnStep(message: warningMessage("\(name) done"))),
        ])
    }
    let next = inlineChainDefinition(Array(names.dropFirst()))
    return HeistPlanAdmissionCandidate(name: name, body: [
        inlineHeist(definitions: [next], body: [
            .invoke(HeistInvocationStep(path: invocationPath(next.name))),
        ]),
    ])
}

private func inlineCycleDefinition(
    name: HeistPlanName,
    remaining: [HeistPlanName],
    first: HeistPlanName
) -> HeistPlanAdmissionCandidate {
    let next = remaining.first.map { nextName in
        inlineCycleDefinition(name: nextName, remaining: Array(remaining.dropFirst()), first: first)
    } ?? HeistPlanAdmissionCandidate(name: first, body: [
        .warn(WarnStep(message: warningMessage("\(first) done"))),
    ])
    return HeistPlanAdmissionCandidate(name: name, body: [
        inlineHeist(definitions: [next], body: [
            .invoke(HeistInvocationStep(path: invocationPath(next.name ?? first))),
        ]),
    ])
}

private func inlineHeist(
    definitions: [HeistPlanAdmissionCandidate],
    body: [HeistStepAdmissionCandidate]
) -> HeistStepAdmissionCandidate {
    .heist(HeistPlanAdmissionCandidate(definitions: definitions, body: body))
}

private func runtimeSafetyFailures(for raw: HeistPlanAdmissionCandidate) -> [HeistPlanRuntimeSafetyFailure] {
    do {
        _ = try raw.validatedForRuntimeSafety()
        return []
    } catch let error as HeistPlanRuntimeSafetyError {
        return error.failures
    } catch {
        Issue.record("Expected runtime safety error, got \(error)")
        return []
    }
}

private func invocationPath(_ name: HeistPlanName?) -> HeistInvocationPath {
    guard let name else {
        preconditionFailure("admitted test definitions must have names")
    }
    return HeistInvocationPath(first: name)
}

private func typedPath(_ value: String) -> HeistInvocationPath {
    do {
        return try HeistInvocationPath(validating: value)
    } catch {
        preconditionFailure("invalid generated test path \(value): \(error)")
    }
}

private func warningMessage(_ value: String) -> HeistWarningMessage {
    do {
        return try HeistWarningMessage(validating: value)
    } catch {
        preconditionFailure("invalid generated warning message \(value): \(error)")
    }
}

private func referenceIsAcyclic(nodes: [HeistInvocationPath], edges: Set<HeistCallGraph.Edge>) -> Bool {
    var incomingCounts = Dictionary(uniqueKeysWithValues: nodes.map { ($0, 0) })
    edges.forEach { incomingCounts[$0.callee, default: 0] += 1 }
    let outgoing = Dictionary(grouping: edges, by: \.caller)
    var ready = incomingCounts.filter { $0.value == 0 }.map(\.key).sorted { $0.description < $1.description }
    var visited: [HeistInvocationPath] = []

    while let next = ready.first {
        ready.removeFirst()
        visited.append(next)
        for callee in (outgoing[next] ?? []).map(\.callee).sorted(by: {
            $0.description < $1.description
        }) {
            incomingCounts[callee, default: 0] -= 1
            if incomingCounts[callee] == 0 {
                ready.append(callee)
                ready.sort { $0.description < $1.description }
            }
        }
    }

    return visited.count == nodes.count
}

private struct RandomDefinitionGraph {
    let nodes: [HeistInvocationPath]
    let edges: Set<HeistCallGraph.Edge>

    init(caseIndex: Int, rng: inout some RandomNumberGenerator) throws {
        let count = Int.random(in: 1...8, using: &rng)
        let generatedNodes = try (0..<count).map { index in
            try HeistInvocationPath(validating: "N\(index)")
        }
        let plantsCycle = count > 1 && caseIndex.isMultiple(of: 3)
        let generatedEdges = generatedNodes.enumerated().flatMap { callerIndex, caller in
            generatedNodes.enumerated().compactMap { calleeIndex, callee -> HeistCallGraph.Edge? in
                guard caller != callee else { return nil }
                if plantsCycle, callerIndex < 3, calleeIndex == (callerIndex + 1) % min(3, count) {
                    return HeistCallGraph.Edge(caller: caller, callee: callee)
                }
                guard !plantsCycle || callerIndex >= min(3, count) || calleeIndex >= min(3, count) else {
                    return nil
                }
                guard calleeIndex > callerIndex, Bool.random(using: &rng) else { return nil }
                return HeistCallGraph.Edge(caller: caller, callee: callee)
            }
        }
        nodes = generatedNodes
        edges = Set(generatedEdges)
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        return state
    }
}

private extension HeistCallGraph {
    func requireTopologicalOrder() throws -> [HeistInvocationPath] {
        switch topologicalOrder() {
        case .success(let order):
            return order
        case .failure(let cycle):
            Issue.record("Expected topological order, got cycle \(cycle.displayPath)")
            return []
        }
    }

    func requireCycle() -> HeistCallGraph.Cycle {
        switch topologicalOrder() {
        case .success(let order):
            Issue.record("Expected cycle, got order \(order)")
            return HeistCallGraph.Cycle(path: [])
        case .failure(let cycle):
            return cycle
        }
    }
}

private extension Array where Element == HeistInvocationPath {
    func respects(_ edges: Set<HeistCallGraph.Edge>) -> Bool {
        let indexByNode = Dictionary(uniqueKeysWithValues: enumerated().map { ($0.element, $0.offset) })
        return edges.allSatisfy { edge in
            guard let callerIndex = indexByNode[edge.caller],
                  let calleeIndex = indexByNode[edge.callee]
            else { return false }
            return callerIndex < calleeIndex
        }
    }

    func adjacentPairs() -> [(HeistInvocationPath, HeistInvocationPath)] {
        guard count >= 2 else { return [] }
        return zip(self, dropFirst()).map { ($0.0, $0.1) }
    }
}
