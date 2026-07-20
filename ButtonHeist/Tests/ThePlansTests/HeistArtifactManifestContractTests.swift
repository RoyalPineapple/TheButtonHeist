import Foundation
import Testing
@_spi(ButtonHeistInternals) import ThePlans

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
