import Foundation

public enum HeistBuildDiagnosticKind: String, Sendable, Equatable {
    case error
    case warning
}

public enum HeistBuildPhase: String, Sendable, Equatable {
    case dslBuild = "dsl_build"
    case sourceCompilation = "source_compilation"
    case swiftCompilation = "swift_compilation"
    case planValidation = "plan_validation"
    case planning
}

public struct HeistBuildDiagnosticCode: RawRepresentable, Sendable, Hashable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    public var description: String {
        rawValue
    }
}

public extension HeistBuildDiagnosticCode {
    static let dslInvalidActionExpectation: Self = "heist.dsl.invalid_action_expectation"
    static let dslInvalidActionUntil: Self = "heist.dsl.invalid_action_until"
    static let dslInvalidDefinition: Self = "heist.dsl.invalid_definition"
    static let dslInvalidForEachElement: Self = "heist.dsl.invalid_for_each_element"
    static let dslInvalidForEachString: Self = "heist.dsl.invalid_for_each_string"
    static let dslInvalidInvocationExpectation: Self = "heist.dsl.invalid_invocation_expectation"
    static let dslInvalidInvocationPath: Self = "heist.dsl.invalid_invocation_path"
    static let dslInvalidRepeatUntil: Self = "heist.dsl.invalid_repeat_until"

    static let sourceInvalidSyntax: Self = "heist.source.invalid_syntax"
    static let sourceWaitForGate: Self = "heist.source.wait_for_gate"
    static let nonDurableAction: Self = "heist.plan.non_durable_action"
    static let planRuntimeSafety: Self = "heist.plan.runtime_safety"

    static let planningMissingPlanSource: Self = "heist.planning.missing_plan_source"
    static let planningMultiplePlanSources: Self = "heist.planning.multiple_plan_sources"
    static let planningInlineSourceNotAccepted: Self = "heist.planning.inline_source_not_accepted"
    static let planningEmptyPath: Self = "heist.planning.empty_path"
    static let planningUnsupportedPath: Self = "heist.planning.unsupported_path"
    static let planningEmptyInlineSource: Self = "heist.planning.empty_inline_source"
    static let planningRawJSONIRFields: Self = "heist.planning.raw_json_ir_fields"
    static let planningInvalidPlanSource: Self = "heist.planning.invalid_plan_source"
    static let planningInvalidArtifact: Self = "heist.planning.invalid_artifact"
    static let planningInvalidArgument: Self = "heist.planning.invalid_argument"
    static let planningInvalidRootArgument: Self = "heist.planning.invalid_root_argument"

    static let performWrongStepCount: Self = "heist.perform.wrong_step_count"
    static let performUnsupportedStep: Self = "heist.perform.unsupported_step"
}

public struct HeistBuildSourceSpan: Sendable, Equatable, CustomStringConvertible {
    public let sourceName: String
    public let offset: Int
    public let line: Int
    public let column: Int
    public let length: Int?

    public init(
        sourceName: String,
        offset: Int,
        line: Int,
        column: Int,
        length: Int? = nil
    ) {
        self.sourceName = sourceName
        self.offset = offset
        self.line = line
        self.column = column
        self.length = length
    }

    public var description: String {
        "\(sourceName):\(line):\(column)"
    }
}

public struct HeistBuildDiagnostic: Sendable, Equatable, CustomStringConvertible {
    public let code: HeistBuildDiagnosticCode
    public let kind: HeistBuildDiagnosticKind
    public let phase: HeistBuildPhase
    public let sourceSpan: HeistBuildSourceSpan?
    public let path: String?
    public let message: String
    public let hint: String?

    public init(
        code: HeistBuildDiagnosticCode,
        kind: HeistBuildDiagnosticKind = .error,
        phase: HeistBuildPhase,
        sourceSpan: HeistBuildSourceSpan? = nil,
        path: String? = nil,
        message: String,
        hint: String? = nil
    ) {
        self.code = code
        self.kind = kind
        self.phase = phase
        self.sourceSpan = sourceSpan
        self.path = path
        self.message = message
        self.hint = hint
    }

    public init(
        code: String,
        kind: HeistBuildDiagnosticKind = .error,
        phase: HeistBuildPhase,
        sourceSpan: HeistBuildSourceSpan? = nil,
        path: String? = nil,
        message: String,
        hint: String? = nil
    ) {
        self.init(
            code: HeistBuildDiagnosticCode(rawValue: code),
            kind: kind,
            phase: phase,
            sourceSpan: sourceSpan,
            path: path,
            message: message,
            hint: hint
        )
    }

    public var severity: Severity {
        switch kind {
        case .error:
            return .error
        case .warning:
            return .warning
        }
    }

    public var source: HeistBuildSourceLocation? {
        guard let sourceSpan else { return nil }
        return HeistBuildSourceLocation(
            url: URL(fileURLWithPath: sourceSpan.sourceName),
            line: sourceSpan.line,
            column: sourceSpan.column
        )
    }

    public var description: String {
        renderedMessage
    }

    public var renderedMessage: String {
        let location: String
        if let sourceSpan {
            location = "\(sourceSpan): "
        } else if let path {
            location = "\(path): "
        } else {
            location = ""
        }
        let suffix = hint.map { " Hint: \($0)" } ?? ""
        return "\(kind.rawValue): \(location)\(message)\(suffix)"
    }
}

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

extension HeistBuildDiagnostic {
    static func dslBuild(
        code: HeistBuildDiagnosticCode,
        path: String? = nil,
        message: String,
        hint: String? = nil
    ) -> HeistBuildDiagnostic {
        HeistBuildDiagnostic(
            code: code,
            phase: .dslBuild,
            path: path,
            message: message,
            hint: hint
        )
    }

    func withPath(_ path: String) -> HeistBuildDiagnostic {
        HeistBuildDiagnostic(
            code: code,
            kind: kind,
            phase: phase,
            sourceSpan: sourceSpan,
            path: path,
            message: message,
            hint: hint
        )
    }
}

extension HeistPlanAdmissionCandidate {
    func runtimeSafetyValidationResult(
        limits: HeistPlanRuntimeSafetyLimits = .standard
    ) -> ValidationResult<HeistPlan, HeistBuildDiagnostic> {
        var validator = HeistPlanRuntimeSafetyValidator(limits: limits)
        let plan = uncheckedPlanForRuntimeSafetyValidation()
        let failures = validator.failures(in: plan)
        guard failures.isEmpty else {
            return .failure(failures.map(\.diagnostic))
        }
        return .success(plan, diagnostics: [])
    }
}

extension HeistPlanRuntimeSafetyError {
    var diagnostics: [HeistBuildDiagnostic] {
        failures.map(\.diagnostic)
    }
}

public extension HeistPlanning {
    static func admitPlanSourceResult(
        from request: HeistPlanSourceAdmissionRequest
    ) -> ValidationResult<HeistPlanLoadRequest, HeistBuildDiagnostic> {
        do {
            return .success(try admitPlanSource(from: request), diagnostics: [])
        } catch let error as HeistPlanningError {
            return .failure(error.diagnostics)
        } catch {
            return .failure([HeistPlanningError.invalidPlanSource(String(describing: error)).diagnostic])
        }
    }

    static func loadValidatedPlanResult(
        from request: HeistPlanSourceAdmissionRequest
    ) -> ValidationResult<HeistPlan, HeistBuildDiagnostic> {
        admitPlanSourceResult(from: request).flatMap { loadValidatedPlanResult(from: $0) }
    }

    static func loadValidatedPlanResult(
        from request: HeistPlanLoadRequest
    ) -> ValidationResult<HeistPlan, HeistBuildDiagnostic> {
        switch request.source {
        case .artifactPath(let path):
            return loadValidatedArtifactPlanResult(path: path, commandName: request.commandName)
        case .inlineDSL(let source):
            return compileInlineButtonHeistSourceResult(source, commandName: request.commandName)
        }
    }

    static func decodeArgumentJSONResult(
        _ data: Data,
        sourceURL: URL = URL(fileURLWithPath: "inline-heist-argument.json")
    ) -> ValidationResult<HeistArgument, HeistBuildDiagnostic> {
        do {
            return .success(try JSONDecoder().decode(HeistArgument.self, from: data), diagnostics: [])
        } catch {
            return .failure([HeistPlanningError.invalidArgument(
                source: sourceURL.path,
                reason: String(describing: error)
            ).diagnostic])
        }
    }

    static func validateRootArgumentResult(
        _ argument: HeistArgument,
        for plan: HeistPlan
    ) -> ValidationResult<Void, HeistBuildDiagnostic> {
        do {
            _ = try HeistExecutionEnvironment.empty.binding(argument: argument, to: plan.parameter)
            return .success((), diagnostics: [])
        } catch {
            return .failure([HeistPlanningError.invalidRootArgument(String(describing: error)).diagnostic])
        }
    }
}

public extension HeistPlanningError {
    var diagnostics: [HeistBuildDiagnostic] {
        [diagnostic]
    }

    var diagnostic: HeistBuildDiagnostic {
        switch self {
        case .missingPlanSource:
            return planningDiagnostic(code: .planningMissingPlanSource, message: description)
        case .multiplePlanSources:
            return planningDiagnostic(code: .planningMultiplePlanSources, message: description)
        case .inlineSourceNotAccepted:
            return planningDiagnostic(code: .planningInlineSourceNotAccepted, message: description)
        case .emptyPath:
            return planningDiagnostic(code: .planningEmptyPath, message: description)
        case .unsupportedPath(_, let path):
            return planningDiagnostic(
                code: .planningUnsupportedPath,
                path: path,
                message: description
            )
        case .emptyInlineSource:
            return planningDiagnostic(code: .planningEmptyInlineSource, message: description)
        case .rawStructuredJSONIRFields:
            return planningDiagnostic(code: .planningRawJSONIRFields, message: description)
        case .invalidPlanSource:
            return planningDiagnostic(code: .planningInvalidPlanSource, message: description)
        case .invalidArgument(let source, _):
            return planningDiagnostic(
                code: .planningInvalidArgument,
                path: source,
                message: description
            )
        case .invalidRootArgument:
            return planningDiagnostic(code: .planningInvalidRootArgument, message: description)
        }
    }

    private func planningDiagnostic(
        code: HeistBuildDiagnosticCode,
        path: String? = nil,
        message: String
    ) -> HeistBuildDiagnostic {
        HeistBuildDiagnostic(
            code: code,
            phase: .planning,
            path: path,
            message: message
        )
    }
}

private extension HeistPlanning {
    static func loadValidatedArtifactPlanResult(
        path: String,
        commandName: String
    ) -> ValidationResult<HeistPlan, HeistBuildDiagnostic> {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure([HeistPlanningError.emptyPath(commandName: commandName).diagnostic])
        }

        let url = URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
        guard url.pathExtension.lowercased() == "heist" else {
            return .failure([HeistPlanningError.unsupportedPath(commandName: commandName, path: path).diagnostic])
        }

        do {
            return .success(try HeistArtifactCodec.read(from: url).plan, diagnostics: [])
        } catch let error as HeistArtifactCodecError {
            return .failure([HeistBuildDiagnostic(
                code: .planningInvalidArtifact,
                phase: .planning,
                path: url.path,
                message: error.description
            )])
        } catch {
            return .failure([HeistBuildDiagnostic(
                code: .planningInvalidArtifact,
                phase: .planning,
                path: url.path,
                message: String(describing: error)
            )])
        }
    }

    static func compileInlineButtonHeistSourceResult(
        _ source: String,
        commandName: String
    ) -> ValidationResult<HeistPlan, HeistBuildDiagnostic> {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure([HeistPlanningError.emptyInlineSource(commandName: commandName).diagnostic])
        }

        return HeistPlanSourceCompiler().compileResult(
            source,
            sourceName: "\(commandName)-inline.plan"
        )
    }
}

private extension HeistPlanRuntimeSafetyFailure {
    private static let durableHeistActionContract = "durable heist action"

    var diagnostic: HeistBuildDiagnostic {
        HeistBuildDiagnostic(
            code: diagnosticCode,
            phase: .planValidation,
            path: path,
            message: "\(contract); observed \(observed)",
            hint: correction
        )
    }

    var diagnosticCode: HeistBuildDiagnosticCode {
        contract == Self.durableHeistActionContract ? .nonDurableAction : .planRuntimeSafety
    }
}

extension HeistPlanSourceParser {
    mutating func rejectForbiddenStatementSyntax() throws {
        guard case .identifier(let name) = currentToken.kind else { return }
        switch name {
        case "import":
            throw error(currentToken, "import declarations are not supported in ButtonHeist source")
        case "let", "var":
            throw error(
                currentToken,
                "\(name) declarations are not supported inside ButtonHeist DSL bodies; wrap the heist in Swift and pass values through parameters or RunHeist"
            )
        case "func":
            throw error(currentToken, "function declarations are not supported in ButtonHeist source")
        case "class", "struct", "protocol", "extension", "actor":
            throw error(currentToken, "type declarations are not supported in ButtonHeist source")
        case "enum":
            throw error(currentToken, "enum declarations are Swift wrapper code, not ButtonHeist DSL body syntax")
        case "if":
            throw error(currentToken, "native Swift if/else is not supported inside ButtonHeist DSL bodies. Use If { Case(...) { ... } Else { ... } }")
        case "repeat":
            throw error(currentToken, "native Swift repeat/while is not supported; use RepeatUntil for bounded repeated actions")
        case "for", "while", "switch":
            throw error(
                currentToken,
                "native Swift \(name) statements are not supported; use ButtonHeist constructs such as If, WaitFor, ForEach, and RepeatUntil"
            )
        case "try":
            if let correction = runHeistCorrectionAfterTryPrefix(startingAt: index + 1) {
                throw error(
                    currentToken,
                    "`try` is only allowed in Swift wrapper code, not inside ButtonHeist DSL bodies. Use \(correction)."
                )
            }
            throw error(currentToken, "`try` is only allowed in Swift wrapper code, not inside ButtonHeist DSL bodies")
        case "await":
            throw error(currentToken, "`await` is not supported in ButtonHeist source")
        default:
            return
        }
    }

    func runHeistCorrectionAfterTryPrefix(startingAt startIndex: Int) -> String? {
        guard tokens.indices.contains(startIndex),
              case .identifier(let first) = tokens[startIndex].kind else {
            return nil
        }
        var names = [first]
        var cursor = startIndex + 1
        while tokens.indices.contains(cursor), tokens[cursor].isSymbol(".") {
            let nameIndex = cursor + 1
            guard tokens.indices.contains(nameIndex),
                  case .identifier(let name) = tokens[nameIndex].kind else {
                return nil
            }
            names.append(name)
            cursor = nameIndex + 1
        }
        guard names.count > 1,
              tokens.indices.contains(cursor),
              tokens[cursor].isSymbol("(") else {
            return nil
        }
        return "RunHeist(\(quote(names.joined(separator: "."))))"
    }

    func quote(_ value: String) -> String {
        if let data = try? JSONEncoder().encode(value),
           let encoded = String(data: data, encoding: .utf8) {
            return encoded
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    func error(
        _ token: HeistPlanSourceToken,
        _ message: String
    ) -> HeistPlanSourceCompilerError {
        HeistPlanSourceCompilerError(
            message: message,
            sourceName: sourceName,
            offset: token.marker.offset,
            line: token.marker.line,
            column: token.marker.column,
            length: token.marker.length
        )
    }

    func currentScope() -> HeistPlanSourceScope {
        scope
    }

    mutating func restoreScope(_ previousScope: HeistPlanSourceScope) {
        scope = previousScope
    }

    mutating func bindScopedParameter(_ parameter: HeistParameter, localName: String) {
        guard let parameterName = parameter.name else { return }
        switch parameter {
        case .string:
            scope.bindString(localName: localName, referenceName: parameterName)
        case .elementTarget:
            scope.bindTarget(localName: localName, referenceName: parameterName)
        case .none:
            break
        }
    }

    mutating func bindScopedReference(
        _ binding: HeistPlanSourceBinding,
        localName: String,
        referenceName: HeistReferenceName
    ) {
        switch binding {
        case .string:
            scope.bindString(localName: localName, referenceName: referenceName)
        case .target:
            scope.bindTarget(localName: localName, referenceName: referenceName)
        }
    }
}

struct ParsedHeistBody {
    let definitions: [HeistPlanAdmissionCandidate]
    let steps: [HeistStepAdmissionCandidate]
}

struct HeistTryPrefix {
    let token: HeistPlanSourceToken
    let forced: Bool
}

struct HeistPlanSourceScope: Equatable {
    var stringRefs: [String: HeistReferenceName] = [:]
    var targetRefs: [String: HeistReferenceName] = [:]

    mutating func bindString(localName: String, referenceName: HeistReferenceName) {
        stringRefs[localName] = referenceName
    }

    mutating func bindTarget(localName: String, referenceName: HeistReferenceName) {
        targetRefs[localName] = referenceName
    }

    func stringReference(for localName: String) -> HeistReferenceName? {
        stringRefs[localName]
    }

    func targetReference(for localName: String) -> HeistReferenceName? {
        targetRefs[localName]
    }
}

enum HeistPlanSourceBinding {
    case string
    case target
}

enum HeistDefinitionParameterKind {
    case none
    case string
    case elementTarget
}
