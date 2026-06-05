import Foundation

public let heistArtifactFormat = "com.royalpineapple.buttonheist.heist"
public let currentHeistArtifactFormatVersion = 1
public let currentHeistPlanVersion = HeistPlan.currentVersion

public struct HeistArtifact: Sendable, Equatable {
    public let manifest: HeistArtifactManifest
    public let plan: HeistPlan

    public init(manifest: HeistArtifactManifest, plan: HeistPlan) {
        self.manifest = manifest
        self.plan = plan
    }

    public init(
        plan: HeistPlan,
        producer: HeistArtifactProducer = .buttonHeist,
        createdAt: Date = Date()
    ) {
        self.init(
            manifest: HeistArtifactManifest(
                format: heistArtifactFormat,
                formatVersion: currentHeistArtifactFormatVersion,
                planVersion: plan.version,
                producer: producer,
                createdAt: createdAt
            ),
            plan: plan
        )
    }
}

public struct HeistArtifactManifest: Codable, Sendable, Equatable {
    public let format: String
    public let formatVersion: Int
    public let planVersion: Int
    public let producer: HeistArtifactProducer
    public let createdAt: Date

    public init(
        format: String,
        formatVersion: Int,
        planVersion: Int,
        producer: HeistArtifactProducer,
        createdAt: Date
    ) {
        self.format = format
        self.formatVersion = formatVersion
        self.planVersion = planVersion
        self.producer = producer
        self.createdAt = createdAt
    }
}

public struct HeistArtifactProducer: Codable, Sendable, Equatable {
    public static let buttonHeist = HeistArtifactProducer(name: "buttonheist")

    public let name: String
    public let version: String?

    public init(name: String, version: String? = nil) {
        self.name = name
        self.version = version
    }
}

public enum HeistArtifactCodec {
    public static let manifestFileName = "manifest.json"
    public static let planFileName = "plan.json"

    public static func read(from url: URL) throws -> HeistArtifact {
        let packageURL = url.standardizedFileURL
        try validateHeistPackageDirectory(packageURL)

        let manifestURL = packageURL.appendingPathComponent(manifestFileName)
        let planURL = packageURL.appendingPathComponent(planFileName)
        try requireMember(manifestURL, member: manifestFileName, packageURL: packageURL)
        try requireMember(planURL, member: planFileName, packageURL: packageURL)

        let manifest = try readManifest(from: manifestURL, packageURL: packageURL)
        try validateArtifactEnvelope(manifest: manifest, packageURL: packageURL)

        let planData = try Data(contentsOf: planURL)
        let planVersion = try decodePlanVersion(from: planData, at: planURL)
        guard manifest.planVersion == planVersion else {
            throw HeistArtifactCodecError.versionMismatch(
                path: packageURL.path,
                manifestPlanVersion: manifest.planVersion,
                planVersion: planVersion
            )
        }
        try validateWritablePlanVersion(manifest.planVersion, path: packageURL.path)
        try validateWritablePlanVersion(planVersion, path: planURL.path)

        let plan = try decodePlanJSON(planData, at: planURL)
        return HeistArtifact(manifest: manifest, plan: plan)
    }

    public static func write(_ artifact: HeistArtifact, to url: URL) throws {
        let packageURL = url.standardizedFileURL
        guard artifact.manifest.planVersion == artifact.plan.version else {
            throw HeistArtifactCodecError.versionMismatch(
                path: packageURL.path,
                manifestPlanVersion: artifact.manifest.planVersion,
                planVersion: artifact.plan.version
            )
        }
        try validateArtifactEnvelope(manifest: artifact.manifest, packageURL: packageURL)
        try validateWritablePlanVersion(artifact.manifest.planVersion, path: packageURL.path)
        try validateWritablePlanVersion(artifact.plan.version, path: packageURL.path)

        let fileManager = FileManager.default
        let parent = packageURL.deletingLastPathComponent()
        let temporaryURL = parent.appendingPathComponent(
            ".\(packageURL.lastPathComponent).\(UUID().uuidString).tmp",
            isDirectory: true
        )

        try fileManager.createDirectory(at: temporaryURL, withIntermediateDirectories: true)
        do {
            try canonicalManifestJSONData(artifact.manifest)
                .write(to: temporaryURL.appendingPathComponent(manifestFileName), options: .atomic)
            try artifact.plan.canonicalHeistJSONData()
                .write(to: temporaryURL.appendingPathComponent(planFileName), options: .atomic)

            if fileManager.fileExists(atPath: packageURL.path) {
                _ = try fileManager.replaceItemAt(packageURL, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: packageURL)
            }
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    public static func readPlan(from url: URL) throws -> HeistPlan {
        let fileURL = url.standardizedFileURL
        switch fileURL.pathExtension.lowercased() {
        case "heist":
            return try read(from: fileURL).plan
        case "json":
            return try decodePlanJSON(try Data(contentsOf: fileURL), at: fileURL)
        default:
            throw HeistArtifactCodecError.unsupportedInputExtension(path: fileURL.path)
        }
    }

    public static func writePlan(_ plan: HeistPlan, to url: URL) throws {
        let fileURL = url.standardizedFileURL
        switch fileURL.pathExtension.lowercased() {
        case "heist":
            try write(HeistArtifact(plan: plan), to: fileURL)
        case "json":
            try plan.canonicalHeistJSONData().write(to: fileURL, options: .atomic)
        default:
            throw HeistArtifactCodecError.unsupportedOutputExtension(path: fileURL.path)
        }
    }

    public static func decodePlanJSON(_ data: Data, at url: URL) throws -> HeistPlan {
        let version = try decodePlanVersion(from: data, at: url)
        try validateWritablePlanVersion(version, path: url.path)
        do {
            return try JSONDecoder().decode(HeistPlan.self, from: data)
        } catch {
            throw HeistArtifactCodecError.invalidPlan(path: url.path, reason: String(describing: error))
        }
    }

    public static func canonicalManifestJSONData(_ manifest: HeistArtifactManifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(manifest)
    }

    private static func validateHeistPackageDirectory(_ url: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw HeistArtifactCodecError.invalidPackage(path: url.path)
        }
        guard isDirectory.boolValue else {
            let firstByte = (try? Data(contentsOf: url))?.firstNonWhitespaceByte
            if firstByte.isJSONStartByte {
                throw HeistArtifactCodecError.rawJSONHeist(path: url.path)
            }
            throw HeistArtifactCodecError.invalidPackage(path: url.path)
        }
    }

    private static func requireMember(_ url: URL, member: String, packageURL: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else {
            throw HeistArtifactCodecError.missingMember(path: packageURL.path, member: member)
        }
    }

    private static func readManifest(from url: URL, packageURL: URL) throws -> HeistArtifactManifest {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(HeistArtifactManifest.self, from: try Data(contentsOf: url))
        } catch {
            throw HeistArtifactCodecError.invalidManifest(
                path: packageURL.path,
                member: manifestFileName,
                reason: String(describing: error)
            )
        }
    }

    private static func validateArtifactEnvelope(manifest: HeistArtifactManifest, packageURL: URL) throws {
        guard manifest.format == heistArtifactFormat else {
            throw HeistArtifactCodecError.invalidManifestFormat(
                path: packageURL.path,
                observed: manifest.format
            )
        }
        guard manifest.formatVersion == currentHeistArtifactFormatVersion else {
            throw HeistArtifactCodecError.unsupportedArtifactVersion(
                path: packageURL.path,
                observed: manifest.formatVersion
            )
        }
    }

    private static func decodePlanVersion(from data: Data, at url: URL) throws -> Int {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw HeistArtifactCodecError.invalidPlan(path: url.path, reason: String(describing: error))
        }

        guard let dictionary = object as? [String: Any] else {
            throw HeistArtifactCodecError.invalidPlan(path: url.path, reason: "expected JSON object")
        }
        guard let version = dictionary["version"] else {
            throw HeistArtifactCodecError.missingPlanVersion(path: url.path)
        }
        guard let intVersion = version as? Int else {
            throw HeistArtifactCodecError.invalidPlanVersion(path: url.path, observed: String(describing: version))
        }
        return intVersion
    }

    private static func validateWritablePlanVersion(_ version: Int, path: String) throws {
        guard version == currentHeistPlanVersion else {
            throw HeistArtifactCodecError.unsupportedPlanVersion(path: path, observed: version)
        }
    }
}

public enum HeistArtifactCodecError: Error, Sendable, CustomStringConvertible, LocalizedError {
    case invalidPackage(path: String)
    case rawJSONHeist(path: String)
    case missingMember(path: String, member: String)
    case invalidManifest(path: String, member: String, reason: String)
    case invalidManifestFormat(path: String, observed: String)
    case unsupportedArtifactVersion(path: String, observed: Int)
    case missingPlanVersion(path: String)
    case invalidPlanVersion(path: String, observed: String)
    case unsupportedPlanVersion(path: String, observed: Int)
    case versionMismatch(path: String, manifestPlanVersion: Int, planVersion: Int)
    case invalidPlan(path: String, reason: String)
    case unsupportedInputExtension(path: String)
    case unsupportedOutputExtension(path: String)

    public var description: String {
        switch self {
        case .invalidPackage(let path):
            return "Invalid .heist artifact at \(path): expected package containing manifest.json and plan.json."
        case .rawJSONHeist(let path):
            return """
            Invalid .heist artifact at \(path): raw JSON is not a .heist package. \
            Use .json for raw HeistPlan IR or re-export as .heist.
            """
        case .missingMember(let path, let member):
            return """
            Invalid .heist artifact at \(path): missing \(member). \
            Expected package containing manifest.json and plan.json. \
            Re-export the heist or run a Swift heist source.
            """
        case .invalidManifest(let path, let member, let reason):
            return "Invalid .heist artifact at \(path): invalid \(member): \(reason)"
        case .invalidManifestFormat(let path, let observed):
            return """
            Invalid .heist artifact at \(path): manifest format \(observed) is unsupported. \
            Re-export the heist as .heist.
            """
        case .unsupportedArtifactVersion(let path, let observed):
            return """
            Invalid .heist artifact at \(path): unsupported formatVersion \(observed). \
            This Button Heist build supports formatVersion \(currentHeistArtifactFormatVersion).
            """
        case .missingPlanVersion(let path):
            return "Invalid heist plan at \(path): missing version."
        case .invalidPlanVersion(let path, let observed):
            return "Invalid heist plan at \(path): version must be an integer, got \(observed)."
        case .unsupportedPlanVersion(let path, let observed):
            return """
            Invalid heist plan at \(path): unsupported version \(observed). \
            This Button Heist build supports version \(currentHeistPlanVersion).
            """
        case .versionMismatch(let path, let manifestPlanVersion, let planVersion):
            return """
            Invalid heist artifact at \(path): manifest planVersion \(manifestPlanVersion) \
            does not match plan version \(planVersion).
            """
        case .invalidPlan(let path, let reason):
            return "Invalid heist plan at \(path): \(reason)"
        case .unsupportedInputExtension(let path):
            return "Unsupported heist input extension for \(path). Use .heist or .json."
        case .unsupportedOutputExtension(let path):
            return "Unsupported heist output extension for \(path). Use .heist or .json."
        }
    }

    public var errorDescription: String? { description }
}

private extension Optional where Wrapped == UInt8 {
    var isJSONStartByte: Bool {
        switch self {
        case .some(0x7B), .some(0x5B):
            return true
        default:
            return false
        }
    }
}

private extension Data {
    var firstNonWhitespaceByte: UInt8? {
        first { byte in
            switch byte {
            case 0x20, 0x09, 0x0A, 0x0D:
                return false
            default:
                return true
            }
        }
    }
}
