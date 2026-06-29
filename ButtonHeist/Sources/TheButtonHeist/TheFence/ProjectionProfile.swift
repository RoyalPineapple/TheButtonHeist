import TheScore

@_spi(ButtonHeistInternals) public struct ProjectionLimits: Sendable, Equatable {
    public let visibleElementBudget: Int
    public let totalNodeBudget: Int
    public let deltaElementsPerBucket: Int
    public let screenPreviewElements: Int
    public let caseResults: Int
    public let failureInterfaceElements: Int

    public init(
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

    public static func current(
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

    public static func current(
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
}

@_spi(ButtonHeistInternals) public struct ProjectionProfile: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case summary
        case full
        case mcp
        case junit
    }

    public let kind: Kind
    public let limits: ProjectionLimits

    public init(kind: Kind, limits: ProjectionLimits) {
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
            limits: .current(deltaElementsPerBucket: 5, screenPreviewElements: 5, caseResults: 10)
        )
    }

    public static var junit: ProjectionProfile {
        ProjectionProfile(kind: .junit, limits: .current())
    }

    var interfaceDetail: InterfaceDetail {
        kind == .full ? .full : .summary
    }
}

enum ProjectionOmissionReason: String, Sendable {
    case rawAccessibilityTrace = "raw accessibility trace omitted from public heist report"
    case rawSubjectEvidence = "raw subject evidence omitted from public heist report"
    case scrollSubtreeElementBudget = "scroll-subtree-element-budget"
    case totalNodeBudget = "total-node-budget"
}
