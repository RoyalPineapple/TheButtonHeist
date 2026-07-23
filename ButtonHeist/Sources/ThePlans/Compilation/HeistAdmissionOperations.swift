import Foundation

public enum HeistPlanSourceAdmission {
    public static func rejectRawStructuredJSONIRSourceFields(
        commandName: String,
        fields: Set<HeistPlanRejectedPublicSourceField>
    ) -> ValidationResult<Void, HeistBuildDiagnostic> {
        guard !fields.isEmpty else { return .success((), diagnostics: []) }
        return .failure([HeistAdmissionFailure.rawStructuredJSONIRFields(
            commandName: commandName,
            fields: fields.sorted { $0.rawValue < $1.rawValue }
        ).diagnostic])
    }

    public static func admit(
        commandName: String,
        path: String?,
        inlineDSL: String?,
        sourcePolicy: HeistPlanSourceAdmissionPolicy = .artifactOrInlineDSL
    ) -> ValidationResult<HeistPlanLoadRequest, HeistBuildDiagnostic> {
        switch (path, inlineDSL) {
        case (.some, .some):
            return .failure([HeistAdmissionFailure.multiplePlanSources(commandName: commandName).diagnostic])
        case (.none, .none):
            return .failure([HeistAdmissionFailure.missingPlanSource(commandName: commandName).diagnostic])
        case (.some(let path), .none):
            return .success(
                HeistPlanLoadRequest(commandName: commandName, source: .artifactPath(path)),
                diagnostics: []
            )
        case (.none, .some(let source)):
            guard sourcePolicy.acceptsInlineDSL else {
                return .failure([
                    HeistAdmissionFailure.inlineSourceNotAccepted(commandName: commandName).diagnostic,
                ])
            }
            return .success(
                HeistPlanLoadRequest(commandName: commandName, source: .inlineDSL(source)),
                diagnostics: []
            )
        }
    }
}

public enum HeistPlanLoading {
    public static func loadValidated(
        from request: HeistPlanLoadRequest
    ) -> ValidationResult<HeistPlan, HeistBuildDiagnostic> {
        switch request.source {
        case .artifactPath(let path):
            return loadValidatedArtifactPlanResult(path: path, commandName: request.commandName)
        case .inlineDSL(let source):
            return compileInlineButtonHeistSourceResult(source, commandName: request.commandName)
        }
    }
}

public enum HeistArgumentAdmission {
    public static func decodeJSON(
        _ data: Data,
        sourceURL: URL = URL(fileURLWithPath: "inline-heist-argument.json")
    ) -> ValidationResult<HeistArgument, HeistBuildDiagnostic> {
        do {
            return .success(try JSONDecoder().decode(HeistArgument.self, from: data), diagnostics: [])
        } catch {
            return .failure([HeistAdmissionFailure.invalidArgument(
                source: sourceURL.path,
                reason: String(describing: error)
            ).diagnostic])
        }
    }

    public static func validateRootArgument(
        _ argument: HeistArgument,
        for plan: HeistPlan
    ) -> ValidationResult<Void, HeistBuildDiagnostic> {
        do {
            _ = try HeistExecutionEnvironment.empty.binding(argument: argument, to: plan.parameter)
            return .success((), diagnostics: [])
        } catch {
            return .failure([HeistAdmissionFailure.invalidRootArgument(String(describing: error)).diagnostic])
        }
    }
}

package extension HeistAdmissionFailure {
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

private extension HeistPlanLoading {
    static func loadValidatedArtifactPlanResult(
        path: String,
        commandName: String
    ) -> ValidationResult<HeistPlan, HeistBuildDiagnostic> {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure([HeistAdmissionFailure.emptyPath(commandName: commandName).diagnostic])
        }

        let url = URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
        guard url.pathExtension.lowercased() == "heist" else {
            return .failure([HeistAdmissionFailure.unsupportedPath(commandName: commandName, path: path).diagnostic])
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
            return .failure([HeistAdmissionFailure.emptyInlineSource(commandName: commandName).diagnostic])
        }

        return HeistSourceCompilation.compileResult(
            source,
            sourceName: "\(commandName)-inline.plan"
        )
    }
}
