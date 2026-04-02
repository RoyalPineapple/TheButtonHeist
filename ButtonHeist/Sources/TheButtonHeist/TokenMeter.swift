import Foundation

@ButtonHeistActor
public struct TokenMeter: Sendable {
    public private(set) var cumulativeTokens: Int = 0
    public private(set) var responseCount: Int = 0

    public static func estimateTokens(_ text: String) -> Int {
        max(1, text.utf8.count / 4)
    }

    @discardableResult
    public mutating func record(_ text: String) -> Int {
        let tokens = Self.estimateTokens(text)
        cumulativeTokens += tokens
        responseCount += 1
        return tokens
    }

    public mutating func reset() {
        cumulativeTokens = 0
        responseCount = 0
    }

    public func formatFooter(responseTokens: Int) -> String {
        "[tokens: ~\(responseTokens) | session: ~\(cumulativeTokens) (\(responseCount) responses)]"
    }
}
