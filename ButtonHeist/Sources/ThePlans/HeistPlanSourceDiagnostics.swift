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

public enum HeistKnownBuildDiagnosticCode: String, Sendable, Hashable, CaseIterable {
    case dslInvalidActionExpectation = "heist.dsl.invalid_action_expectation"
    case dslInvalidActionUntil = "heist.dsl.invalid_action_until"
    case dslInvalidDefinition = "heist.dsl.invalid_definition"
    case dslInvalidForEachElement = "heist.dsl.invalid_for_each_element"
    case dslInvalidForEachString = "heist.dsl.invalid_for_each_string"
    case dslInvalidInvocationExpectation = "heist.dsl.invalid_invocation_expectation"
    case dslInvalidInvocationPath = "heist.dsl.invalid_invocation_path"
    case dslInvalidRepeatUntil = "heist.dsl.invalid_repeat_until"

    case sourceInvalidSyntax = "heist.source.invalid_syntax"
    case sourceWaitForGate = "heist.source.wait_for_gate"
    case nonDurableAction = "heist.plan.non_durable_action"
    case planRuntimeSafety = "heist.plan.runtime_safety"

    case planningMissingPlanSource = "heist.planning.missing_plan_source"
    case planningMultiplePlanSources = "heist.planning.multiple_plan_sources"
    case planningInlineSourceNotAccepted = "heist.planning.inline_source_not_accepted"
    case planningEmptyPath = "heist.planning.empty_path"
    case planningUnsupportedPath = "heist.planning.unsupported_path"
    case planningEmptyInlineSource = "heist.planning.empty_inline_source"
    case planningRawJSONIRFields = "heist.planning.raw_json_ir_fields"
    case planningInvalidPlanSource = "heist.planning.invalid_plan_source"
    case planningInvalidArtifact = "heist.planning.invalid_artifact"
    case planningInvalidArgument = "heist.planning.invalid_argument"
    case planningInvalidRootArgument = "heist.planning.invalid_root_argument"

    case performWrongStepCount = "heist.perform.wrong_step_count"
    case performUnsupportedStep = "heist.perform.unsupported_step"

    case swiftCompilationFailed = "heist.swift_compilation.failed"
    case swiftCompilationUnsupportedPlatform = "heist.swift_compilation.unsupported_platform"
    case swiftCompilationCancelled = "heist.swift_compilation.cancelled"
    case swiftCompilationInvalidEntry = "heist.swift_compilation.invalid_entry"
    case swiftCompilationSourceNotFound = "heist.swift_compilation.source_not_found"
    case swiftCompilationPackageRootNotFound = "heist.swift_compilation.package_root_not_found"
    case swiftCompilationBuildArtifactsNotFound = "heist.swift_compilation.build_artifacts_not_found"
    case swiftCompilationCompileFailed = "heist.swift_compilation.compile_failed"
    case swiftCompilationExecutionFailed = "heist.swift_compilation.execution_failed"
    case swiftCompilationInvalidOutput = "heist.swift_compilation.invalid_output"

    case directoryNoSources = "heist.directory.no_sources"
    case directoryCancelled = "heist.directory.cancelled"
    case directoryNotDirectory = "heist.directory.not_directory"
    case directoryUnsupportedSourceFile = "heist.directory.unsupported_source_file"

    case catalogAnonymousCapability = "heist.catalog.anonymous_capability"
    case catalogDuplicateCapability = "heist.catalog.duplicate_capability"
    case catalogInvalidEntry = "heist.catalog.invalid_entry"
}

public struct HeistBuildDiagnosticCode: Sendable, Hashable, CustomStringConvertible {
    public let rawValue: String

    private init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ knownCode: HeistKnownBuildDiagnosticCode) {
        self.init(knownCode.rawValue)
    }

    public static func externalBoundaryRawCode(_ rawValue: String) -> Self {
        Self(rawValue)
    }

    public var knownCode: HeistKnownBuildDiagnosticCode? {
        HeistKnownBuildDiagnosticCode(rawValue: rawValue)
    }

    public var description: String {
        rawValue
    }
}

public extension HeistBuildDiagnosticCode {
    static let dslInvalidActionExpectation = Self(HeistKnownBuildDiagnosticCode.dslInvalidActionExpectation)
    static let dslInvalidActionUntil = Self(HeistKnownBuildDiagnosticCode.dslInvalidActionUntil)
    static let dslInvalidDefinition = Self(HeistKnownBuildDiagnosticCode.dslInvalidDefinition)
    static let dslInvalidForEachElement = Self(HeistKnownBuildDiagnosticCode.dslInvalidForEachElement)
    static let dslInvalidForEachString = Self(HeistKnownBuildDiagnosticCode.dslInvalidForEachString)
    static let dslInvalidInvocationExpectation = Self(HeistKnownBuildDiagnosticCode.dslInvalidInvocationExpectation)
    static let dslInvalidInvocationPath = Self(HeistKnownBuildDiagnosticCode.dslInvalidInvocationPath)
    static let dslInvalidRepeatUntil = Self(HeistKnownBuildDiagnosticCode.dslInvalidRepeatUntil)

    static let sourceInvalidSyntax = Self(HeistKnownBuildDiagnosticCode.sourceInvalidSyntax)
    static let sourceWaitForGate = Self(HeistKnownBuildDiagnosticCode.sourceWaitForGate)
    static let nonDurableAction = Self(HeistKnownBuildDiagnosticCode.nonDurableAction)
    static let planRuntimeSafety = Self(HeistKnownBuildDiagnosticCode.planRuntimeSafety)

    static let planningMissingPlanSource = Self(HeistKnownBuildDiagnosticCode.planningMissingPlanSource)
    static let planningMultiplePlanSources = Self(HeistKnownBuildDiagnosticCode.planningMultiplePlanSources)
    static let planningInlineSourceNotAccepted = Self(HeistKnownBuildDiagnosticCode.planningInlineSourceNotAccepted)
    static let planningEmptyPath = Self(HeistKnownBuildDiagnosticCode.planningEmptyPath)
    static let planningUnsupportedPath = Self(HeistKnownBuildDiagnosticCode.planningUnsupportedPath)
    static let planningEmptyInlineSource = Self(HeistKnownBuildDiagnosticCode.planningEmptyInlineSource)
    static let planningRawJSONIRFields = Self(HeistKnownBuildDiagnosticCode.planningRawJSONIRFields)
    static let planningInvalidPlanSource = Self(HeistKnownBuildDiagnosticCode.planningInvalidPlanSource)
    static let planningInvalidArtifact = Self(HeistKnownBuildDiagnosticCode.planningInvalidArtifact)
    static let planningInvalidArgument = Self(HeistKnownBuildDiagnosticCode.planningInvalidArgument)
    static let planningInvalidRootArgument = Self(HeistKnownBuildDiagnosticCode.planningInvalidRootArgument)

    static let performWrongStepCount = Self(HeistKnownBuildDiagnosticCode.performWrongStepCount)
    static let performUnsupportedStep = Self(HeistKnownBuildDiagnosticCode.performUnsupportedStep)
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
        code: HeistKnownBuildDiagnosticCode,
        kind: HeistBuildDiagnosticKind = .error,
        phase: HeistBuildPhase,
        sourceSpan: HeistBuildSourceSpan? = nil,
        path: String? = nil,
        message: String,
        hint: String? = nil
    ) {
        self.code = HeistBuildDiagnosticCode(code)
        self.kind = kind
        self.phase = phase
        self.sourceSpan = sourceSpan
        self.path = path
        self.message = message
        self.hint = hint
    }

    public init(
        externalBoundaryRawCode rawCode: String,
        kind: HeistBuildDiagnosticKind = .error,
        phase: HeistBuildPhase,
        sourceSpan: HeistBuildSourceSpan? = nil,
        path: String? = nil,
        message: String,
        hint: String? = nil
    ) {
        self.code = .externalBoundaryRawCode(rawCode)
        self.kind = kind
        self.phase = phase
        self.sourceSpan = sourceSpan
        self.path = path
        self.message = message
        self.hint = hint
    }

    fileprivate init(
        preservingCode code: HeistBuildDiagnosticCode,
        kind: HeistBuildDiagnosticKind,
        phase: HeistBuildPhase,
        sourceSpan: HeistBuildSourceSpan?,
        path: String?,
        message: String,
        hint: String?
    ) {
        self.code = code
        self.kind = kind
        self.phase = phase
        self.sourceSpan = sourceSpan
        self.path = path
        self.message = message
        self.hint = hint
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

    public var title: String {
        code.title
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

public extension HeistBuildDiagnosticCode {
    var title: String {
        switch knownCode {
        case .dslInvalidActionExpectation:
            return "Invalid action expectation"
        case .dslInvalidActionUntil:
            return "Invalid action until clause"
        case .dslInvalidDefinition:
            return "Invalid heist definition"
        case .dslInvalidForEachElement:
            return "Invalid element loop"
        case .dslInvalidForEachString:
            return "Invalid string loop"
        case .dslInvalidInvocationExpectation:
            return "Invalid RunHeist expectation"
        case .dslInvalidInvocationPath:
            return "Invalid RunHeist path"
        case .dslInvalidRepeatUntil:
            return "Invalid repeat-until"
        case .sourceInvalidSyntax:
            return "Invalid ButtonHeist source"
        case .sourceWaitForGate:
            return "Invalid WaitFor source"
        case .nonDurableAction:
            return "Non-durable action"
        case .planRuntimeSafety:
            return "Plan semantic validation failed"
        case .performWrongStepCount:
            return "Invalid perform step count"
        case .performUnsupportedStep:
            return "Unsupported perform step"
        case .planningMissingPlanSource,
             .planningMultiplePlanSources,
             .planningInlineSourceNotAccepted,
             .planningEmptyPath,
             .planningUnsupportedPath,
             .planningEmptyInlineSource,
             .planningRawJSONIRFields,
             .planningInvalidPlanSource,
             .planningInvalidArtifact,
             .planningInvalidArgument,
             .planningInvalidRootArgument,
             .swiftCompilationFailed,
             .swiftCompilationUnsupportedPlatform,
             .swiftCompilationCancelled,
             .swiftCompilationInvalidEntry,
             .swiftCompilationSourceNotFound,
             .swiftCompilationPackageRootNotFound,
             .swiftCompilationBuildArtifactsNotFound,
             .swiftCompilationCompileFailed,
             .swiftCompilationExecutionFailed,
             .swiftCompilationInvalidOutput,
             .directoryNoSources,
             .directoryCancelled,
             .directoryNotDirectory,
             .directoryUnsupportedSourceFile,
             .catalogAnonymousCapability,
             .catalogDuplicateCapability,
             .catalogInvalidEntry,
             .none:
            break
        }
        return rawValue
            .split(separator: ".")
            .last
            .map { String($0).replacingOccurrences(of: "_", with: " ") }
            ?? rawValue
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
    static let heistPathComponentHint =
        "Use a non-empty dot-separated heist capability name with Swift-style identifier components."

    static func dslBuild(
        code: HeistKnownBuildDiagnosticCode,
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

    static func invalidDefinitionPath(
        _ path: String,
        error: Error,
        phase: HeistBuildPhase,
        sourceSpan: HeistBuildSourceSpan? = nil
    ) -> HeistBuildDiagnostic {
        HeistBuildDiagnostic(
            code: .dslInvalidDefinition,
            phase: phase,
            sourceSpan: sourceSpan,
            path: pathForDiagnostic(path),
            message: "HeistDef path is invalid: \(String(describing: error))",
            hint: heistPathComponentHint
        )
    }

    static func invalidInvocationPath(
        _ path: String,
        error: Error,
        phase: HeistBuildPhase,
        sourceSpan: HeistBuildSourceSpan? = nil
    ) -> HeistBuildDiagnostic {
        HeistBuildDiagnostic(
            code: .dslInvalidInvocationPath,
            phase: phase,
            sourceSpan: sourceSpan,
            path: pathForDiagnostic(path),
            message: "RunHeist name is invalid: \(String(describing: error))",
            hint: heistPathComponentHint
        )
    }

    func withPath(_ path: String) -> HeistBuildDiagnostic {
        HeistBuildDiagnostic(
            preservingCode: code,
            kind: kind,
            phase: phase,
            sourceSpan: sourceSpan,
            path: path,
            message: message,
            hint: hint
        )
    }

    private static func pathForDiagnostic(_ path: String) -> String? {
        path.isEmpty ? nil : path
    }
}

extension HeistPlanAdmissionCandidate {
    func runtimeSafetyValidationResult(
        limits: HeistPlanRuntimeSafetyLimits = .standard
    ) -> ValidationResult<HeistPlan, HeistBuildDiagnostic> {
        semanticValidationResult(limits: limits)
    }
}

extension HeistPlanRuntimeSafetyError {
    var diagnostics: [HeistBuildDiagnostic] {
        failures.map(\.diagnostic)
    }
}

public extension HeistPlanning {
    static func rejectRawStructuredJSONIRFieldsResult(
        commandName: String,
        fields: Set<String>
    ) -> ValidationResult<Void, HeistBuildDiagnostic> {
        do {
            try rejectRawStructuredJSONIRFields(commandName: commandName, fields: fields)
            return .success((), diagnostics: [])
        } catch let error as HeistPlanningError {
            return .failure(error.diagnostics)
        } catch {
            return .failure([HeistPlanningError.invalidPlanSource(String(describing: error)).diagnostic])
        }
    }

    static func admissionRequestResult(
        commandName: String,
        path: String?,
        inlineDSL: String?,
        sourcePolicy: HeistPlanSourceAdmissionPolicy = .artifactOrInlineDSL
    ) -> ValidationResult<HeistPlanSourceAdmissionRequest, HeistBuildDiagnostic> {
        do {
            return .success(try admissionRequest(
                commandName: commandName,
                path: path,
                inlineDSL: inlineDSL,
                sourcePolicy: sourcePolicy
            ), diagnostics: [])
        } catch let error as HeistPlanningError {
            return .failure(error.diagnostics)
        } catch {
            return .failure([HeistPlanningError.invalidPlanSource(String(describing: error)).diagnostic])
        }
    }

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
        code: HeistKnownBuildDiagnosticCode,
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

    var diagnosticCode: HeistKnownBuildDiagnosticCode {
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

    func sourceSpan(for token: HeistPlanSourceToken) -> HeistBuildSourceSpan {
        HeistBuildSourceSpan(
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
