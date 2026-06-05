import Foundation
import Testing
import ThePlans

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
    #expect(decoded.runtimeAdmissionFailures().isEmpty)
    #expect(decoded.lint(.strictTest).isEmpty)

    let rendered = try decoded.canonicalSwiftDSL()
    #expect(rendered.contains(#"try HeistPlan("loginFlow")"#))
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
    #expect(manifest.formatVersion == currentHeistArtifactFormatVersion)
    #expect(manifest.planVersion == currentHeistPlanVersion)

    let planObject = try JSONSerialization.jsonObject(with: Data(contentsOf: planURL)) as? [String: Any]
    #expect(planObject?["version"] as? Int == currentHeistPlanVersion)
    #expect(try HeistArtifactCodec.readPlan(from: artifactURL) == plan)
}

@Test
func `json heist plan IR reads as raw plan`() throws {
    let temp = try PlansTemporaryDirectory()
    let jsonURL = temp.url.appendingPathComponent("SearchFlow.json")
    let plan = try representativeArtifactPlan()

    try HeistArtifactCodec.writePlan(plan, to: jsonURL)

    #expect(try HeistArtifactCodec.readPlan(from: jsonURL) == plan)
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
    HeistArtifactManifest(
        format: heistArtifactFormat,
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
    let packageURL = directory.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
    try HeistArtifactCodec.canonicalManifestJSONData(manifest)
        .write(to: packageURL.appendingPathComponent("manifest.json"))
    try planJSON.write(to: packageURL.appendingPathComponent("plan.json"))
    try validate(packageURL)
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
