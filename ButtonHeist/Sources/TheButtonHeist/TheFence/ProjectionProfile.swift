import TheScore

private enum MCPProjectionLimits {
    static let deltaElementsPerBucket = 5
    static let screenPreviewElements = 5
    static let caseResults = 10
}

struct ProjectionLimits: Sendable, Equatable {
    let visibleElementBudget: Int
    let totalNodeBudget: Int
    let deltaElementsPerBucket: Int
    let screenPreviewElements: Int
    let caseResults: Int
    let failureInterfaceElements: Int

    init(
        visibleElementBudget: Int,
        totalNodeBudget: Int,
        deltaElementsPerBucket: Int,
        screenPreviewElements: Int,
        caseResults: Int,
        failureInterfaceElements: Int
    ) {
        self.visibleElementBudget = max(0, visibleElementBudget)
        self.totalNodeBudget = max(0, totalNodeBudget)
        self.deltaElementsPerBucket = max(0, deltaElementsPerBucket)
        self.screenPreviewElements = max(0, screenPreviewElements)
        self.caseResults = max(0, caseResults)
        self.failureInterfaceElements = max(0, failureInterfaceElements)
    }

    static func current(
        deltaElementsPerBucket: Int = Int.max,
        screenPreviewElements: Int = Int.max,
        caseResults: Int = Int.max,
        failureInterfaceElements: Int = HeistFailureDiagnostics.defaultElementLimit
    ) -> ProjectionLimits {
        ProjectionLimits(
            visibleElementBudget: ButtonHeistRuntimeKnobs.current.visibleElementBudget,
            totalNodeBudget: ButtonHeistRuntimeKnobs.current.totalNodeBudget,
            deltaElementsPerBucket: deltaElementsPerBucket,
            screenPreviewElements: screenPreviewElements,
            caseResults: caseResults,
            failureInterfaceElements: failureInterfaceElements
        )
    }

    static func current(
        visibleElementBudget: Int,
        totalNodeBudget: Int,
        deltaElementsPerBucket: Int = Int.max,
        screenPreviewElements: Int = Int.max,
        caseResults: Int = Int.max,
        failureInterfaceElements: Int = HeistFailureDiagnostics.defaultElementLimit
    ) -> ProjectionLimits {
        ProjectionLimits(
            visibleElementBudget: visibleElementBudget,
            totalNodeBudget: totalNodeBudget,
            deltaElementsPerBucket: deltaElementsPerBucket,
            screenPreviewElements: screenPreviewElements,
            caseResults: caseResults,
            failureInterfaceElements: failureInterfaceElements
        )
    }

    var boundedForMCP: ProjectionLimits {
        ProjectionLimits(
            visibleElementBudget: visibleElementBudget,
            totalNodeBudget: totalNodeBudget,
            deltaElementsPerBucket: min(deltaElementsPerBucket, MCPProjectionLimits.deltaElementsPerBucket),
            screenPreviewElements: min(screenPreviewElements, MCPProjectionLimits.screenPreviewElements),
            caseResults: min(caseResults, MCPProjectionLimits.caseResults),
            failureInterfaceElements: failureInterfaceElements
        )
    }
}

@_spi(ButtonHeistInternals) public struct ProjectionProfile: Sendable, Equatable {
    enum Kind: String, Sendable, Equatable {
        case summary
        case full
        case mcp
        case junit
    }

    let kind: Kind
    let limits: ProjectionLimits

    init(kind: Kind, limits: ProjectionLimits) {
        self.kind = kind
        self.limits = limits
    }

    public static var summary: ProjectionProfile {
        ProjectionProfile(kind: .summary, limits: .current())
    }

    public static var full: ProjectionProfile {
        ProjectionProfile(kind: .full, limits: .current())
    }

    public static var mcp: ProjectionProfile {
        ProjectionProfile(
            kind: .mcp,
            limits: .current(
                deltaElementsPerBucket: MCPProjectionLimits.deltaElementsPerBucket,
                screenPreviewElements: MCPProjectionLimits.screenPreviewElements,
                caseResults: MCPProjectionLimits.caseResults
            )
        )
    }

    public static var junit: ProjectionProfile {
        ProjectionProfile(kind: .junit, limits: .current())
    }

    var interfaceDetail: InterfaceDetail {
        kind == .full ? .full : .summary
    }

    var heistReport: ProjectionProfile {
        kind == .summary
            ? ProjectionProfile(kind: .mcp, limits: limits.boundedForMCP)
            : self
    }
}

enum ProjectionOmissionReason: String, Sendable {
    case rawAccessibilityTrace = "raw accessibility trace omitted from public heist report"
    case rawSubjectEvidence = "raw subject evidence omitted from public heist report"
    case scrollSubtreeElementBudget = "scroll-subtree-element-budget"
    case totalNodeBudget = "total-node-budget"
}
