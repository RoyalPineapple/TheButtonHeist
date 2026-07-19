struct ClientNetworkAddress: Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }

    init(stringLiteral value: String) {
        self.init(value)
    }
}
