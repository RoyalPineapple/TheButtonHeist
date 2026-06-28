import Foundation
import Testing
@_spi(ButtonHeistInternals) @testable import ThePlans

private struct EncodedInvocationStepContract: Decodable {
    let path: [String]
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

@Test func `plan call graph resolves invocations in their definition scope`() throws {
    let raw = HeistPlanAdmissionCandidate(definitions: [
        HeistPlanAdmissionCandidate(name: "Cart", definitions: [
            HeistPlanAdmissionCandidate(name: "addToCart", definitions: [
                HeistPlanAdmissionCandidate(name: "tapAddButton", body: [
                    .warn(WarnStep(message: "tap")),
                ]),
            ], body: [
                .invoke(HeistInvocationStep(path: ["tapAddButton"])),
            ]),
        ], body: []),
    ], body: [.warn(WarnStep(message: "root"))])

    let graph = HeistCallGraph(plan: raw.uncheckedPlanForRuntimeSafetyValidation())

    #expect(graph.nodes == ["Cart", "Cart.addToCart", "Cart.addToCart.tapAddButton"])
    #expect(graph.edges == [
        HeistCallGraph.Edge(caller: "Cart.addToCart", callee: "Cart.addToCart.tapAddButton"),
    ])
}

@Test func `plan call graph resolves qualified exported namespace invocations from definition bodies`() throws {
    let typedPath = try HeistInvocationPath(dottedName: "lib.b")
    let raw = HeistPlanAdmissionCandidate(definitions: [
        HeistPlanAdmissionCandidate(name: "lib", definitions: [
            HeistPlanAdmissionCandidate(name: "a", body: [
                .invoke(HeistInvocationStep(invocationPath: typedPath)),
            ]),
            HeistPlanAdmissionCandidate(name: "b", body: [
                .warn(WarnStep(message: "b")),
            ]),
        ], body: []),
    ], body: [.invoke(HeistInvocationStep(path: ["lib", "a"]))])

    let graph = HeistCallGraph(plan: raw.uncheckedPlanForRuntimeSafetyValidation())

    #expect(graph.edges.contains(HeistCallGraph.Edge(caller: "lib.a", callee: "lib.b")))
}

@Test func `typed invocation path renders dotted names without changing invoke JSON`() throws {
    let invocationPath = try HeistInvocationPath(dottedName: "LibraryScreen.addToCart")
    let invocation = HeistInvocationStep(invocationPath: invocationPath)

    #expect(invocation.path == ["LibraryScreen", "addToCart"])
    #expect(invocation.capabilityName == "LibraryScreen.addToCart")

    let encoded = try JSONEncoder().encode(invocation)
    let json = try JSONDecoder().decode(EncodedInvocationStepContract.self, from: encoded)
    #expect(json.path == ["LibraryScreen", "addToCart"])

    let decoded = try JSONDecoder().decode(HeistInvocationStep.self, from: encoded)
    #expect(decoded == invocation)
    #expect(decoded.capabilityName == "LibraryScreen.addToCart")
}

@Test func `typed invocation path rejects empty path and components`() throws {
    expectInvocationPathFailure(.emptyPath) {
        _ = try HeistInvocationPath(components: [])
    }
    expectInvocationPathFailure(.emptyPath) {
        _ = try HeistInvocationPath(dottedName: "")
    }
    expectInvocationPathFailure(.emptyComponent(index: 1)) {
        _ = try HeistInvocationPath(components: ["LibraryScreen", ""])
    }
    expectInvocationPathFailure(.emptyComponent(index: 1)) {
        _ = try HeistInvocationPath(dottedName: "LibraryScreen..addToCart")
    }
}

@Test func `invocation step decode rejects empty path and components`() throws {
    expectDataCorrupted("empty invocation path", contains: "heist invocation path must not be empty") {
        _ = try JSONDecoder().decode(HeistInvocationStep.self, from: Data("""
        { "path": [] }
        """.utf8))
    }

    expectDataCorrupted("empty invocation path component", contains: "component at index 1 must not be empty") {
        _ = try JSONDecoder().decode(HeistInvocationStep.self, from: Data("""
        { "path": [ "LibraryScreen", "" ] }
        """.utf8))
    }
}

@Test func `random generated definition graphs agree with reference cycle checker`() throws {
    var rng = SeededGenerator(seed: 0xAC1DCA11)

    for caseIndex in 0..<200 {
        let model = RandomDefinitionGraph(caseIndex: caseIndex, rng: &rng)
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

@Test func `runtime admission recursive failures match call graph cycle witnesses`() throws {
    let cases: [HeistPlanAdmissionCandidate] = [
        rawInlineChain(["A", "B", "C"]),
        rawInlineCycle(["A"]),
        rawInlineCycle(["A", "B"]),
        rawInlineCycle(["A", "B", "C"]),
    ]

    for raw in cases {
        let graph = HeistCallGraph(plan: raw.uncheckedPlanForRuntimeSafetyValidation())
        let recursiveFailures = runtimeSafetyFailures(for: raw).filter {
            $0.contract == recursiveHeistRunContract
        }

        switch graph.topologicalOrder() {
        case .success:
            #expect(recursiveFailures.isEmpty)
        case .failure(let cycle):
            #expect(!recursiveFailures.isEmpty)
            #expect(Set(recursiveFailures.map(\.contract)) == [recursiveHeistRunContract])
            #expect(Set(recursiveFailures.map(\.observed)) == [cycle.displayPath])
            #expect(Set(recursiveFailures.map(\.correction)) == [recursiveHeistRunCorrection])
        }
    }
}

private let recursiveHeistRunContract = "heist runs must not be recursive"
private let recursiveHeistRunCorrection = "Remove the recursive heist run cycle."

private func callGraph(edges: [(String, String)]) -> HeistCallGraph {
    HeistCallGraph(
        nodes: Set(edges.flatMap { [$0.0, $0.1] }),
        edges: Set(edges.map { HeistCallGraph.Edge(caller: $0.0, callee: $0.1) })
    )
}

private func rawInlineChain(_ names: [String]) -> HeistPlanAdmissionCandidate {
    let definition = inlineChainDefinition(names)
    return HeistPlanAdmissionCandidate(definitions: [HeistPlanAdmissionCandidate(definition)], body: [
        .invoke(HeistInvocationStep(path: [definition.name ?? ""])),
    ])
}

private func rawInlineCycle(_ names: [String]) -> HeistPlanAdmissionCandidate {
    guard let first = names.first else {
        return HeistPlanAdmissionCandidate(body: [.warn(WarnStep(message: "empty"))])
    }
    let definition = inlineCycleDefinition(name: first, remaining: Array(names.dropFirst()), first: first)
    return HeistPlanAdmissionCandidate(definitions: [HeistPlanAdmissionCandidate(definition)], body: [
        .invoke(HeistInvocationStep(path: [first])),
    ])
}

private func inlineChainDefinition(_ names: [String]) -> HeistPlan {
    guard let name = names.first else {
        return uncheckedDefinition(name: "empty", body: [.warn(WarnStep(message: "empty"))])
    }
    guard names.count > 1 else {
        return uncheckedDefinition(name: name, body: [.warn(WarnStep(message: "\(name) done"))])
    }
    let next = inlineChainDefinition(Array(names.dropFirst()))
    return uncheckedDefinition(name: name, body: [
        inlineHeist(definitions: [next], body: [
            .invoke(HeistInvocationStep(path: [next.name ?? ""])),
        ]),
    ])
}

private func inlineCycleDefinition(name: String, remaining: [String], first: String) -> HeistPlan {
    let next = remaining.first.map { nextName in
        inlineCycleDefinition(name: nextName, remaining: Array(remaining.dropFirst()), first: first)
    } ?? uncheckedDefinition(name: first, body: [.warn(WarnStep(message: "\(first) done"))])
    return uncheckedDefinition(name: name, body: [
        inlineHeist(definitions: [next], body: [
            .invoke(HeistInvocationStep(path: [next.name ?? first])),
        ]),
    ])
}

private func uncheckedDefinition(name: String, body: [HeistStep]) -> HeistPlan {
    HeistPlan(runtimeValidatedVersion: HeistPlan.currentVersion, name: name, body: body)
}

private func inlineHeist(definitions: [HeistPlan], body: [HeistStep]) -> HeistStep {
    .heist(HeistPlan(runtimeValidatedVersion: HeistPlan.currentVersion, definitions: definitions, body: body))
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

private func expectInvocationPathFailure(
    _ expected: HeistInvocationPath.ValidationError,
    _ body: () throws -> Void
) {
    do {
        try body()
        Issue.record("Expected invocation path construction to fail")
    } catch let error as HeistInvocationPath.ValidationError {
        #expect(error == expected)
    } catch {
        Issue.record("Expected invocation path validation error, got \(error)")
    }
}

private func expectDataCorrupted(
    _ name: String,
    contains expectedMessage: String,
    decode: () throws -> Void
) {
    do {
        try decode()
        Issue.record("Expected \(name) to reject invalid JSON")
    } catch DecodingError.dataCorrupted(let context) {
        #expect(
            context.debugDescription.contains(expectedMessage),
            "\(name) error \(context.debugDescription) did not contain \(expectedMessage)"
        )
    } catch {
        Issue.record("Expected \(name) to throw DecodingError.dataCorrupted, got \(error)")
    }
}

private func referenceIsAcyclic(nodes: [String], edges: Set<HeistCallGraph.Edge>) -> Bool {
    var incomingCounts = Dictionary(uniqueKeysWithValues: nodes.map { ($0, 0) })
    edges.forEach { incomingCounts[$0.callee, default: 0] += 1 }
    let outgoing = Dictionary(grouping: edges, by: \.caller)
    var ready = incomingCounts.filter { $0.value == 0 }.map(\.key).sorted()
    var visited: [String] = []

    while let next = ready.first {
        ready.removeFirst()
        visited.append(next)
        for callee in (outgoing[next] ?? []).map(\.callee).sorted() {
            incomingCounts[callee, default: 0] -= 1
            if incomingCounts[callee] == 0 {
                ready.append(callee)
                ready.sort()
            }
        }
    }

    return visited.count == nodes.count
}

private struct RandomDefinitionGraph {
    let nodes: [String]
    let edges: Set<HeistCallGraph.Edge>

    init(caseIndex: Int, rng: inout some RandomNumberGenerator) {
        let count = Int.random(in: 1...8, using: &rng)
        let generatedNodes = (0..<count).map { "N\($0)" }
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
    func requireTopologicalOrder() throws -> [String] {
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

private extension Array where Element == String {
    func respects(_ edges: Set<HeistCallGraph.Edge>) -> Bool {
        let indexByNode = Dictionary(uniqueKeysWithValues: enumerated().map { ($0.element, $0.offset) })
        return edges.allSatisfy { edge in
            guard let callerIndex = indexByNode[edge.caller],
                  let calleeIndex = indexByNode[edge.callee]
            else { return false }
            return callerIndex < calleeIndex
        }
    }

    func adjacentPairs() -> [(String, String)] {
        guard count >= 2 else { return [] }
        return zip(self, dropFirst()).map { ($0.0, $0.1) }
    }
}
