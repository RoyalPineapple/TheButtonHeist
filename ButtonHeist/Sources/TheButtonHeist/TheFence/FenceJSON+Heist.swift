import Foundation
import ThePlans

import TheScore

struct PublicHeistCatalogResponse: FencePublicJSONResponse {
    let status = PublicStatus.ok
    private let heists: [PublicHeistCatalogEntry]

    init(catalog: HeistDiscoveryCatalog) {
        heists = catalog.heists.map(PublicHeistCatalogEntry.init)
    }
}

struct PublicHeistDescriptionResponse: FencePublicJSONResponse {
    let status = PublicStatus.ok
    private let heist: PublicHeistDescription

    init(heist: HeistDescription) {
        self.heist = PublicHeistDescription(heist)
    }
}

struct PublicHeistValidationResponse: FencePublicJSONResponse {
    let status = PublicStatus.ok
    let admissible: Bool
    let plan: PublicHeistPlanValidation
    let invocation: PublicHeistInvocationValidation
    let lint: PublicHeistLintReport
    let buildDiagnostics: [PublicHeistBuildDiagnostic]
    let canonicalPlan: String?

    init(report: HeistValidationReport) {
        admissible = report.admissible
        plan = PublicHeistPlanValidation(report.plan)
        invocation = PublicHeistInvocationValidation(report.invocation)
        lint = PublicHeistLintReport(report.lint)
        buildDiagnostics = report.plan.diagnostics.map(PublicHeistBuildDiagnostic.init)
        canonicalPlan = report.canonicalPlan
    }
}

struct PublicHeistPlanValidation: Encodable {
    let valid: Bool
    let version: Int?
    let name: String?
    let parameter: HeistParameter?
    let definitionCount: Int?
    let topLevelStepCount: Int?

    init(_ validation: HeistPlanValidation) {
        switch validation {
        case .valid(let summary):
            valid = true
            version = summary.version
            name = summary.name
            parameter = summary.parameter
            definitionCount = summary.definitionCount
            topLevelStepCount = summary.topLevelStepCount
        case .invalid:
            valid = false
            version = nil
            name = nil
            parameter = nil
            definitionCount = nil
            topLevelStepCount = nil
        }
    }
}

struct PublicHeistInvocationValidation: Encodable {
    let state: String
    let argumentProvided: Bool
    let diagnostics: [PublicHeistBuildDiagnostic]

    init(_ validation: HeistInvocationValidation) {
        state = validation.state.rawValue
        argumentProvided = validation.argumentProvided
        diagnostics = validation.diagnostics.map(PublicHeistBuildDiagnostic.init)
    }
}

struct PublicHeistLintReport: Encodable {
    let mode: String
    let state: String
    let findings: [PublicHeistLintFinding]

    init(_ report: HeistLintReport) {
        mode = report.mode.rawValue
        state = report.state.rawValue
        findings = report.findings.map(PublicHeistLintFinding.init)
    }
}

struct PublicHeistLintFinding: Encodable {
    let severity: String
    let path: String
    let message: String
    let suggestion: String?

    init(_ finding: HeistPlanLintFinding) {
        severity = finding.severity.rawValue
        path = finding.path
        message = finding.message
        suggestion = finding.suggestion
    }
}

private struct PublicHeistCatalogEntry: Encodable {
    let name: String
    let role: HeistCatalogRole
    let parameterKind: HeistParameterKind
    let requiresArgument: Bool
    let summary: String?
    let tags: [String]
    let parameterName: HeistReferenceName?
    let nestedRunHeists: [String]?
    let actionCommands: [String]?
    let waitCount: Int?
    let expectationCount: Int?
    let semanticSurfaces: [String]?
    let validationStatus: HeistValidationStatus?

    init(_ entry: HeistCatalogEntry) {
        name = entry.name
        role = entry.role
        parameterKind = entry.parameterKind
        requiresArgument = entry.requiresArgument
        summary = entry.summary
        tags = entry.tags.map(\.heistDiscoveryDisplayValue)
        parameterName = entry.parameterName
        nestedRunHeists = entry.nestedRunHeists?.map(\.heistDiscoveryDisplayValue)
        actionCommands = entry.actionCommands?.map(\.heistDiscoveryDisplayValue)
        waitCount = entry.waitCount
        expectationCount = entry.expectationCount
        semanticSurfaces = entry.semanticSurfaces?.map(\.heistDiscoveryDisplayValue)
        validationStatus = entry.validationStatus
    }
}

private struct PublicHeistDescription: Encodable {
    let name: String
    let role: HeistCatalogRole
    let parameterKind: HeistParameterKind
    let parameterName: HeistReferenceName?
    let requiresArgument: Bool
    let summary: String?
    let validationStatus: HeistValidationStatus
    let semanticSurface: PublicHeistSemanticSurface

    init(_ description: HeistDescription) {
        name = description.name
        role = description.role
        parameterKind = description.parameterKind
        parameterName = description.parameterName
        requiresArgument = description.requiresArgument
        summary = description.summary
        validationStatus = description.validationStatus
        semanticSurface = PublicHeistSemanticSurface(description.semanticSurface)
    }
}

private struct PublicHeistSemanticSurface: Encodable {
    let actionCommands: [String]
    let targetPredicates: [String]
    let waits: [String]
    let expectations: [String]
    let nestedRunHeists: [String]
    let expectedEffects: [String]
    let semanticSurfaces: [String]

    init(_ surface: HeistSemanticSurface) {
        actionCommands = surface.actionCommands.map(\.heistDiscoveryDisplayValue)
        targetPredicates = surface.targetPredicates.map(\.heistDiscoveryDisplayValue)
        waits = surface.waits.map(\.heistDiscoveryDisplayValue)
        expectations = surface.expectations.map(\.heistDiscoveryDisplayValue)
        nestedRunHeists = surface.nestedRunHeists.map(\.heistDiscoveryDisplayValue)
        expectedEffects = surface.expectedEffects.map(\.heistDiscoveryDisplayValue)
        semanticSurfaces = surface.semanticSurfaces.map(\.heistDiscoveryDisplayValue)
    }
}
