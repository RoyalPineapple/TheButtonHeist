import Foundation

extension FenceError: LocalizedError {
    static let actionTimeoutRecoveryHint =
        "The app may be busy on its main thread, processing a long-running UI update, " +
        "or sending a large response. The connection is preserved; retry the command on the same session."

    public var errorDescription: String? {
        let failure = diagnosticFailure
        guard let hint = failure.hint else { return failure.message }
        return """
            \(failure.message)
              Hint: \(hint)
            """
    }
}
