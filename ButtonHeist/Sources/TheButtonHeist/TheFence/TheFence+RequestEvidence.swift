import TheScore

private struct ActivateEvidenceArguments: Encodable {
    let action: String?
    let count: Int?
}

extension TheFence.ParsedRequest {
    func heistRecordingElementTarget() throws -> ElementTarget? {
        try heistRecordingProjection().elementTarget
    }

    func heistRecordingCoordinateOnly() throws -> Bool {
        try heistRecordingProjection().coordinateOnly
    }

    func heistRecordingArguments() throws -> [String: HeistValue] {
        try heistRecordingProjection().arguments
    }

    private func heistRecordingProjection() throws -> HeistRecordingProjection {
        guard let messages = executableMessages else { return .empty }
        guard command == .activate else {
            return try messages.first?.heistRecordingProjection() ?? .empty
        }
        return try .activate(messages)
    }
}

private extension HeistRecordingProjection {
    static func activate(_ messages: [ClientMessage]) throws -> HeistRecordingProjection {
        guard let first = messages.first else { return .empty }
        switch first {
        case .activate(let target):
            return .target(elementTarget: target)
        case .increment(let target):
            return .target(
                arguments: try ActivateEvidenceArguments(
                    action: ElementAction.increment.description,
                    count: messages.count > 1 ? messages.count : nil
                ).heistEvidenceArguments(),
                elementTarget: target
            )
        case .decrement(let target):
            return .target(
                arguments: try ActivateEvidenceArguments(
                    action: ElementAction.decrement.description,
                    count: messages.count > 1 ? messages.count : nil
                ).heistEvidenceArguments(),
                elementTarget: target
            )
        case .performCustomAction(let target):
            return .target(
                arguments: try ActivateEvidenceArguments(action: target.actionName, count: nil)
                    .heistEvidenceArguments(),
                elementTarget: target.elementTarget
            )
        default:
            return try first.heistRecordingProjection()
        }
    }
}

private extension ClientMessage {
    func heistRecordingProjection() throws -> HeistRecordingProjection {
        switch self {
        case .activate(let target), .increment(let target), .decrement(let target):
            return .target(elementTarget: target)
        case .performCustomAction(let target):
            return .target(
                arguments: try target.heistEvidenceArguments(),
                elementTarget: target.elementTarget
            )
        case .rotor(let target):
            return try .target(arguments: target.heistEvidenceArguments(), elementTarget: target.elementTarget)
        case .typeText(let target):
            return try .target(arguments: target.heistEvidenceArguments(), elementTarget: target.elementTarget)
        case .editAction(let target):
            return try HeistRecordingProjection(arguments: target.heistEvidenceArguments())
        case .setPasteboard(let target):
            return try HeistRecordingProjection(arguments: target.heistEvidenceArguments())
        case .oneFingerTap(let target):
            return try target.heistRecordingProjection()
        case .longPress(let target):
            return try target.heistRecordingProjection()
        case .swipe(let target):
            return try target.heistRecordingProjection()
        case .drag(let target):
            return try target.heistRecordingProjection()
        case .pinch(let target):
            return try target.heistRecordingProjection()
        case .rotate(let target):
            return try target.heistRecordingProjection()
        case .twoFingerTap(let target):
            return try target.heistRecordingProjection()
        case .drawPath(let target):
            return try HeistRecordingProjection(arguments: target.heistEvidenceArguments(), coordinateOnly: true)
        case .drawBezier(let target):
            return try HeistRecordingProjection(arguments: target.heistEvidenceArguments(), coordinateOnly: true)
        case .scroll(let target):
            return try .target(arguments: target.heistEvidenceArguments(), elementTarget: target.elementTarget)
        case .scrollToVisible(let target):
            return .target(elementTarget: target.elementTarget)
        case .elementSearch(let target):
            return try .target(arguments: target.heistEvidenceArguments(), elementTarget: target.elementTarget)
        case .scrollToEdge(let target):
            return try .target(arguments: target.heistEvidenceArguments(), elementTarget: target.elementTarget)
        case .waitFor(let target):
            return try .target(arguments: target.heistEvidenceArguments(), elementTarget: target.elementTarget)
        case .waitForChange(let target):
            return try HeistRecordingProjection(arguments: target.heistEvidenceArguments())
        default:
            return .empty
        }
    }
}
