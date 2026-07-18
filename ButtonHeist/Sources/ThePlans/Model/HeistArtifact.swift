import Foundation

public let currentHeistArtifactFormatVersion = 1
public let currentHeistPlanVersion = HeistPlan.currentVersion

public enum HeistArtifactFormat: String, Codable, Sendable, Equatable, CaseIterable {
    case buttonHeist = "com.royalpineapple.buttonheist.heist"
}

private func admitArtifactProducerValue<Failure: Error>(
    _ value: String,
    or failure: @autoclosure () -> Failure
) throws -> String {
    guard value.contains(where: { !$0.isWhitespace }) else { throw failure() }
    return value
}

private func decodeArtifactProducerValue<Value>(
    from decoder: Decoder,
    admitting: (String) throws -> Value
) throws -> Value {
    let container = try decoder.singleValueContainer()
    do {
        return try admitting(container.decode(String.self))
    } catch {
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: String(describing: error)
        )
    }
}

private func encodeArtifactProducerValue(_ value: String, to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(value)
}

public struct HeistArtifactProducerName: Sendable, Equatable, Hashable, ExpressibleByStringLiteral,
    CustomStringConvertible, Codable {
    public enum ValidationError: Error, Sendable, Equatable, CustomStringConvertible {
        case blank

        public var description: String {
            "heist artifact producer name must contain a non-whitespace character"
        }
    }

    private let value: String

    public init(validating value: String) throws {
        self.value = try admitArtifactProducerValue(value, or: ValidationError.blank)
    }

    public init(stringLiteral value: String) {
        do {
            try self.init(validating: value)
        } catch {
            preconditionFailure(String(describing: error))
        }
    }

    public var description: String { value }

    public init(from decoder: Decoder) throws {
        self = try decodeArtifactProducerValue(from: decoder, admitting: Self.init(validating:))
    }

    public func encode(to encoder: Encoder) throws {
        try encodeArtifactProducerValue(value, to: encoder)
    }
}

public struct HeistArtifactProducerVersion: Sendable, Equatable, Hashable, ExpressibleByStringLiteral,
    CustomStringConvertible, Codable {
    public enum ValidationError: Error, Sendable, Equatable, CustomStringConvertible {
        case blank

        public var description: String {
            "heist artifact producer version must contain a non-whitespace character"
        }
    }

    private let value: String

    public init(validating value: String) throws {
        self.value = try admitArtifactProducerValue(value, or: ValidationError.blank)
    }

    public init(stringLiteral value: String) {
        do {
            try self.init(validating: value)
        } catch {
            preconditionFailure(String(describing: error))
        }
    }

    public var description: String { value }

    public init(from decoder: Decoder) throws {
        self = try decodeArtifactProducerValue(from: decoder, admitting: Self.init(validating:))
    }

    public func encode(to encoder: Encoder) throws {
        try encodeArtifactProducerValue(value, to: encoder)
    }
}

public struct HeistArtifact: Sendable, Equatable {
    public enum InitializationError: Error, Sendable, Equatable, CustomStringConvertible {
        case anonymousPlan

        public var description: String {
            "a .heist artifact requires a named root plan"
        }
    }

    public let manifest: HeistArtifactManifest
    public let plan: HeistPlan

    fileprivate init(manifest: HeistArtifactManifest, plan: HeistPlan) {
        self.manifest = manifest
        self.plan = plan
    }

    public init(
        plan: HeistPlan,
        producer: HeistArtifactProducer = .buttonHeist,
        createdAt: Date = Date()
    ) throws {
        guard let entry = plan.name else { throw InitializationError.anonymousPlan }
        self.init(
            manifest: HeistArtifactManifest(
                format: .buttonHeist,
                entry: entry,
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
    public let format: HeistArtifactFormat
    public let entry: HeistPlanName
    public let formatVersion: Int
    public let planVersion: Int
    public let producer: HeistArtifactProducer
    public let createdAt: Date

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case format, entry, formatVersion, planVersion, producer, createdAt
    }

    public init(
        format: HeistArtifactFormat,
        entry: HeistPlanName,
        formatVersion: Int,
        planVersion: Int,
        producer: HeistArtifactProducer,
        createdAt: Date
    ) {
        self.format = format
        self.entry = entry
        self.formatVersion = formatVersion
        self.planVersion = planVersion
        self.producer = producer
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "manifest")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decodeRequired(HeistArtifactFormat.self, forKey: .format, typeName: "manifest")
        entry = try container.decodeRequired(HeistPlanName.self, forKey: .entry, typeName: "manifest")
        formatVersion = try container.decodeRequired(Int.self, forKey: .formatVersion, typeName: "manifest")
        planVersion = try container.decodeRequired(Int.self, forKey: .planVersion, typeName: "manifest")
        producer = try container.decodeRequired(HeistArtifactProducer.self, forKey: .producer, typeName: "manifest")
        createdAt = try container.decodeRequired(Date.self, forKey: .createdAt, typeName: "manifest")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(format, forKey: .format)
        try container.encode(entry, forKey: .entry)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(planVersion, forKey: .planVersion)
        try container.encode(producer, forKey: .producer)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

public struct HeistArtifactProducer: Codable, Sendable, Equatable {
    public static let buttonHeist = HeistArtifactProducer(name: "buttonheist")

    public let name: HeistArtifactProducerName
    public let version: HeistArtifactProducerVersion?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case name, version
    }

    public init(name: HeistArtifactProducerName, version: HeistArtifactProducerVersion? = nil) {
        self.name = name
        self.version = version
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "manifest producer")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeRequired(HeistArtifactProducerName.self, forKey: .name, typeName: "manifest producer")
        version = try container.decodeIfPresent(HeistArtifactProducerVersion.self, forKey: .version)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(version, forKey: .version)
    }
}

public enum HeistArtifactCodec {
    public static let manifestFileName = "manifest.json"
    public static let planFileName = "plan.json"
    package static let manifestMemberSizeLimit = 64 * 1024
    package static let planMemberSizeLimit = 8 * 1024 * 1024

    private static let fileReadChunkSize = 64 * 1024

    public static func read(from url: URL) throws -> HeistArtifact {
        let packageURL = url.standardizedFileURL
        try requireHeistInputExtension(packageURL)
        try validateHeistPackageDirectory(packageURL)

        let manifestMember = try readArtifactMemberData(
            manifestFileName,
            in: packageURL,
            maxBytes: manifestMemberSizeLimit
        )
        let planMember = try readArtifactMemberData(
            planFileName,
            in: packageURL,
            maxBytes: planMemberSizeLimit
        )

        let manifestPayload = try readManifestPayload(from: manifestMember.data, packageURL: packageURL)
        let planCandidate = try decodePlanCandidate(planMember.data, at: planMember.url)
        try validateArtifactEnvelope(manifest: manifestPayload, packageURL: packageURL)
        guard manifestPayload.planVersion == planCandidate.version else {
            throw HeistArtifactCodecError.versionMismatch(
                path: packageURL.path,
                manifestPlanVersion: manifestPayload.planVersion,
                planVersion: planCandidate.version
            )
        }
        let plan = try admitPlan(planCandidate, at: planMember.url)
        let entry = try validateArtifactEntry(
            manifestEntry: manifestPayload.entry,
            plan: plan,
            packageURL: packageURL
        )
        let manifest = HeistArtifactManifest(
            format: manifestPayload.format,
            entry: entry,
            formatVersion: manifestPayload.formatVersion,
            planVersion: manifestPayload.planVersion,
            producer: manifestPayload.producer,
            createdAt: manifestPayload.createdAt
        )
        return HeistArtifact(manifest: manifest, plan: plan)
    }

    public static func write(_ artifact: HeistArtifact, to url: URL) throws {
        let packageURL = url.standardizedFileURL
        try requireHeistOutputExtension(packageURL)
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
                let backupURL = try fileManager.replaceItemAt(packageURL, withItemAt: temporaryURL)
                if let backupURL {
                    try? fileManager.removeItem(at: backupURL)
                }
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
        try requireHeistInputExtension(fileURL)
        return try read(from: fileURL).plan
    }

    public static func writePlan(_ plan: HeistPlan, to url: URL) throws {
        let fileURL = url.standardizedFileURL
        try requireHeistOutputExtension(fileURL)
        try write(HeistArtifact(plan: plan), to: fileURL)
    }

    package static func decodeAdmissionCandidateJSON(
        _ data: Data,
        at url: URL
    ) throws -> HeistPlanAdmissionCandidate {
        try decodePlanCandidate(data, at: url)
    }

    public static func canonicalManifestJSONData(_ manifest: HeistArtifactManifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(manifest)
    }

    private static func requireHeistInputExtension(_ url: URL) throws {
        guard url.pathExtension.lowercased() == "heist" else {
            throw HeistArtifactCodecError.unsupportedInputExtension(path: url.path)
        }
    }

    private static func requireHeistOutputExtension(_ url: URL) throws {
        guard url.pathExtension.lowercased() == "heist" else {
            throw HeistArtifactCodecError.unsupportedOutputExtension(path: url.path)
        }
    }

    private static func validateHeistPackageDirectory(_ url: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw HeistArtifactCodecError.invalidPackage(path: url.path)
        }
        guard isDirectory.boolValue else {
            let firstByte = firstNonWhitespaceByte(in: url)
            if firstByte.isJSONStartByte {
                throw HeistArtifactCodecError.rawJSONHeist(path: url.path)
            }
            throw HeistArtifactCodecError.invalidPackage(path: url.path)
        }
    }

    private static func readArtifactMemberData(
        _ member: String,
        in packageURL: URL,
        maxBytes: Int
    ) throws -> ArtifactMemberData {
        let url = try validateArtifactMember(member, in: packageURL, maxBytes: maxBytes)
        return ArtifactMemberData(
            url: url,
            data: try readBoundedFile(url, member: member, packageURL: packageURL, maxBytes: maxBytes)
        )
    }

    private static func validateArtifactMember(
        _ member: String,
        in packageURL: URL,
        maxBytes: Int
    ) throws -> URL {
        let url = packageURL.appendingPathComponent(member, isDirectory: false)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else {
            throw HeistArtifactCodecError.missingMember(path: packageURL.path, member: member)
        }
        try validateMemberContainment(url, member: member, packageURL: packageURL)
        if isSymbolicLink(url) {
            throw HeistArtifactCodecError.symlinkMember(path: packageURL.path, member: member)
        }
        guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            throw HeistArtifactCodecError.invalidMember(
                path: packageURL.path,
                member: member,
                reason: "could not determine file size"
            )
        }
        guard size <= maxBytes else {
            throw HeistArtifactCodecError.memberTooLarge(
                path: packageURL.path,
                member: member,
                limit: maxBytes,
                observed: size
            )
        }
        return url
    }

    private static func validateMemberContainment(_ url: URL, member: String, packageURL: URL) throws {
        let resolvedPackagePath = packageURL.resolvingSymlinksInPath().standardizedFileURL.path
        let resolvedMemberPath = url.resolvingSymlinksInPath().standardizedFileURL.path
        guard resolvedMemberPath.isSameOrDescendant(of: resolvedPackagePath) else {
            throw HeistArtifactCodecError.unsafeMemberPath(
                path: packageURL.path,
                member: member,
                resolvedPath: resolvedMemberPath
            )
        }
    }

    private static func readBoundedFile(
        _ url: URL,
        member: String,
        packageURL: URL,
        maxBytes: Int
    ) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var data = Data()
        while true {
            let remaining = maxBytes - data.count
            let readSize = min(fileReadChunkSize, remaining + 1)
            guard let chunk = try handle.read(upToCount: readSize), !chunk.isEmpty else {
                return data
            }
            guard data.count + chunk.count <= maxBytes else {
                throw HeistArtifactCodecError.memberTooLarge(
                    path: packageURL.path,
                    member: member,
                    limit: maxBytes,
                    observed: data.count + chunk.count
                )
            }
            data.append(chunk)
        }
    }

    private static func firstNonWhitespaceByte(in url: URL) -> UInt8? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: fileReadChunkSize))??.firstNonWhitespaceByte
    }

    private static func isSymbolicLink(_ url: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    private static func readManifestPayload(from data: Data, packageURL: URL) throws -> HeistArtifactManifestPayload {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(HeistArtifactManifestPayload.self, from: data)
        } catch {
            throw HeistArtifactCodecError.invalidManifest(
                path: packageURL.path,
                member: manifestFileName,
                reason: String(describing: error)
            )
        }
    }

    private static func decodePlanCandidate(_ data: Data, at url: URL) throws -> HeistPlanAdmissionCandidate {
        do {
            return try JSONDecoder().decode(HeistPlanAdmissionCandidate.self, from: data)
        } catch DecodingError.typeMismatch(_, let context) where context.codingPath.isEmpty {
            throw HeistArtifactCodecError.invalidPlan(path: url.path, reason: "expected JSON object")
        } catch DecodingError.keyNotFound(let key, _) where key.stringValue == "version" {
            throw HeistArtifactCodecError.missingPlanVersion(path: url.path)
        } catch DecodingError.typeMismatch(_, let context) where context.codingPath.last?.stringValue == "version" {
            throw HeistArtifactCodecError.invalidPlanVersion(path: url.path, observed: context.debugDescription)
        } catch {
            throw HeistArtifactCodecError.invalidPlan(path: url.path, reason: String(describing: error))
        }
    }

    private static func admitPlan(_ candidate: HeistPlanAdmissionCandidate, at url: URL) throws -> HeistPlan {
        do {
            return try candidate.validatedSemantics()
        } catch let error as HeistPlanVersionAdmissionError {
            throw HeistArtifactCodecError.unsupportedPlanVersion(path: url.path, observed: error.observed)
        } catch {
            throw HeistArtifactCodecError.invalidPlan(path: url.path, reason: String(describing: error))
        }
    }

    private static func validateArtifactEnvelope(
        manifest: HeistArtifactManifestPayload,
        packageURL: URL
    ) throws {
        guard manifest.formatVersion == currentHeistArtifactFormatVersion else {
            throw HeistArtifactCodecError.unsupportedArtifactVersion(
                path: packageURL.path,
                observed: manifest.formatVersion
            )
        }
    }

    private static func validateArtifactEntry(
        manifestEntry: HeistPlanName?,
        plan: HeistPlan,
        packageURL: URL
    ) throws -> HeistPlanName {
        let correction = artifactEntryCorrection(for: plan)
        guard let manifestEntry else {
            throw HeistArtifactCodecError.invalidManifestEntry(
                path: packageURL.path,
                contract: "entry is required and must name the root HeistPlan.name",
                observed: "missing entry",
                correction: correction
            )
        }
        guard let planName = plan.name else {
            throw HeistArtifactCodecError.invalidManifestEntry(
                path: packageURL.path,
                contract: "artifact root plan must have a non-empty HeistPlan.name",
                observed: "plan.name is missing or empty",
                correction: "Add a non-empty root plan name in plan.json and set manifest.json entry to the same value."
            )
        }
        guard manifestEntry == planName else {
            throw HeistArtifactCodecError.invalidManifestEntry(
                path: packageURL.path,
                contract: "entry must equal the root HeistPlan.name",
                observed: "entry \(quoted(manifestEntry.description)) with root plan name \(quoted(planName.description))",
                correction: artifactEntryCorrection(for: plan)
            )
        }
        return manifestEntry
    }

    private static func artifactEntryCorrection(for plan: HeistPlan) -> String {
        guard let planName = plan.name else {
            return "Add a non-empty root plan name in plan.json and set manifest.json entry to the same value."
        }
        return """
        Set manifest.json entry to \(quoted(planName.description)), the root plan name. \
        Do not use the .heist directory name, a definition name, or a registry key.
        """
    }

    private static func quoted(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
    }

}

private struct ArtifactMemberData {
    let url: URL
    let data: Data
}

private struct HeistArtifactManifestPayload: Decodable {
    let format: HeistArtifactFormat
    let entry: HeistPlanName?
    let formatVersion: Int
    let planVersion: Int
    let producer: HeistArtifactProducer
    let createdAt: Date

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case format, entry, formatVersion, planVersion, producer, createdAt
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "manifest")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decodeRequired(HeistArtifactFormat.self, forKey: .format, typeName: "manifest")
        entry = try container.decodeIfPresent(HeistPlanName.self, forKey: .entry)
        formatVersion = try container.decodeRequired(Int.self, forKey: .formatVersion, typeName: "manifest")
        planVersion = try container.decodeRequired(Int.self, forKey: .planVersion, typeName: "manifest")
        producer = try container.decodeRequired(HeistArtifactProducer.self, forKey: .producer, typeName: "manifest")
        createdAt = try container.decodeRequired(Date.self, forKey: .createdAt, typeName: "manifest")
    }
}

public enum HeistArtifactCodecError: Error, Sendable, CustomStringConvertible, LocalizedError {
    case invalidPackage(path: String)
    case rawJSONHeist(path: String)
    case missingMember(path: String, member: String)
    case symlinkMember(path: String, member: String)
    case unsafeMemberPath(path: String, member: String, resolvedPath: String)
    case invalidMember(path: String, member: String, reason: String)
    case memberTooLarge(path: String, member: String, limit: Int, observed: Int)
    case invalidManifest(path: String, member: String, reason: String)
    case invalidManifestEntry(path: String, contract: String, observed: String, correction: String)
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
            Use Swift DSL source or re-export the generated artifact as .heist.
            """
        case .missingMember(let path, let member):
            return """
            Invalid .heist artifact at \(path): missing \(member). \
            Expected package containing manifest.json and plan.json. \
            Re-export the heist or run a Swift heist source.
            """
        case .symlinkMember(let path, let member):
            return """
            Invalid .heist artifact at \(path): \(member) must be a regular file inside the artifact package, \
            not a symbolic link.
            """
        case .unsafeMemberPath(let path, let member, let resolvedPath):
            return """
            Invalid .heist artifact at \(path): \(member) resolves outside the artifact package \
            to \(resolvedPath).
            """
        case .invalidMember(let path, let member, let reason):
            return "Invalid .heist artifact at \(path): invalid \(member): \(reason)"
        case .memberTooLarge(let path, let member, let limit, let observed):
            return """
            Invalid .heist artifact at \(path): \(member) is too large \
            (\(observed) bytes; limit \(limit) bytes).
            """
        case .invalidManifest(let path, let member, let reason):
            return "Invalid .heist artifact at \(path): invalid \(member): \(reason)"
        case .invalidManifestEntry(let path, let contract, let observed, let correction):
            return """
            Invalid .heist artifact at \(path): manifest entry contract failed: \(contract); \
            observed \(observed); \(correction)
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
            return "Unsupported heist input extension for \(path). Use a generated .heist package artifact."
        case .unsupportedOutputExtension(let path):
            return "Unsupported heist output extension for \(path). Use a generated .heist package artifact."
        }
    }

    public var errorDescription: String? { description }
}

private extension String {
    func isSameOrDescendant(of directory: String) -> Bool {
        self == directory || hasPrefix(directory.hasSuffix("/") ? directory : "\(directory)/")
    }
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

private extension KeyedDecodingContainer {
    func decodeRequired<T: Decodable>(
        _ type: T.Type,
        forKey key: Key,
        typeName: String
    ) throws -> T {
        guard contains(key) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: codingPath + [key],
                debugDescription: "Missing \(typeName) field \"\(key.stringValue)\""
            ))
        }
        return try decode(type, forKey: key)
    }
}
