import Foundation

/// Limits for public machine-input adapters before they materialize recursive
/// JSON structures. Public users hit these through `buttonheist json_lines` and
/// MCP tool arguments.
public enum PublicAdapterInputLimits {
    public static let maxRequestBytes = 1_000_000
    public static let maxNestingDepth = 32
    public static let maxTotalObjectKeys = 1_024
}

public struct PublicAdapterInputError: Error, LocalizedError, CustomStringConvertible, Equatable, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
    public var description: String { message }
}

public enum PublicJSONInputPreflight {
    public static func validateObject(
        _ input: String,
        context: String = "Public JSON request",
        maxBytes: Int = PublicAdapterInputLimits.maxRequestBytes,
        maxNestingDepth: Int = PublicAdapterInputLimits.maxNestingDepth,
        maxTotalObjectKeys: Int = PublicAdapterInputLimits.maxTotalObjectKeys
    ) throws {
        let byteCount = input.utf8.count
        guard byteCount <= maxBytes else {
            throw PublicAdapterInputError(
                "\(context) exceeds \(maxBytes) bytes (observed \(byteCount) bytes)"
            )
        }

        var scanner = PublicJSONInputScanner(
            bytes: Array(input.utf8),
            context: context,
            maxNestingDepth: maxNestingDepth,
            maxTotalObjectKeys: maxTotalObjectKeys
        )
        try scanner.parseRootObject()
    }
}

private struct PublicJSONInputScanner {
    private let bytes: [UInt8]
    private let context: String
    private let maxNestingDepth: Int
    private let maxTotalObjectKeys: Int
    private var index = 0
    private var totalObjectKeys = 0

    init(bytes: [UInt8], context: String, maxNestingDepth: Int, maxTotalObjectKeys: Int) {
        self.bytes = bytes
        self.context = context
        self.maxNestingDepth = maxNestingDepth
        self.maxTotalObjectKeys = maxTotalObjectKeys
    }

    mutating func parseRootObject() throws {
        skipWhitespace()
        guard peek == Self.leftBrace else {
            throw invalidJSON()
        }
        try parseValue(depth: 1)
        skipWhitespace()
        guard index == bytes.count else {
            throw invalidJSON()
        }
    }

    private mutating func parseValue(depth: Int) throws {
        try validateDepth(depth)
        skipWhitespace()
        guard let byte = peek else {
            throw invalidJSON()
        }

        switch byte {
        case Self.leftBrace:
            try parseObject(depth: depth)
        case Self.leftBracket:
            try parseArray(depth: depth)
        case Self.quote:
            try parseString()
        case Self.t:
            try consumeLiteral("true")
        case Self.f:
            try consumeLiteral("false")
        case Self.n:
            try consumeLiteral("null")
        case Self.minus, Self.zero...Self.nine:
            try parseNumber()
        default:
            throw invalidJSON()
        }
    }

    private mutating func parseObject(depth: Int) throws {
        try validateDepth(depth)
        try consume(Self.leftBrace)
        skipWhitespace()
        if consumeIfPresent(Self.rightBrace) {
            return
        }

        while true {
            skipWhitespace()
            guard peek == Self.quote else {
                throw invalidJSON()
            }
            try parseString()
            try countObjectKey()
            skipWhitespace()
            try consume(Self.colon)
            try parseValue(depth: depth + 1)
            skipWhitespace()
            if consumeIfPresent(Self.rightBrace) {
                return
            }
            try consume(Self.comma)
        }
    }

    private mutating func parseArray(depth: Int) throws {
        try validateDepth(depth)
        try consume(Self.leftBracket)
        skipWhitespace()
        if consumeIfPresent(Self.rightBracket) {
            return
        }

        while true {
            try parseValue(depth: depth + 1)
            skipWhitespace()
            if consumeIfPresent(Self.rightBracket) {
                return
            }
            try consume(Self.comma)
        }
    }

    private mutating func parseString() throws {
        try consume(Self.quote)
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            switch byte {
            case Self.quote:
                return
            case Self.backslash:
                try parseStringEscape()
            case 0x00...0x1F:
                throw invalidJSON()
            default:
                continue
            }
        }
        throw invalidJSON()
    }

    private mutating func parseStringEscape() throws {
        guard index < bytes.count else {
            throw invalidJSON()
        }
        let escaped = bytes[index]
        index += 1
        switch escaped {
        case Self.quote, Self.backslash, Self.slash, Self.b, Self.f, Self.n, Self.r, Self.t:
            return
        case Self.u:
            guard index + 4 <= bytes.count else {
                throw invalidJSON()
            }
            for _ in 0..<4 {
                guard Self.isHexDigit(bytes[index]) else {
                    throw invalidJSON()
                }
                index += 1
            }
        default:
            throw invalidJSON()
        }
    }

    private mutating func parseNumber() throws {
        if consumeIfPresent(Self.minus), peek == nil {
            throw invalidJSON()
        }

        if consumeIfPresent(Self.zero) {
            if let byte = peek, Self.isDigit(byte) {
                throw invalidJSON()
            }
        } else {
            try consumeDigit()
            while let byte = peek, Self.isDigit(byte) {
                index += 1
            }
        }

        if consumeIfPresent(Self.period) {
            try consumeDigit()
            while let byte = peek, Self.isDigit(byte) {
                index += 1
            }
        }

        if consumeIfPresent(Self.e) || consumeIfPresent(Self.capitalE) {
            _ = consumeIfPresent(Self.plus) || consumeIfPresent(Self.minus)
            try consumeDigit()
            while let byte = peek, Self.isDigit(byte) {
                index += 1
            }
        }
    }

    private mutating func consumeDigit() throws {
        guard let byte = peek, Self.isDigit(byte) else {
            throw invalidJSON()
        }
        index += 1
    }

    private mutating func consumeLiteral(_ literal: String) throws {
        for byte in literal.utf8 {
            try consume(byte)
        }
    }

    private mutating func consume(_ byte: UInt8) throws {
        guard consumeIfPresent(byte) else {
            throw invalidJSON()
        }
    }

    private mutating func consumeIfPresent(_ byte: UInt8) -> Bool {
        guard peek == byte else {
            return false
        }
        index += 1
        return true
    }

    private mutating func skipWhitespace() {
        while let byte = peek, Self.isWhitespace(byte) {
            index += 1
        }
    }

    private mutating func countObjectKey() throws {
        totalObjectKeys += 1
        guard totalObjectKeys <= maxTotalObjectKeys else {
            throw PublicAdapterInputError(
                "\(context) object key count exceeds \(maxTotalObjectKeys) (observed \(totalObjectKeys))"
            )
        }
    }

    private func validateDepth(_ depth: Int) throws {
        guard depth <= maxNestingDepth else {
            throw PublicAdapterInputError(
                "\(context) nesting depth exceeds \(maxNestingDepth) (observed \(depth))"
            )
        }
    }

    private var peek: UInt8? {
        index < bytes.count ? bytes[index] : nil
    }

    private func invalidJSON() -> PublicAdapterInputError {
        PublicAdapterInputError("\(context) is not valid JSON")
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09
    }

    private static func isDigit(_ byte: UInt8) -> Bool {
        zero...nine ~= byte
    }

    private static func isHexDigit(_ byte: UInt8) -> Bool {
        (zero...nine ~= byte) || (capitalA...capitalF ~= byte) || (a...f ~= byte)
    }

    private static let quote = UInt8(ascii: "\"")
    private static let backslash = UInt8(ascii: "\\")
    private static let slash = UInt8(ascii: "/")
    private static let leftBrace = UInt8(ascii: "{")
    private static let rightBrace = UInt8(ascii: "}")
    private static let leftBracket = UInt8(ascii: "[")
    private static let rightBracket = UInt8(ascii: "]")
    private static let colon = UInt8(ascii: ":")
    private static let comma = UInt8(ascii: ",")
    private static let minus = UInt8(ascii: "-")
    private static let plus = UInt8(ascii: "+")
    private static let period = UInt8(ascii: ".")
    private static let zero = UInt8(ascii: "0")
    private static let nine = UInt8(ascii: "9")
    private static let a = UInt8(ascii: "a")
    private static let b = UInt8(ascii: "b")
    private static let capitalA = UInt8(ascii: "A")
    private static let capitalE = UInt8(ascii: "E")
    private static let capitalF = UInt8(ascii: "F")
    private static let e = UInt8(ascii: "e")
    private static let f = UInt8(ascii: "f")
    private static let n = UInt8(ascii: "n")
    private static let r = UInt8(ascii: "r")
    private static let t = UInt8(ascii: "t")
    private static let u = UInt8(ascii: "u")
}
