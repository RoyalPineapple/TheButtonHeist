import Foundation

public extension HeistPlanning {
    static func rejectRawStructuredJSONIRSourceFieldsResult(
        commandName: String,
        fields: Set<HeistPlanRejectedPublicSourceField>
    ) -> ValidationResult<Void, HeistBuildDiagnostic> {
        guard !fields.isEmpty else { return .success((), diagnostics: []) }
        return .failure([HeistPlanningError.rawStructuredJSONIRFields(
            commandName: commandName,
            fields: fields.sorted { $0.rawValue < $1.rawValue }
        ).diagnostic])
    }

    static func admittedSourceResult(
        commandName: String,
        path: String?,
        inlineDSL: String?
    ) -> ValidationResult<HeistPlanSource, HeistBuildDiagnostic> {
        switch (path, inlineDSL) {
        case (.some, .some):
            return .failure([HeistPlanningError.multiplePlanSources(commandName: commandName).diagnostic])
        case (.none, .none):
            return .failure([HeistPlanningError.missingPlanSource(commandName: commandName).diagnostic])
        case (.some(let path), .none):
            return .success(.artifactPath(path), diagnostics: [])
        case (.none, .some(let source)):
            return .success(.inlineDSL(source), diagnostics: [])
        }
    }

    static func admissionRequestResult(
        commandName: String,
        path: String?,
        inlineDSL: String?,
        sourcePolicy: HeistPlanSourceAdmissionPolicy = .artifactOrInlineDSL
    ) -> ValidationResult<HeistPlanSourceAdmissionRequest, HeistBuildDiagnostic> {
        admittedSourceResult(commandName: commandName, path: path, inlineDSL: inlineDSL).map {
            HeistPlanSourceAdmissionRequest(
                commandName: commandName,
                source: $0,
                sourcePolicy: sourcePolicy
            )
        }
    }

    static func admitPlanSourceResult(
        from request: HeistPlanSourceAdmissionRequest
    ) -> ValidationResult<HeistPlanLoadRequest, HeistBuildDiagnostic> {
        switch request.source {
        case .artifactPath(let path):
            return .success(
                HeistPlanLoadRequest(commandName: request.commandName, source: .artifactPath(path)),
                diagnostics: []
            )
        case .inlineDSL(let source):
            guard request.sourcePolicy.acceptsInlineDSL else {
                return .failure([
                    HeistPlanningError.inlineSourceNotAccepted(commandName: request.commandName).diagnostic,
                ])
            }
            return .success(
                HeistPlanLoadRequest(commandName: request.commandName, source: .inlineDSL(source)),
                diagnostics: []
            )
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
