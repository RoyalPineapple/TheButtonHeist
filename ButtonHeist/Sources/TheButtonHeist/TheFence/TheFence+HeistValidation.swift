import ThePlans

extension TheFence {
    func handleValidateHeist(_ request: ValidateHeistRequest) throws -> FenceResponse {
        do {
            let plan = try HeistPlanLoading.loadValidated(from: request.source)
            return .heistValidation(try validationReport(for: plan, request: request))
        } catch let error as HeistPlanBuildError {
            return .heistValidation(HeistValidation.Report.rejectedPlan(
                diagnostics: error.diagnostics,
                argumentProvided: request.argumentProvided,
                lintMode: request.lintMode
            ))
        }
    }

    private func validationReport(
        for plan: HeistPlan,
        request: ValidateHeistRequest
    ) throws -> HeistValidation.Report {
        let invocation = invocationValidation(
            argument: request.argument,
            argumentProvided: request.argumentProvided,
            plan: plan
        )
        let lint = lintReport(for: plan, mode: request.lintMode)
        return HeistValidation.Report.evaluatedPlan(
            HeistValidation.PlanSummary(plan),
            invocation: invocation,
            argumentProvided: request.argumentProvided,
            lint: lint,
            canonicalPlan: try plan.canonicalSwiftDSL()
        )
    }

    private func invocationValidation(
        argument: HeistArgument,
        argumentProvided: Bool,
        plan: HeistPlan
    ) -> HeistValidation.Result<HeistValidation.InvocationSummary> {
        do {
            try HeistArgumentAdmission.validateRootArgument(argument, for: plan)
            return .valid(HeistValidation.InvocationSummary(argumentProvided: argumentProvided))
        } catch let error {
            return .invalid(error.diagnostics)
        }
    }

    private func lintReport(
        for plan: HeistPlan,
        mode: HeistValidationLintMode
    ) -> HeistValidation.Lint {
        guard let planLintMode = mode.planLintMode else {
            return .notEvaluated(mode: mode)
        }
        let findings = plan.lint(planLintMode)
        return findings.isEmpty ? .passed(mode: mode) : .findings(mode: mode, values: findings)
    }
}
