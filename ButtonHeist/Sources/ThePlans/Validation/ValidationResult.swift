public enum ValidationResult<Value: Sendable, Diagnostic: Sendable>: Sendable {
    case success(Value, diagnostics: [Diagnostic])
    case failure([Diagnostic])
}

public extension ValidationResult {
    var value: Value? {
        switch self {
        case .success(let value, _):
            return value
        case .failure:
            return nil
        }
    }

    var diagnostics: [Diagnostic] {
        switch self {
        case .success(_, let diagnostics), .failure(let diagnostics):
            return diagnostics
        }
    }

    var failureDiagnostics: [Diagnostic]? {
        switch self {
        case .success:
            return nil
        case .failure(let diagnostics):
            return diagnostics
        }
    }

    func map<NewValue: Sendable>(
        _ transform: (Value) -> NewValue
    ) -> ValidationResult<NewValue, Diagnostic> {
        switch self {
        case .success(let value, let diagnostics):
            return .success(transform(value), diagnostics: diagnostics)
        case .failure(let diagnostics):
            return .failure(diagnostics)
        }
    }

    func flatMap<NewValue: Sendable>(
        _ transform: (Value) -> ValidationResult<NewValue, Diagnostic>
    ) -> ValidationResult<NewValue, Diagnostic> {
        switch self {
        case .success(let value, let diagnostics):
            switch transform(value) {
            case .success(let transformedValue, let transformedDiagnostics):
                return .success(transformedValue, diagnostics: diagnostics + transformedDiagnostics)
            case .failure(let transformedDiagnostics):
                return .failure(diagnostics + transformedDiagnostics)
            }
        case .failure(let diagnostics):
            return .failure(diagnostics)
        }
    }

    func mapDiagnostics<NewDiagnostic: Sendable>(
        _ transform: (Diagnostic) -> NewDiagnostic
    ) -> ValidationResult<Value, NewDiagnostic> {
        switch self {
        case .success(let value, let diagnostics):
            return .success(value, diagnostics: diagnostics.map(transform))
        case .failure(let diagnostics):
            return .failure(diagnostics.map(transform))
        }
    }

    func get<Failure: Error>(
        orThrow makeError: ([Diagnostic]) -> Failure
    ) throws -> Value {
        switch self {
        case .success(let value, _):
            return value
        case .failure(let diagnostics):
            throw makeError(diagnostics)
        }
    }
}

extension Sequence {
    func collectValidationResults<Value: Sendable, Diagnostic: Sendable>()
        -> ValidationResult<[Value], Diagnostic>
        where Element == ValidationResult<Value, Diagnostic> {
        var values: [Value] = []
        var diagnostics: [Diagnostic] = []
        var hasFailure = false

        values.reserveCapacity(underestimatedCount)
        for result in self {
            switch result {
            case .success(let value, let resultDiagnostics):
                values.append(value)
                diagnostics.append(contentsOf: resultDiagnostics)
            case .failure(let resultDiagnostics):
                hasFailure = true
                diagnostics.append(contentsOf: resultDiagnostics)
            }
        }

        if hasFailure {
            return .failure(diagnostics)
        }
        return .success(values, diagnostics: diagnostics)
    }
}
