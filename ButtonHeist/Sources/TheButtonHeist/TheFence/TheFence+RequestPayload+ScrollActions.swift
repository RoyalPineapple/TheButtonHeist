import TheScore

extension TheFence {

    func decodeScrollActionDispatch(
        command: Command,
        input: ElementActionRequestInput
    ) throws -> DecodedRequestDispatch {
        switch command {
        case .scroll:
            let direction = try input.enumValue("direction", as: ScrollDirection.self) ?? .down
            return try decodedExecutablePayload(.scroll(ScrollTarget(
                selection: input.scrollContainerSelection(in: self),
                direction: direction
            )))
        case .scrollToVisible:
            return try decodedExecutablePayload(.scrollToVisible(ScrollToVisibleTarget(
                elementTarget: input.requiredElementTarget(command: .scrollToVisible, in: self)
            )))
        case .elementSearch:
            return try decodedExecutablePayload(.elementSearch(ElementSearchTarget(
                elementTarget: input.requiredElementTarget(command: .elementSearch, in: self),
                direction: input.enumValue("direction", as: ScrollSearchDirection.self) ?? .down
            )))
        case .scrollToEdge:
            let edge = try input.enumValue("edge", as: ScrollEdge.self) ?? .top
            return try decodedExecutablePayload(.scrollToEdge(ScrollToEdgeTarget(
                selection: input.scrollContainerSelection(in: self),
                edge: edge
            )))
        default:
            throw FenceError.invalidRequest("Unexpected scroll action command: \(command.rawValue)")
        }
    }
}
