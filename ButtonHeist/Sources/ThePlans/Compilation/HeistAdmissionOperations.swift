import Foundation

public enum HeistPlanSourceAdmission {
    public static func rejectRawStructuredJSONIRSourceFields(
        commandName: String,
        fields: Set<HeistPlanRejectedPublicSourceField>
    ) throws(HeistPlanBuildError) {
        guard !fields.isEmpty else { return }
        throw HeistPlanBuildError(diagnostics: [
            HeistAdmissionFailure.rawStructuredJSONIRFields(
                commandName: commandName,
                fields: fields.sorted { $0.rawValue < $1.rawValue }
            ).diagnostic,
        ])
    }

    public static func admit(
        commandName: String,
        path: String?,
        inlineDSL: String?,
        sourcePolicy: HeistPlanSourceAdmissionPolicy = .artifactOrInlineDSL
    ) throws(HeistPlanBuildError) -> HeistPlanLoadRequest {
        switch (path, inlineDSL) {
        case (.some, .some):
            throw HeistPlanBuildError(
                diagnostics: HeistAdmissionFailure.multiplePlanSources(commandName: commandName).diagnostics
            )
        case (.none, .none):
            throw HeistPlanBuildError(
                diagnostics: HeistAdmissionFailure.missingPlanSource(commandName: commandName).diagnostics
            )
        case (.some(let path), .none):
            return HeistPlanLoadRequest(commandName: commandName, source: .artifactPath(path))
        case (.none, .some(let source)):
            guard sourcePolicy.acceptsInlineDSL else {
                throw HeistPlanBuildError(
                    diagnostics: HeistAdmissionFailure.inlineSourceNotAccepted(commandName: commandName).diagnostics
                )
            }
            return HeistPlanLoadRequest(commandName: commandName, source: .inlineDSL(source))
        }
    }
}

public enum HeistPlanLoading {
    public static func loadValidated(
        from request: HeistPlanLoadRequest
    ) throws(HeistPlanBuildError) -> HeistPlan {
        switch request.source {
        case .artifactPath(let path):
            return try loadValidatedArtifactPlan(path: path, commandName: request.commandName)
        case .inlineDSL(let source):
            return try compileInlineButtonHeistSource(source, commandName: request.commandName)
        }
    }
}

public enum HeistArgumentAdmission {
    public static func decodeJSON(
        _ data: Data,
        sourceURL: URL = URL(fileURLWithPath: "inline-heist-argument.json")
    ) throws(HeistPlanBuildError) -> HeistArgument {
        do {
            return try JSONDecoder().decode(HeistArgument.self, from: data)
        } catch {
            throw HeistPlanBuildError(diagnostics: [
                HeistAdmissionFailure.invalidArgument(
                    source: sourceURL.path,
                    reason: String(describing: error)
                ).diagnostic,
            ])
        }
    }

    public static func validateRootArgument(
        _ argument: HeistArgument,
        for plan: HeistPlan
    ) throws(HeistPlanBuildError) {
        do {
            _ = try HeistExecutionEnvironment.empty.binding(argument: argument, to: plan.parameter)
        } catch {
            throw HeistPlanBuildError(
                diagnostics: HeistAdmissionFailure.invalidRootArgument(String(describing: error)).diagnostics
            )
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
    static func loadValidatedArtifactPlan(
        path: String,
        commandName: String
    ) throws(HeistPlanBuildError) -> HeistPlan {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw HeistPlanBuildError(
                diagnostics: HeistAdmissionFailure.emptyPath(commandName: commandName).diagnostics
            )
        }

        let url = URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
        guard url.pathExtension.lowercased() == "heist" else {
            throw HeistPlanBuildError(
                diagnostics: HeistAdmissionFailure.unsupportedPath(commandName: commandName, path: path).diagnostics
            )
        }

        do {
            return try HeistArtifactCodec.read(from: url).plan
        } catch let error as HeistArtifactCodecError {
            throw HeistPlanBuildError(diagnostics: [HeistBuildDiagnostic(
                code: .planningInvalidArtifact,
                phase: .planning,
                path: url.path,
                message: error.description
            )])
        } catch {
            throw HeistPlanBuildError(diagnostics: [HeistBuildDiagnostic(
                code: .planningInvalidArtifact,
                phase: .planning,
                path: url.path,
                message: String(describing: error)
            )])
        }
    }

    static func compileInlineButtonHeistSource(
        _ source: String,
        commandName: String
    ) throws(HeistPlanBuildError) -> HeistPlan {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HeistPlanBuildError(
                diagnostics: HeistAdmissionFailure.emptyInlineSource(commandName: commandName).diagnostics
            )
        }

        return try HeistSourceCompilation.compile(source, sourceName: "\(commandName)-inline.plan")
    }
}
