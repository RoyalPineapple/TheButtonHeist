import Foundation
import Testing
@_spi(ButtonHeistInternals) import ThePlans

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
