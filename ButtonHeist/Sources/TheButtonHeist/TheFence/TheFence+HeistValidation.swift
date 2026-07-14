import ThePlans

extension TheFence {
    func handleValidateHeist(_ request: ValidateHeistRequest) throws -> FenceResponse {
        switch HeistPlanning.loadValidatedPlanResult(from: request.source) {
        case .failure(let diagnostics):
            return .heistValidation(HeistValidationReport.rejectedPlan(
                diagnostics: diagnostics,
                argumentProvided: request.argumentProvided,
                lintMode: request.lintMode
            ))
        case .success(let plan, _):
            return .heistValidation(try validationReport(for: plan, request: request))
        }
    }

    private func validationReport(
        for plan: HeistPlan,
        request: ValidateHeistRequest
    ) throws -> HeistValidationReport {
        let invocation = invocationValidation(
            argument: request.argument,
            argumentProvided: request.argumentProvided,
            plan: plan
        )
        let lint = lintReport(for: plan, mode: request.lintMode)
        return HeistValidationReport(
            plan: .valid(HeistPlanSummary(plan)),
            invocation: invocation,
            lint: lint,
            canonicalPlan: try plan.canonicalSwiftDSL()
        )
    }

    private func invocationValidation(
        argument: HeistArgument,
        argumentProvided: Bool,
        plan: HeistPlan
    ) -> HeistInvocationValidation {
        switch HeistPlanning.validateRootArgumentResult(argument, for: plan) {
        case .success:
            return HeistInvocationValidation(state: .valid, argumentProvided: argumentProvided)
        case .failure(let diagnostics):
            return HeistInvocationValidation(
                state: .invalid,
                argumentProvided: argumentProvided,
                diagnostics: diagnostics
            )
        }
    }

    private func lintReport(
        for plan: HeistPlan,
        mode: HeistValidationLintMode
    ) -> HeistLintReport {
        guard let planLintMode = mode.planLintMode else {
            return HeistLintReport(mode: mode, state: .notEvaluated)
        }
        let findings = plan.lint(planLintMode)
        return HeistLintReport(
            mode: mode,
            state: findings.isEmpty ? .passed : .findings,
            findings: findings
        )
    }
}
