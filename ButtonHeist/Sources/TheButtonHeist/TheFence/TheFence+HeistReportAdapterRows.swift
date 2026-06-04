import TheScore

// Linear rows are derived from structured report nodes for compact/playback/JUnit
// adapters. Product report surfaces should consume HeistReportProjection.nodes directly.
struct HeistReportAdapterRow {
    let index: Int
    let node: HeistReportNode

    var commandName: String {
        node.action?.commandName ?? node.kind.reportName
    }

    var fenceCommand: TheFence.Command? {
        node.action?.fenceCommand
    }

    var target: ElementTarget? {
        node.action?.target
    }

    var finalActionResult: ActionResult? {
        node.action?.finalActionResult
    }

    var failureMessage: String? {
        switch node.status {
        case .passed, .warned:
            return nil
        case .skipped, .failed:
            break
        }
        if let message = node.message {
            return message
        }
        if let result = finalActionResult, !result.success {
            return result.message ?? "action failed"
        }
        if node.expectation?.met == false {
            return node.expectation?.actual ?? "expectation not met"
        }
        if node.kind == .waitForCases,
           node.caseSelection?.timedOut == true,
           node.caseSelection?.elseRan != true {
            return "wait_for_cases timed out"
        }
        if let reason = node.forEachResult?.failureReason {
            return reason
        }
        return "heist step failed"
    }

    static func rows(from nodes: [HeistReportNode]) -> [Self] {
        nodes.flatMap(Self.flatten(node:))
            .enumerated()
            .map { index, row in Self(index: index, node: row.node) }
    }

    private static func flatten(node: HeistReportNode) -> [Self] {
        let row = Self(index: 0, node: node)
        switch node.kind {
        case .forEachElement, .forEachString:
            return [row]
        case .action, .wait, .conditional, .waitForCases, .forEachIteration, .warn, .fail, .heist, .invoke:
            return [row] + node.children.flatMap(Self.flatten(node:))
        }
    }
}
