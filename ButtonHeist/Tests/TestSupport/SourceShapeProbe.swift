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

public enum SourceShapeProbeError: Error, Equatable, Sendable {
    case missingFile(String)
}
