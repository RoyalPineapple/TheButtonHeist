import Foundation

#if os(macOS) || os(Linux)
enum HeistSwiftFileCompilerError: Error, Sendable, Equatable, CustomStringConvertible {
    case sourceFileNotFound(String)
    case packageRootNotFound
    case buildArtifactsNotFound(searched: [String], hint: String)
    case compileFailed(String, String)
    case executionFailed(String, String)
    case compileTimedOut(String, String)
    case executionTimedOut(String, String)
    case compileOutputLimitExceeded(String, stream: CompilerProcess.OutputStream, diagnostics: String)
    case executionOutputLimitExceeded(String, stream: CompilerProcess.OutputStream, diagnostics: String)
    case compilerTerminated(String, signal: Int32, diagnostics: String)
    case executionTerminated(String, signal: Int32, diagnostics: String)
    case invalidCompilerOutput(String)
    case runtimeSafetyFailed(String)

    var description: String {
        switch self {
        case .sourceFileNotFound(let path):
            return "Swift heist source file not found: \(path)"
        case .packageRootNotFound:
            return """
            could not locate built ThePlans artifacts or a local ButtonHeist package root containing Sources/ThePlans. \
            Install Button Heist with its heist-plan compiler artifacts, run the compiler from inside \
            a ButtonHeist checkout, or set HEIST_THEPLANS_BUILD_DIR to a directory holding built ThePlans artifacts \
            (Modules/ThePlans.swiftmodule or Modules/ThePlans.swiftinterface, plus ThePlans.build/*.swift.o).
            """
        case .buildArtifactsNotFound(let searched, let hint):
            let searchedList = searched.map { "  - \($0)" }.joined(separator: "\n")
            return """
            could not find built ThePlans artifacts for Swift compilation.
            searched:
            \(searchedList)
            \(hint)
            """
        case .compileFailed(let path, let diagnostics):
            return "failed to compile Swift heist source \(path): \(diagnostics)"
        case .executionFailed(let path, let diagnostics):
            return "compiled Swift heist source \(path) failed while evaluating entry: \(diagnostics)"
        case .compileTimedOut(let path, let diagnostics):
            return "timed out compiling Swift heist source \(path): \(diagnostics)"
        case .executionTimedOut(let path, let diagnostics):
            return "compiled Swift heist source \(path) timed out while evaluating entry: \(diagnostics)"
        case .compileOutputLimitExceeded(let path, let stream, let diagnostics):
            return """
            compiler for Swift heist source \(path) exceeded its \(stream.rawValue) output limit: \(diagnostics)
            """
        case .executionOutputLimitExceeded(let path, let stream, let diagnostics):
            return """
            compiled Swift heist source \(path) exceeded its \(stream.rawValue) output limit \
            while evaluating entry: \(diagnostics)
            """
        case .compilerTerminated(let path, let signal, let diagnostics):
            return "compiler for Swift heist source \(path) terminated by signal \(signal): \(diagnostics)"
        case .executionTerminated(let path, let signal, let diagnostics):
            return "compiled Swift heist source \(path) terminated by signal \(signal) while evaluating entry: \(diagnostics)"
        case .invalidCompilerOutput(let diagnostics):
            return "compiled Swift heist did not emit valid HeistPlan JSON: \(diagnostics)"
        case .runtimeSafetyFailed(let diagnostics):
            return "compiled Swift heist failed runtime safety: \(diagnostics)"
        }
    }
}

enum HeistSwiftFileCompilerProcessPhase {
    case compilation(String)
    case execution(String)

    func nonzeroExit(code: Int32, diagnostics: String) -> HeistSwiftFileCompilerError {
        let details = processDetails(prefix: "exit code \(code)", diagnostics: diagnostics)
        switch self {
        case .compilation(let path):
            return .compileFailed(path, details)
        case .execution(let path):
            return .executionFailed(path, details)
        }
    }

    func signaled(signal: Int32, diagnostics: String) -> HeistSwiftFileCompilerError {
        switch self {
        case .compilation(let path):
            return .compilerTerminated(path, signal: signal, diagnostics: diagnostics)
        case .execution(let path):
            return .executionTerminated(path, signal: signal, diagnostics: diagnostics)
        }
    }

    func timedOut(diagnostics: String) -> HeistSwiftFileCompilerError {
        switch self {
        case .compilation(let path):
            return .compileTimedOut(path, diagnostics)
        case .execution(let path):
            return .executionTimedOut(path, diagnostics)
        }
    }

    func outputLimitExceeded(
        stream: CompilerProcess.OutputStream,
        diagnostics: String
    ) -> HeistSwiftFileCompilerError {
        switch self {
        case .compilation(let path):
            return .compileOutputLimitExceeded(path, stream: stream, diagnostics: diagnostics)
        case .execution(let path):
            return .executionOutputLimitExceeded(path, stream: stream, diagnostics: diagnostics)
        }
    }

    private func processDetails(prefix: String, diagnostics: String) -> String {
        guard !diagnostics.isEmpty else { return prefix }
        return "\(prefix): \(diagnostics)"
    }
}

#endif
