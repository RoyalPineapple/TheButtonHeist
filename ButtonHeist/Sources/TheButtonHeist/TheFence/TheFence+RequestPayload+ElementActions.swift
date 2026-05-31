import TheScore

extension TheFence {

    static func decodedExecutablePayload(_ message: ClientMessage) -> DecodedRequestDispatch {
        Self.clientActionDispatch([message])
    }

}
