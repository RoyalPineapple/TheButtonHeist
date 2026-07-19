import Foundation
import Testing
@_spi(ButtonHeistInternals) import ThePlans

private struct EncodedHeistPlanHeaderContract: Decodable {
    let version: Int
    let name: String
}

@Test func `artifact format has one canonical wire spelling`() throws {
    let encoded = try JSONEncoder().encode(HeistArtifactFormat.buttonHeist)

    #expect(HeistArtifactFormat.allCases == [.buttonHeist])
    #expect(String(bytes: encoded, encoding: .utf8) == #""com.royalpineapple.buttonheist.heist""#)
}

@Test func `artifact producer name is typed open vocabulary metadata`() throws {
    let producer = HeistArtifactProducer(name: "third-party-compiler", version: "4.2")
    let encoded = try JSONEncoder().encode(producer)
    let decoded = try JSONDecoder().decode(HeistArtifactProducer.self, from: encoded)

    #expect(decoded == producer)
    #expect(decoded.name.description == "third-party-compiler")
    #expect(decoded.version?.description == "4.2")
}

@Test func `artifact producer values reject blank construction and decoding`() throws {
    #expect(throws: HeistArtifactProducerName.ValidationError.self) {
        try HeistArtifactProducerName(validating: " \n\t")
    }
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(HeistArtifactProducerName.self, from: Data(#"" \n\t""#.utf8))
    }
    #expect(throws: HeistArtifactProducerVersion.ValidationError.self) {
        try HeistArtifactProducerVersion(validating: " \n\t")
    }
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(HeistArtifactProducerVersion.self, from: Data(#"" \n\t""#.utf8))
    }
}

@Test
func `representative heist plan encodes decodes validates and renders`() throws {
    let plan = try HeistPlan("loginFlow") {
        TypeText("alex@example.com", into: .identifier("email"))
            .expect(.exists(.value("alex@example.com")), timeout: 1)

        Activate(.label("Submit"))
            .expect(.changed(.screen()))
            .expect(.exists(.label("Home")), timeout: 5)

        WaitFor(.missing(.label("Loading")), timeout: 1)

        If {
            Case(.exists(.label("Promo"))) {
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
    #expect(manifest.format == .buttonHeist)
    #expect(manifest.entry == "searchFlow")
    #expect(manifest.entry == plan.name)
    #expect(manifest.formatVersion == currentHeistArtifactFormatVersion)
    #expect(manifest.planVersion == currentHeistPlanVersion)

    let planObject = try JSONDecoder().decode(EncodedHeistPlanHeaderContract.self, from: Data(contentsOf: planURL))
    #expect(planObject.version == currentHeistPlanVersion)
    #expect(planObject.name == "searchFlow")
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
func `public artifact package helpers require heist extension`() throws {
    let temp = try PlansTemporaryDirectory()
    let packageURL = temp.url.appendingPathComponent("SearchFlow.package")
    let plan = try representativeArtifactPlan()

    #expect(throws: HeistArtifactCodecError.self) {
        try HeistArtifactCodec.write(HeistArtifact(plan: plan), to: packageURL)
    }
    #expect(throws: HeistArtifactCodecError.self) {
        _ = try HeistArtifactCodec.read(from: packageURL)
    }
}

@Test
func `plan loading loads generated heist artifact source`() throws {
    let temp = try PlansTemporaryDirectory()
    let artifactURL = temp.url.appendingPathComponent("SearchFlow.heist")
    let plan = try representativeArtifactPlan()
    try HeistArtifactCodec.writePlan(plan, to: artifactURL)

    let loaded = try #require(HeistPlanLoading.loadValidated(from: HeistPlanLoadRequest(
        commandName: "run_heist",
        source: .artifactPath(artifactURL.path)
    )).value)

    #expect(loaded == plan)
}

@Test
func `plan loading compiles inline ButtonHeist DSL source`() throws {
    let loaded = try #require(HeistPlanLoading.loadValidated(from: HeistPlanLoadRequest(
        commandName: "run_heist",
        source: .inlineDSL("""
        HeistPlan("sourceFlow") {
            Warn("from source")
        }
        """)
    )).value)

    #expect(loaded.name == "sourceFlow")
    #expect(loaded.body == [.warn(WarnStep(message: "from source"))])
}

@Test
func `plan source admission request carries one closed source`() throws {
    let artifact = try #require(HeistPlanSourceAdmission.request(
        commandName: "run_heist",
        path: "/tmp/SearchFlow.heist",
        inlineDSL: nil
    ).value)
    let inline = try #require(HeistPlanSourceAdmission.request(
        commandName: "run_heist",
        path: nil,
        inlineDSL: #"HeistPlan("sourceFlow") { Warn("from source") }"#
    ).value)

    #expect(artifact.source == .artifactPath("/tmp/SearchFlow.heist"))
    #expect(inline.source == .inlineDSL(#"HeistPlan("sourceFlow") { Warn("from source") }"#))
}

@Test
func `plan source admission raw IR keys map to a closed rejected field set`() throws {
    let fields = HeistPlanRejectedPublicSourceField.sourceFields(in: [
        "version",
        "path",
        "body",
        "argument",
    ])

    #expect(fields == [.version, .body])
}

@Test
func `plan source admission rejects missing public source`() throws {
    let result = HeistPlanSourceAdmission.request(
        commandName: "run_heist",
        path: nil,
        inlineDSL: nil
    )

    #expect(try #require(result.failureDiagnostics?.first).message.contains("requires exactly one plan source"))
}

@Test
func `plan source admission rejects multiple public sources`() throws {
    let result = HeistPlanSourceAdmission.request(
        commandName: "run_heist",
        path: "/tmp/SearchFlow.heist",
        inlineDSL: #"HeistPlan("searchFlow") { Warn("from source") }"#
    )

    #expect(try #require(result.failureDiagnostics?.first).message.contains("accepts exactly one plan source"))
}

@Test
func `plan source admission rejects inline source when policy is artifact only`() throws {
    let result = HeistPlanSourceAdmission.admit(from: HeistPlanSourceAdmissionRequest(
        commandName: "heist-plan",
        source: .inlineDSL(#"HeistPlan("searchFlow") { Warn("from source") }"#),
        sourcePolicy: .artifactOnly
    ))

    #expect(try #require(result.failureDiagnostics?.first).message.contains("does not accept inline ButtonHeist DSL source"))
}

@Test
func `plan loading rejects standalone raw json path as public source`() throws {
    let temp = try PlansTemporaryDirectory()
    let jsonURL = temp.url.appendingPathComponent("SearchFlow.json")
    try representativeArtifactPlan().canonicalHeistJSONData().write(to: jsonURL)

    let result = HeistPlanLoading.loadValidated(from: HeistPlanLoadRequest(
        commandName: "run_heist",
        source: .artifactPath(jsonURL.path)
    ))
    let message = try #require(result.failureDiagnostics?.first).message

    #expect(message.contains("raw `.json` HeistPlan IR"))
    #expect(message.contains("not public run input"))
}

@Test
func `plan source admission rejects raw structured JSON IR fields`() throws {
    let result = HeistPlanSourceAdmission.rejectRawStructuredJSONIRSourceFields(
        commandName: "run_heist",
        fields: [.version, .body]
    )
    let message = try #require(result.failureDiagnostics?.first).message

    #expect(message.contains("raw JSON HeistPlan IR field"))
    #expect(message.contains("ButtonHeist DSL"))
    #expect(message.contains(".heist"))
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
func `plan JSON admission rejects non object JSON with explicit diagnostic`() throws {
    let url = URL(fileURLWithPath: "/tmp/non-object-plan.json")

    do {
        _ = try HeistArtifactCodec.decodeAdmissionCandidateJSON(Data(#"["not an object"]"#.utf8), at: url)
        Issue.record("Expected non-object plan JSON to fail")
    } catch {
        #expect(String(describing: error).contains(
            "Invalid heist plan at /tmp/non-object-plan.json: expected JSON object"
        ))
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
func `heist artifact rejects symlinked manifest and plan members`() throws {
    let temp = try PlansTemporaryDirectory()
    let planJSON = try representativeArtifactPlan().canonicalHeistJSONData()
    let manifestJSON = try HeistArtifactCodec.canonicalManifestJSONData(validArtifactManifest())

    let symlinkManifestURL = temp.url.appendingPathComponent("SymlinkManifest.heist")
    try FileManager.default.createDirectory(at: symlinkManifestURL, withIntermediateDirectories: true)
    let realManifestURL = symlinkManifestURL.appendingPathComponent("manifest-real.json")
    try manifestJSON.write(to: realManifestURL)
    try FileManager.default.createSymbolicLink(
        at: symlinkManifestURL.appendingPathComponent("manifest.json"),
        withDestinationURL: realManifestURL
    )
    try planJSON.write(to: symlinkManifestURL.appendingPathComponent("plan.json"))
    try expectArtifactReadError(from: symlinkManifestURL, containing: [
        "manifest.json",
        "symbolic link",
    ])

    let symlinkPlanURL = temp.url.appendingPathComponent("SymlinkPlan.heist")
    try FileManager.default.createDirectory(at: symlinkPlanURL, withIntermediateDirectories: true)
    let realPlanURL = symlinkPlanURL.appendingPathComponent("plan-real.json")
    try manifestJSON.write(to: symlinkPlanURL.appendingPathComponent("manifest.json"))
    try planJSON.write(to: realPlanURL)
    try FileManager.default.createSymbolicLink(
        at: symlinkPlanURL.appendingPathComponent("plan.json"),
        withDestinationURL: realPlanURL
    )
    try expectArtifactReadError(from: symlinkPlanURL, containing: [
        "plan.json",
        "symbolic link",
    ])
}

@Test
func `heist artifact rejects escaping symlink member`() throws {
    let temp = try PlansTemporaryDirectory()
    let outsidePlanURL = temp.url.appendingPathComponent("outside-plan.json")
    try representativeArtifactPlan().canonicalHeistJSONData().write(to: outsidePlanURL)

    let packageURL = temp.url.appendingPathComponent("EscapingPlan.heist")
    try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
    try HeistArtifactCodec.canonicalManifestJSONData(validArtifactManifest())
        .write(to: packageURL.appendingPathComponent("manifest.json"))
    try FileManager.default.createSymbolicLink(
        at: packageURL.appendingPathComponent("plan.json"),
        withDestinationURL: outsidePlanURL
    )

    try expectArtifactReadError(from: packageURL, containing: [
        "plan.json",
        "resolves outside the artifact package",
    ])
}

@Test
func `heist artifact rejects oversized manifest and plan before decode`() throws {
    let temp = try PlansTemporaryDirectory()
    let planJSON = try representativeArtifactPlan().canonicalHeistJSONData()
    let manifestJSON = try HeistArtifactCodec.canonicalManifestJSONData(validArtifactManifest())

    let oversizedManifestURL = temp.url.appendingPathComponent("OversizedManifest.heist")
    try FileManager.default.createDirectory(at: oversizedManifestURL, withIntermediateDirectories: true)
    try Data(count: HeistArtifactCodec.manifestMemberSizeLimit + 1)
        .write(to: oversizedManifestURL.appendingPathComponent("manifest.json"))
    try planJSON.write(to: oversizedManifestURL.appendingPathComponent("plan.json"))
    try expectArtifactReadError(
        from: oversizedManifestURL,
        containing: [
            "manifest.json is too large",
            "limit \(HeistArtifactCodec.manifestMemberSizeLimit) bytes",
        ],
        excluding: ["invalid manifest.json"]
    )

    let oversizedPlanURL = temp.url.appendingPathComponent("OversizedPlan.heist")
    try FileManager.default.createDirectory(at: oversizedPlanURL, withIntermediateDirectories: true)
    try manifestJSON.write(to: oversizedPlanURL.appendingPathComponent("manifest.json"))
    try Data(count: HeistArtifactCodec.planMemberSizeLimit + 1)
        .write(to: oversizedPlanURL.appendingPathComponent("plan.json"))
    try expectArtifactReadError(
        from: oversizedPlanURL,
        containing: [
            "plan.json is too large",
            "limit \(HeistArtifactCodec.planMemberSizeLimit) bytes",
        ],
        excluding: ["Invalid heist plan"]
    )
}

@Test
func `heist artifact manifest rejects unknown root fields`() throws {
    let temp = try PlansTemporaryDirectory()
    let plan = try representativeArtifactPlan()
    let manifestJSON = rawArtifactManifestJSON(entry: "searchFlow", additionalFields: [
        #"  "legacyKind" : "raw-json""#,
    ])

    try writePackage(
        named: "UnknownManifestField.heist",
        in: temp.url,
        manifestJSON: manifestJSON,
        planJSON: plan.canonicalHeistJSONData()
    ) { url in
        try expectArtifactReadError(
            from: url,
            containing: [
                "invalid manifest.json",
                "Unknown manifest field",
                "legacyKind",
            ]
        )
    }
}

@Test
func `heist artifact manifest rejects unknown producer fields`() throws {
    let temp = try PlansTemporaryDirectory()
    let manifestJSON = rawArtifactManifestJSON(
        entry: "searchFlow",
        producerFields: [
            #" "name" : "buttonheist""#,
            #" "legacySource" : "json""#,
        ]
    )

    try writePackage(
        named: "UnknownProducerField.heist",
        in: temp.url,
        manifestJSON: manifestJSON,
        planJSON: representativeArtifactPlan().canonicalHeistJSONData()
    ) { url in
        try expectArtifactReadError(
            from: url,
            containing: [
                "invalid manifest.json",
                "Unknown manifest producer field",
                "legacySource",
            ]
        )
    }
}

@Test
func `heist artifact manifest rejects stale version key`() throws {
    let temp = try PlansTemporaryDirectory()
    let manifestJSON = rawArtifactManifestJSON(entry: "searchFlow", additionalFields: [
        #"  "version" : 1"#,
    ])

    try writePackage(
        named: "StaleManifestVersionKey.heist",
        in: temp.url,
        manifestJSON: manifestJSON,
        planJSON: representativeArtifactPlan().canonicalHeistJSONData()
    ) { url in
        try expectArtifactReadError(
            from: url,
            containing: [
                "invalid manifest.json",
                "Unknown manifest field",
                "version",
            ]
        )
    }
}

@Test
func `heist artifact validates manifest and plan versions`() throws {
    let temp = try PlansTemporaryDirectory()

    try writePackage(
        named: "MissingFormatVersion.heist",
        in: temp.url,
        manifestJSON: rawArtifactManifestJSON(entry: "searchFlow", includeFormatVersion: false),
        planJSON: representativeArtifactPlan().canonicalHeistJSONData()
    ) { url in
        try expectArtifactReadError(
            from: url,
            containing: [
                "invalid manifest.json",
                "Missing manifest field",
                "formatVersion",
            ]
        )
    }

    try writePackage(
        named: "UnsupportedArtifact.heist",
        in: temp.url,
        manifest: HeistArtifactManifest(
            format: .buttonHeist,
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
            format: .buttonHeist,
            entry: "searchFlow",
            formatVersion: currentHeistArtifactFormatVersion,
            planVersion: 3,
            producer: .buttonHeist,
            createdAt: Date(timeIntervalSince1970: 0)
        ),
        planJSON: Data(#"{"version":3,"body":[{"type":"warn","warn":{"message":"new version"}}]}"#.utf8)
    ) { url in
        #expect(throws: HeistArtifactCodecError.self) {
            try HeistArtifactCodec.read(from: url)
        }
    }

    try writePackage(
        named: "Mismatch.heist",
        in: temp.url,
        manifest: validArtifactManifest(),
        planJSON: Data(#"{"version":3,"body":[{"type":"warn","warn":{"message":"mismatch"}}]}"#.utf8)
    ) { url in
        do {
            _ = try HeistArtifactCodec.read(from: url)
            Issue.record("Expected version mismatch")
        } catch {
            #expect(String(describing: error).contains("manifest planVersion 2 does not match plan version 3"))
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
        body: [.action(ActionStep(command: .typeText(
            reference: "query",
            target: .label("Search")
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
    let definitions = try (0...250).map { index in
        HeistPlanAdmissionCandidate(name: try HeistPlanName(validating: "definition\(index)"), body: [
            .warn(WarnStep(message: try HeistWarningMessage(validating: "definition \(index)"))),
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

private func representativeArtifactPlan() throws -> HeistPlan {
    try HeistPlan("searchFlow") {
        Warn("check state")
    }
}

private func validArtifactManifest() -> HeistArtifactManifest {
    validArtifactManifest(entry: "searchFlow")
}

private func validArtifactManifest(entry: HeistPlanName) -> HeistArtifactManifest {
    HeistArtifactManifest(
        format: .buttonHeist,
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

private func rawArtifactManifestJSON(
    entry: String?,
    includeFormatVersion: Bool = true,
    producerFields: [String] = [#" "name" : "buttonheist""#],
    additionalFields: [String] = []
) -> Data {
    var fields = [
        #"  "createdAt" : "2026-06-05T00:00:00Z""#,
        #"  "format" : "com.royalpineapple.buttonheist.heist""#,
        #"  "planVersion" : 2"#,
        #"  "producer" : { \#(producerFields.joined(separator: ", ")) }"#,
    ]
    if let entry {
        fields.insert(#"  "entry" : "\#(entry)""#, at: 1)
    }
    if includeFormatVersion {
        fields.insert(#"  "formatVersion" : 1"#, at: 2)
    }
    fields.append(contentsOf: additionalFields)
    return Data(("{\n" + fields.joined(separator: ",\n") + "\n}\n").utf8)
}

private func expectArtifactReadError(
    from url: URL,
    containing substrings: [String],
    excluding excludedSubstrings: [String] = []
) throws {
    do {
        _ = try HeistArtifactCodec.read(from: url)
        Issue.record("Expected artifact read to fail")
    } catch {
        let description = String(describing: error)
        for substring in substrings {
            #expect(description.contains(substring), "\(description) did not contain \(substring)")
        }
        for substring in excludedSubstrings {
            #expect(!description.contains(substring), "\(description) unexpectedly contained \(substring)")
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
