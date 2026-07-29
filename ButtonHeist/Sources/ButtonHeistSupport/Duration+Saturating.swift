package extension Duration {
    static func saturatingSeconds(_ seconds: Double) -> Self {
        precondition(
            seconds.isFinite && seconds >= 0,
            "duration seconds must be finite and non-negative"
        )
        return .seconds(min(seconds, maximumScheduledSeconds))
    }

    private static var maximumScheduledSeconds: Double {
        Double(Int64.max / 2)
    }
}
