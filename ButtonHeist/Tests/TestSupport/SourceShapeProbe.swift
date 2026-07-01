import Foundation

public struct SourceShapeRepository: Sendable {
    public let root: URL

    public init(filePath: StaticString = #filePath, levelsToRoot: Int = 4) {
        var root = URL(fileURLWithPath: filePath.description)
        for _ in 0..<levelsToRoot {
            root.deleteLastPathComponent()
        }
        self.root = root
    }

    public func file(relativePath: String) throws -> SourceShapeFile? {
        let url = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return SourceShapeFile(
            relativePath: relativePath,
            contents: try String(contentsOf: url, encoding: .utf8)
        )
    }

    public func requiredFile(relativePath: String) throws -> SourceShapeFile {
        guard let file = try file(relativePath: relativePath) else {
            throw SourceShapeProbeError.missingFile(relativePath)
        }
        return file
    }
}

public struct SourceShapeFile: Equatable, Sendable {
    public let relativePath: String
    public let contents: String

    public init(relativePath: String, contents: String) {
        self.relativePath = relativePath
        self.contents = contents
    }

    public func matches(
        of pattern: String,
        options: NSRegularExpression.Options = []
    ) throws -> [String] {
        let regex = try NSRegularExpression(pattern: pattern, options: options)
        let range = NSRange(contents.startIndex..<contents.endIndex, in: contents)
        return regex.matches(in: contents, range: range).compactMap { match in
            Range(match.range, in: contents).map { String(contents[$0]) }
        }
    }

    public func containsMatch(
        _ pattern: String,
        options: NSRegularExpression.Options = []
    ) throws -> Bool {
        try !matches(of: pattern, options: options).isEmpty
    }

    public func firstBlock(
        _ declaration: SourceShapeDeclaration,
        options: NSRegularExpression.Options = []
    ) throws -> SourceShapeFile? {
        try firstBlock(matching: declaration.blockPattern, options: options)
    }

    public func requiredBlock(
        _ declaration: SourceShapeDeclaration,
        message: String? = nil,
        options: NSRegularExpression.Options = []
    ) throws -> SourceShapeFile {
        guard let block = try firstBlock(declaration, options: options) else {
            throw SourceShapeProbeError.missingDeclaration(
                declaration,
                relativePath: relativePath,
                message: message
            )
        }
        return block
    }

    public func declarationSignature(_ declaration: SourceShapeDeclaration) throws -> String? {
        try matches(of: declaration.signaturePattern, options: [.dotMatchesLineSeparators]).first
    }

    @discardableResult
    public func requireDeclaration(
        _ declaration: SourceShapeDeclaration,
        message: String? = nil
    ) throws -> String {
        guard let signature = try declarationSignature(declaration) else {
            throw SourceShapeProbeError.missingDeclaration(
                declaration,
                relativePath: relativePath,
                message: message
            )
        }

        for conformance in declaration.conformances where !signature.contains(conformance) {
            throw SourceShapeProbeError.missingConformance(
                declaration,
                conformance: conformance,
                relativePath: relativePath
            )
        }

        return signature
    }

    public func requireDeclarations(_ declarations: [SourceShapeDeclaration]) throws {
        for declaration in declarations {
            try requireDeclaration(declaration)
        }
    }

    public func lines(matching pattern: String) throws -> [String] {
        let regex = try NSRegularExpression(pattern: pattern)
        return contents
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { line in
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                return regex.firstMatch(in: line, range: range) != nil
            }
            .map { "\($0.trimmingCharacters(in: .whitespaces))" }
    }

    public func firstBlock(
        matching declarationPattern: String,
        options: NSRegularExpression.Options = []
    ) throws -> SourceShapeFile? {
        let regex = try NSRegularExpression(pattern: declarationPattern, options: options)
        let fullRange = NSRange(contents.startIndex..<contents.endIndex, in: contents)
        guard let match = regex.firstMatch(in: contents, range: fullRange),
              let matchRange = Range(match.range, in: contents),
              let openingBrace = contents[matchRange.upperBound...].firstIndex(of: "{")
        else {
            return nil
        }

        var depth = 0
        var index = openingBrace
        while index < contents.endIndex {
            switch contents[index] {
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    let end = contents.index(after: index)
                    return SourceShapeFile(
                        relativePath: "\(relativePath)#block",
                        contents: String(contents[matchRange.lowerBound..<end])
                    )
                }
            default:
                break
            }
            contents.formIndex(after: &index)
        }
        return nil
    }
}

public struct SourceShapeDeclaration: Equatable, Sendable, CustomStringConvertible {
    public let kind: SourceShapeDeclarationKind
    public let name: String
    public let conformances: [String]

    private init(
        kind: SourceShapeDeclarationKind,
        name: String,
        conformances: [String] = []
    ) {
        self.kind = kind
        self.name = name
        self.conformances = conformances
    }

    public static func type(
        _ name: String,
        conformingTo conformances: [String] = []
    ) -> SourceShapeDeclaration {
        SourceShapeDeclaration(
            kind: .type,
            name: name,
            conformances: conformances
        )
    }

    public static func structure(
        _ name: String,
        conformingTo conformances: [String] = []
    ) -> SourceShapeDeclaration {
        SourceShapeDeclaration(
            kind: .structure,
            name: name,
            conformances: conformances
        )
    }

    public static func enumeration(
        _ name: String,
        conformingTo conformances: [String] = []
    ) -> SourceShapeDeclaration {
        SourceShapeDeclaration(
            kind: .enumeration,
            name: name,
            conformances: conformances
        )
    }

    public var description: String {
        "\(kindDescription) \(name)"
    }

    fileprivate var blockPattern: String {
        #"\b(?:"# + kindPattern + #")\s+"# + escapedName + #"\b"#
    }

    fileprivate var signaturePattern: String {
        #"\b(?:"# + kindPattern + #")\s+"# + escapedName + #"\s*:\s*[^{}]+"#
    }

    private var kindPattern: String {
        switch kind {
        case .type:
            return "struct|enum"
        case .structure:
            return "struct"
        case .enumeration:
            return "enum"
        }
    }

    private var kindDescription: String {
        switch kind {
        case .type:
            return "struct or enum"
        case .structure:
            return "struct"
        case .enumeration:
            return "enum"
        }
    }

    private var escapedName: String {
        NSRegularExpression.escapedPattern(for: name)
    }
}

public enum SourceShapeDeclarationKind: Equatable, Sendable {
    case type
    case structure
    case enumeration
}

public enum SourceShapeProbeError: Error, Equatable, Sendable, CustomStringConvertible {
    case missingFile(String)
    case missingDeclaration(SourceShapeDeclaration, relativePath: String, message: String?)
    case missingConformance(SourceShapeDeclaration, conformance: String, relativePath: String)

    public var description: String {
        switch self {
        case .missingFile(let relativePath):
            return "Missing source file: \(relativePath)"
        case .missingDeclaration(let declaration, let relativePath, let message):
            return [
                "\(relativePath) should declare \(declaration)",
                message,
            ]
            .compactMap(\.self)
            .joined(separator: ": ")
        case .missingConformance(let declaration, let conformance, let relativePath):
            return "\(declaration) should conform to \(conformance) in \(relativePath)"
        }
    }
}
