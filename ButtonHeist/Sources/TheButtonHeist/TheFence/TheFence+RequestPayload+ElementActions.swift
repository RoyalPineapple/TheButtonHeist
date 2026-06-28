import TheScore

extension TheFence {

    static func decodedExecutablePayload(_ message: RuntimeActionMessage) -> DecodedRequestDispatch {
        Self.runtimeActionDispatch([message])
    }

}
