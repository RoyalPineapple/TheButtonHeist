import TheScore

extension TheFence {

    func decodeScrollActionDispatch(
        command: Command,
        input: some CommandArgumentReadable
    ) throws -> DecodedRequestDispatch {
        switch command {
        case .scroll:
            let direction = try input.schemaEnum("direction", as: ScrollDirection.self) ?? .down
            return try decodedExecutablePayload(.scroll(ScrollTarget(
                selection: input.scrollContainerSelection(),
                direction: direction
            )))
        case .scrollToVisible:
            return try decodedExecutablePayload(.scrollToVisible(ScrollToVisibleTarget(
                elementTarget: input.requiredElementTarget(command: .scrollToVisible)
            )))
        case .elementSearch:
            return try decodedExecutablePayload(.elementSearch(ElementSearchTarget(
                elementTarget: input.requiredElementTarget(command: .elementSearch),
                direction: input.schemaEnum("direction", as: ScrollSearchDirection.self) ?? .down
            )))
        case .scrollToEdge:
            let edge = try input.schemaEnum("edge", as: ScrollEdge.self) ?? .top
            return try decodedExecutablePayload(.scrollToEdge(ScrollToEdgeTarget(
                selection: input.scrollContainerSelection(),
                edge: edge
            )))
        default:
            throw FenceError.invalidRequest("Unexpected scroll action command: \(command.rawValue)")
        }
    }
}
