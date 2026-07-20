import Foundation
import Testing
@_spi(ButtonHeistInternals) import ThePlans

@Test
func `all heist step kinds round trip through canonical JSON bytes`() throws {
    let plan = try representativeAllStepKindsPlan()
    let encoded = try plan.canonicalHeistJSONData()

    let decoded = try JSONDecoder().decode(HeistPlan.self, from: encoded)
    #expect(decoded == plan)
    #expect(try decoded.canonicalHeistJSONData() == encoded)
    #expect(decoded.body.map(stepKind) == [
        "action",
        "wait",
        "conditional",
        "for_each_element",
        "for_each_string",
        "repeat_until",
        "warn",
        "fail",
        "heist",
        "invoke",
    ])
}

@Test
func `checked in heist fixtures use canonical JSON contracts`() throws {
    let fixtureURLs = try heistArtifactFixtureURLs()
    if fixtureURLs.isEmpty {
        Issue.record("Expected at least one checked-in .heist fixture")
    }

    for fixtureURL in fixtureURLs {
        let artifact = try HeistArtifactCodec.read(from: fixtureURL)
        try expectCanonicalJSON(
            at: fixtureURL.appendingPathComponent(HeistArtifactCodec.manifestFileName, isDirectory: false),
            expectedData: HeistArtifactCodec.canonicalManifestJSONData(artifact.manifest)
        )
        try expectCanonicalJSON(
            at: fixtureURL.appendingPathComponent(HeistArtifactCodec.planFileName, isDirectory: false),
            expectedData: artifact.plan.canonicalHeistJSONData()
        )
    }
}

private func heistArtifactFixtureURLs() throws -> [URL] {
    let fixturesURL = repositoryRootURL()
        .appendingPathComponent("tests", isDirectory: true)
        .appendingPathComponent("fixtures", isDirectory: true)
    let enumerator = FileManager.default.enumerator(
        at: fixturesURL,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    )
    return try (enumerator?.compactMap { entry -> URL? in
        guard let url = entry as? URL,
              url.pathExtension == "heist"
        else {
            return nil
        }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        return values.isDirectory == true ? url : nil
    } ?? [])
    .sorted { $0.path < $1.path }
}

private func repositoryRootURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func expectCanonicalJSON(at url: URL, expectedData: Data) throws {
    let actualData = try Data(contentsOf: url)
    let actualJSON = try canonicalJSONObjectData(from: actualData)
    let expectedJSON = try canonicalJSONObjectData(from: expectedData)
    #expect(actualJSON == expectedJSON, "\(url.path) must use Button Heist's canonical JSON encoding")
}

private func canonicalJSONObjectData(from data: Data) throws -> Data {
    let object = try JSONSerialization.jsonObject(with: data, options: [])
    return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

private func representativeAllStepKindsPlan() throws -> HeistPlan {
    let searchDefinition = try HeistPlan(
        name: "Search",
        parameter: .string(name: "query"),
        body: [
            .action(ActionStep(command: .typeText(
                reference: "query",
                target: .predicate(.label("Search"))
            ))),
        ]
    )

    return try HeistPlan(
        name: "wireAllSteps",
        definitions: [searchDefinition],
        body: [
            .action(ActionStep(
                command: .activate(.predicate(.label("Pay"))),
                expectationPolicy: .expect(ActionExpectation(predicate: .changed(.screen()), timeout: 0.001)))),
            .wait(WaitStep(predicate: .exists(.label("Home")), timeout: 1)),
            .conditional(try ConditionalStep(
                cases: [
                    PredicateCase(predicate: .exists(.label("Promo")), body: [
                        .warn(WarnStep(message: "promo visible")),
                    ]),
                ],
                elseBody: [
                    .fail(FailStep(message: "promo missing")),
                ]
            )),
            .forEachElement(try ForEachElementStep(
                matching: .element(.label("Delete"), .traits([.button])),
                limit: 2,
                parameter: "row",
                body: [
                    .action(ActionStep(
                        command: .activate(.ref("row")),
                        expectationPolicy: .expect(ActionExpectation(predicate: .missing(.ref("row")), timeout: 2)))),
                ]
            )),
            .forEachString(try ForEachStringStep(
                values: ["Milk", "Eggs"],
                parameter: "item",
                body: [
                    .action(ActionStep(command: .typeText(
                        reference: "item",
                        target: .predicate(.label("Search"))
                    ))),
                ]
            )),
            .repeatUntil(try RepeatUntilStep(
                predicate: .exists(.label("Ready")),
                timeout: 2,
                body: [
                    .warn(WarnStep(message: "retry")),
                ]
            )),
            .warn(WarnStep(message: "checkpoint")),
            .fail(FailStep(message: "stop here")),
            .heist(try HeistPlan(body: [
                .warn(WarnStep(message: "inline group")),
            ])),
            .invoke(HeistInvocationStep(
                path: "Search",
                argument: .string("Milk")
            )),
        ]
    )
}

private func stepKind(_ step: HeistStep) -> String {
    switch step {
    case .action:
        return "action"
    case .wait:
        return "wait"
    case .conditional:
        return "conditional"
    case .forEachElement:
        return "for_each_element"
    case .forEachString:
        return "for_each_string"
    case .repeatUntil:
        return "repeat_until"
    case .warn:
        return "warn"
    case .fail:
        return "fail"
    case .heist:
        return "heist"
    case .invoke:
        return "invoke"
    }
}
