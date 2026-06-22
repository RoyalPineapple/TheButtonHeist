import Foundation
import Testing
@_spi(ButtonHeistInternals) import ThePlans

@Test
func `representative heist plan encodes decodes validates and renders`() throws {
    let plan = try HeistPlan("loginFlow") {
        TypeText("alex@example.com", into: .identifier("email"))
            .expect(.present(.value("alex@example.com")), timeout: .seconds(1))

        Activate(.label("Submit"))
            .expect(.changed(.screen()))
            .expect(.present(.label("Home")), timeout: .seconds(5))

        WaitFor(.absent(.label("Loading")), timeout: .seconds(1))

        If {
            Case(.present(.label("Promo"))) {
                Warn("promo visible")
            }

            Else {
                Warn("promo skipped")
            }
        }
    }

    let data = try JSONEncoder().encode(plan)
    let decoded = try JSONDecoder().decode(HeistPlan.self, from: data)

    #expect(decoded == plan)
    #expect(decoded.lint(.strictTest).isEmpty)

    let rendered = try decoded.canonicalSwiftDSL()
    #expect(rendered.contains(#"HeistPlan("loginFlow")"#))
    #expect(rendered.contains(#"TypeText("alex@example.com", into: .identifier("email"))"#))
    #expect(rendered.contains(#"Activate(.label("Submit"))"#))
}

@Test
func `heist artifact package writes manifest and canonical plan`() throws {
    let temp = try PlansTemporaryDirectory()
    let artifactURL = temp.url.appendingPathComponent("SearchFlow.heist")
    let plan = try representativeArtifactPlan()

    try HeistArtifactCodec.writePlan(plan, to: artifactURL)

    var isDirectory: ObjCBool = false
    #expect(FileManager.default.fileExists(atPath: artifactURL.path, isDirectory: &isDirectory))
    #expect(isDirectory.boolValue)

    let manifestURL = artifactURL.appendingPathComponent("manifest.json")
    let planURL = artifactURL.appendingPathComponent("plan.json")
    #expect(FileManager.default.fileExists(atPath: manifestURL.path))
    #expect(FileManager.default.fileExists(atPath: planURL.path))

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let manifest = try decoder.decode(HeistArtifactManifest.self, from: Data(contentsOf: manifestURL))
    #expect(manifest.format == heistArtifactFormat)
    #expect(manifest.entry == "searchFlow")
    #expect(manifest.entry == plan.name)
    #expect(manifest.formatVersion == currentHeistArtifactFormatVersion)
    #expect(manifest.planVersion == currentHeistPlanVersion)

    let planObject = try JSONSerialization.jsonObject(with: Data(contentsOf: planURL)) as? [String: Any]
    #expect(planObject?["version"] as? Int == currentHeistPlanVersion)
    #expect(planObject?["name"] as? String == "searchFlow")
    #expect(try HeistArtifactCodec.readPlan(from: artifactURL) == plan)
    #expect(try HeistArtifactCodec.read(from: artifactURL).manifest.entry == "searchFlow")
}

@Test
func `heist artifact entry uses root plan name not output path`() throws {
    let temp = try PlansTemporaryDirectory()
    let artifactURL = temp.url.appendingPathComponent("CompletelyDifferent.heist")
    let plan = try representativeArtifactPlan()

    try HeistArtifactCodec.writePlan(plan, to: artifactURL)

    let artifact = try HeistArtifactCodec.read(from: artifactURL)
    #expect(artifact.manifest.entry == "searchFlow")
    #expect(artifact.plan.name == "searchFlow")
}

@Test
func `public artifact plan helpers reject standalone raw plan json`() throws {
    let temp = try PlansTemporaryDirectory()
    let jsonURL = temp.url.appendingPathComponent("SearchFlow.json")
    let plan = try HeistPlan(body: [.warn(WarnStep(message: "raw unnamed IR"))])

    try plan.canonicalHeistJSONData().write(to: jsonURL)

    #expect(throws: HeistArtifactCodecError.self) {
        try HeistArtifactCodec.readPlan(from: jsonURL)
    }
    #expect(throws: HeistArtifactCodecError.self) {
        try HeistArtifactCodec.writePlan(plan, to: jsonURL)
    }
}

@Test
func `heist planning loads generated heist artifact source`() throws {
    let temp = try PlansTemporaryDirectory()
    let artifactURL = temp.url.appendingPathComponent("SearchFlow.heist")
    let plan = try representativeArtifactPlan()
    try HeistArtifactCodec.writePlan(plan, to: artifactURL)

    let loaded = try HeistPlanning.loadValidatedPlan(from: HeistPlanSourceRequest(
        commandName: "run_heist",
        path: artifactURL.path
    ))

    #expect(loaded == plan)
}

@Test
func `heist planning compiles inline ButtonHeist DSL source`() throws {
    let loaded = try HeistPlanning.loadValidatedPlan(from: HeistPlanSourceRequest(
        commandName: "run_heist",
        inlineButtonHeistSource: """
        HeistPlan("sourceFlow") {
            Warn("from source")
        }
        """
    ))

    #expect(loaded.name == "sourceFlow")
    #expect(loaded.body == [.warn(WarnStep(message: "from source"))])
}

@Test
func `heist planning rejects standalone raw json path as public source`() throws {
    let temp = try PlansTemporaryDirectory()
    let jsonURL = temp.url.appendingPathComponent("SearchFlow.json")
    try representativeArtifactPlan().canonicalHeistJSONData().write(to: jsonURL)

    do {
        _ = try HeistPlanning.loadValidatedPlan(from: HeistPlanSourceRequest(
            commandName: "run_heist",
            path: jsonURL.path
        ))
        Issue.record("Expected standalone raw JSON path to fail")
    } catch {
        #expect(String(describing: error).contains("raw `.json` HeistPlan IR"))
        #expect(String(describing: error).contains("not public run input"))
    }
}

@Test
func `heist planning rejects raw structured JSON IR fields as public source`() throws {
    do {
        _ = try HeistPlanning.loadValidatedPlan(from: HeistPlanSourceRequest(
            commandName: "run_heist",
            rawStructuredJSONIRFields: ["version", "body"]
        ))
        Issue.record("Expected raw structured JSON fields to fail")
    } catch {
        #expect(String(describing: error).contains("raw JSON HeistPlan IR field"))
        #expect(String(describing: error).contains("ButtonHeist DSL"))
        #expect(String(describing: error).contains(".heist"))
    }
}

@Test
func `raw JSON with heist extension fails`() throws {
    let temp = try PlansTemporaryDirectory()
    let artifactURL = temp.url.appendingPathComponent("SearchFlow.heist")
    try representativeArtifactPlan().canonicalHeistJSONData().write(to: artifactURL)

    #expect(throws: HeistArtifactCodecError.self) {
        try HeistArtifactCodec.readPlan(from: artifactURL)
    }
}

@Test
func `heist artifact requires manifest and plan members`() throws {
    let temp = try PlansTemporaryDirectory()
    let missingManifestURL = temp.url.appendingPathComponent("MissingManifest.heist")
    try FileManager.default.createDirectory(at: missingManifestURL, withIntermediateDirectories: true)
    try representativeArtifactPlan().canonicalHeistJSONData()
        .write(to: missingManifestURL.appendingPathComponent("plan.json"))

    #expect(throws: HeistArtifactCodecError.self) {
        try HeistArtifactCodec.read(from: missingManifestURL)
    }

    let missingPlanURL = temp.url.appendingPathComponent("MissingPlan.heist")
    try FileManager.default.createDirectory(at: missingPlanURL, withIntermediateDirectories: true)
    try HeistArtifactCodec.canonicalManifestJSONData(validArtifactManifest())
        .write(to: missingPlanURL.appendingPathComponent("manifest.json"))

    #expect(throws: HeistArtifactCodecError.self) {
        try HeistArtifactCodec.read(from: missingPlanURL)
    }
}

@Test
func `heist artifact validates manifest and plan versions`() throws {
    let temp = try PlansTemporaryDirectory()

    try writePackage(
        named: "InvalidFormat.heist",
        in: temp.url,
        manifest: HeistArtifactManifest(
            format: "not.buttonheist",
            entry: "searchFlow",
            formatVersion: currentHeistArtifactFormatVersion,
            planVersion: currentHeistPlanVersion,
            producer: .buttonHeist,
            createdAt: Date(timeIntervalSince1970: 0)
        ),
        planJSON: representativeArtifactPlan().canonicalHeistJSONData()
    ) { url in
        #expect(throws: HeistArtifactCodecError.self) {
            try HeistArtifactCodec.read(from: url)
        }
    }

    try writePackage(
        named: "UnsupportedArtifact.heist",
        in: temp.url,
        manifest: HeistArtifactManifest(
            format: heistArtifactFormat,
            entry: "searchFlow",
            formatVersion: 2,
            planVersion: currentHeistPlanVersion,
            producer: .buttonHeist,
            createdAt: Date(timeIntervalSince1970: 0)
        ),
        planJSON: representativeArtifactPlan().canonicalHeistJSONData()
    ) { url in
        #expect(throws: HeistArtifactCodecError.self) {
            try HeistArtifactCodec.read(from: url)
        }
    }

    try writePackage(
        named: "MissingPlanVersion.heist",
        in: temp.url,
        manifest: validArtifactManifest(),
        planJSON: Data(#"{"body":[{"type":"warn","warn":{"message":"missing version"}}]}"#.utf8)
    ) { url in
        #expect(throws: HeistArtifactCodecError.self) {
            try HeistArtifactCodec.read(from: url)
        }
    }

    try writePackage(
        named: "UnsupportedPlanVersion.heist",
        in: temp.url,
        manifest: HeistArtifactManifest(
            format: heistArtifactFormat,
            entry: "searchFlow",
            formatVersion: currentHeistArtifactFormatVersion,
            planVersion: 2,
            producer: .buttonHeist,
            createdAt: Date(timeIntervalSince1970: 0)
        ),
        planJSON: Data(#"{"version":2,"body":[{"type":"warn","warn":{"message":"new version"}}]}"#.utf8)
    ) { url in
        #expect(throws: HeistArtifactCodecError.self) {
            try HeistArtifactCodec.read(from: url)
        }
    }

    try writePackage(
        named: "Mismatch.heist",
        in: temp.url,
        manifest: validArtifactManifest(),
        planJSON: Data(#"{"version":2,"body":[{"type":"warn","warn":{"message":"mismatch"}}]}"#.utf8)
    ) { url in
        do {
            _ = try HeistArtifactCodec.read(from: url)
            Issue.record("Expected version mismatch")
        } catch {
            #expect(String(describing: error).contains("manifest planVersion 1 does not match plan version 2"))
        }
    }
}

@Test
func `heist artifact validates required entry against root plan name`() throws {
    let temp = try PlansTemporaryDirectory()
    let plan = try representativeArtifactPlan()
    let planJSON = try plan.canonicalHeistJSONData()

    try writePackage(
        named: "MissingEntry.heist",
        in: temp.url,
        manifestJSON: rawArtifactManifestJSON(entry: nil),
        planJSON: planJSON
    ) { url in
        try expectArtifactReadError(
            from: url,
            containing: [
                "manifest entry contract failed",
                "observed missing entry",
                #"Set manifest.json entry to "searchFlow""#,
            ]
        )
    }

    try writePackage(
        named: "EmptyEntry.heist",
        in: temp.url,
        manifest: validArtifactManifest(entry: ""),
        planJSON: planJSON
    ) { url in
        try expectArtifactReadError(
            from: url,
            containing: [
                "entry must be non-empty",
                "observed empty string",
                #"Set manifest.json entry to "searchFlow""#,
            ]
        )
    }

    try writePackage(
        named: "WrongEntry.heist",
        in: temp.url,
        manifest: validArtifactManifest(entry: "otherFlow"),
        planJSON: planJSON
    ) { url in
        try expectArtifactReadError(
            from: url,
            containing: [
                "entry must equal the root HeistPlan.name",
                #"entry "otherFlow" with root plan name "searchFlow""#,
                "definition name",
            ]
        )
    }
}

@Test
func `heist artifact accepts parameterized root entry through validation contract`() throws {
    let temp = try PlansTemporaryDirectory()
    let raw = HeistPlanAdmissionCandidate(
        name: "search",
        parameter: .string(name: "query"),
        body: [.action(try ActionStep(command: .typeText(
            text: .ref("query"),
            target: .target(.predicate(.label("Search")))
        )))]
    )

    try writePackage(
        named: "ParameterizedRoot.heist",
        in: temp.url,
        manifest: validArtifactManifest(entry: "search"),
        planJSON: try JSONEncoder().encode(raw)
    ) { url in
        let plan = try HeistArtifactCodec.readPlan(from: url)
        #expect(plan.name == "search")
        #expect(plan.parameter.kind == .string)
    }
}

@Test
func `heist artifact loading rejects standard definition cap`() throws {
    let temp = try PlansTemporaryDirectory()
    let definitions = (0...250).map { index in
        HeistPlanAdmissionCandidate(name: "definition\(index)", body: [
            .warn(WarnStep(message: "definition \(index)")),
        ])
    }
    let raw = HeistPlanAdmissionCandidate(
        name: "tooManyDefinitions",
        definitions: definitions,
        body: [.warn(WarnStep(message: "body"))]
    )

    try writePackage(
        named: "TooManyDefinitions.heist",
        in: temp.url,
        manifest: validArtifactManifest(entry: "tooManyDefinitions"),
        planJSON: try JSONEncoder().encode(raw)
    ) { url in
        do {
            _ = try HeistArtifactCodec.readPlan(from: url)
            Issue.record("Expected artifact loading to reject too many definitions")
        } catch {
            let diagnostic = String(describing: error)
            #expect(diagnostic.contains("max total heist definitions"))
            #expect(diagnostic.contains("251 definitions"))
        }
    }
}

@Test
func `thePlans does not import runtime or adapter modules`() throws {
    let testFile = URL(fileURLWithPath: #filePath)
    let sources = testFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/ThePlans")
    let forbiddenImports = [
        "TheFence",
        "TheInsideJob",
        "ButtonHeist",
        "ButtonHeistCLI",
        "ButtonHeistMCP",
        "TheScore",
        "MCP",
        "ArgumentParser",
        "AccessibilitySnapshotModel",
    ]

    let files = try FileManager.default
        .contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "swift" }

    for file in files {
        let source = try String(contentsOf: file, encoding: .utf8)
        for forbiddenImport in forbiddenImports {
            #expect(!source.contains("import \(forbiddenImport)"), "\(file.lastPathComponent) imports \(forbiddenImport)")
        }
    }
}

private func representativeArtifactPlan() throws -> HeistPlan {
    try HeistPlan("searchFlow") {
        Warn("check state")
    }
}

private func validArtifactManifest() -> HeistArtifactManifest {
    validArtifactManifest(entry: "searchFlow")
}

private func validArtifactManifest(entry: String) -> HeistArtifactManifest {
    HeistArtifactManifest(
        format: heistArtifactFormat,
        entry: entry,
        formatVersion: currentHeistArtifactFormatVersion,
        planVersion: currentHeistPlanVersion,
        producer: .buttonHeist,
        createdAt: Date(timeIntervalSince1970: 0)
    )
}

private func writePackage(
    named name: String,
    in directory: URL,
    manifest: HeistArtifactManifest,
    planJSON: Data,
    validate: (URL) throws -> Void
) throws {
    try writePackage(
        named: name,
        in: directory,
        manifestJSON: HeistArtifactCodec.canonicalManifestJSONData(manifest),
        planJSON: planJSON,
        validate: validate
    )
}

private func writePackage(
    named name: String,
    in directory: URL,
    manifestJSON: Data,
    planJSON: Data,
    validate: (URL) throws -> Void
) throws {
    let packageURL = directory.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
    try manifestJSON.write(to: packageURL.appendingPathComponent("manifest.json"))
    try planJSON.write(to: packageURL.appendingPathComponent("plan.json"))
    try validate(packageURL)
}

private func rawArtifactManifestJSON(entry: String?) -> Data {
    var fields = [
        #"  "createdAt" : "2026-06-05T00:00:00Z""#,
        #"  "format" : "com.royalpineapple.buttonheist.heist""#,
        #"  "formatVersion" : 1"#,
        #"  "planVersion" : 1"#,
        #"  "producer" : { "name" : "buttonheist" }"#,
    ]
    if let entry {
        fields.insert(#"  "entry" : "\#(entry)""#, at: 1)
    }
    return Data(("{\n" + fields.joined(separator: ",\n") + "\n}\n").utf8)
}

private func expectArtifactReadError(from url: URL, containing substrings: [String]) throws {
    do {
        _ = try HeistArtifactCodec.read(from: url)
        Issue.record("Expected artifact read to fail")
    } catch {
        let description = String(describing: error)
        for substring in substrings {
            #expect(description.contains(substring), "\(description) did not contain \(substring)")
        }
    }
}

private final class PlansTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("theplans-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
