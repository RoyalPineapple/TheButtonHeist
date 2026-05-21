import Foundation

import TheScore

extension FenceResponse {

    func compactActionResult(_ result: ActionResult, expectation: ExpectationResult?) -> String {
        guard result.success else {
            if case .scrollSearch(let search) = result.payload {
                return Self.compactScrollSearchNotFound(
                    search,
                    method: result.method,
                    errorKind: Self.compactActionErrorKind(result),
                    screenId: result.screenId
                )
            }
            return Self.compactActionFailure(result)
        }

        var text: String
        switch result.payload {
        case .scrollSearch(let search):
            text = Self.compactScrollSearchFound(search, method: result.method)
        case .rotor(let search):
            text = Self.compactRotor(search)
        case .value, .explore, .none:
            if let delta = result.accessibilityDelta {
                text = Self.compactDelta(delta, method: result.method.rawValue)
            } else {
                text = "\(result.method.rawValue): ok"
            }
        }
        if let screenId = result.screenId {
            text = "\(screenId) | \(text)"
        }
        if case .value(let value) = result.payload {
            text += "\nvalue: \"\(value)\""
        }
        if let expectation, !expectation.met {
            text += "\n[expectation FAILED: got \(expectation.actual ?? "nil")]"
            if let hint = Self.compactExpectationFailureHint(expectation) {
                text += "\nhint: \(hint)"
            }
        }
        return text
    }

    private static func compactRotor(_ search: RotorResult) -> String {
        var text = "rotor \(search.direction.rawValue): \(search.rotor)"
        if let element = search.foundElement {
            text += "\n  \(compactElementLine(element))"
        }
        if let range = search.textRange {
            text += "\n  textRange=\(range.rangeDescription)"
            if let rangeText = range.text {
                text += " \"\(rangeText)\""
            }
        }
        return text
    }

    private static func compactExpectationFailureHint(_ expectation: ExpectationResult) -> String? {
        guard expectation.expectation == .screenChanged, expectation.actual == "elementsChanged" else {
            return nil
        }
        return "screen_changed requires a screen-level transition; " +
            "use elements_changed for same-screen element updates " +
            "or wait_for_change when the UI may settle asynchronously"
    }

    private static func compactActionFailure(_ result: ActionResult) -> String {
        let message = result.message ?? result.method.rawValue
        let errorCode = Self.actionFailureDetails(result)?.errorCode ?? compactActionErrorKind(result).rawValue
        var text = "\(result.method.rawValue): error[\(errorCode)]: \(message)"
        if let screenId = result.screenId {
            text = "\(screenId) | \(text)"
        }
        return text
    }

    private static func compactActionErrorKind(_ result: ActionResult) -> ErrorKind {
        if let errorKind = result.errorKind {
            return errorKind
        }
        if case .scrollSearch = result.payload {
            return .elementNotFound
        }
        switch result.method {
        case .elementNotFound, .elementDeallocated:
            return .elementNotFound
        default:
            return .actionFailed
        }
    }

    private static func compactScrollSearchFound(
        _ search: ScrollSearchResult,
        method: ActionMethod
    ) -> String {
        let commandName = method.compactScrollSearchCommandName
        var header: String
        if search.scrollCount == 0 {
            header = "\(commandName): already visible"
        } else {
            let itemInfo = scrollSearchItemInfo(search)
            header = "\(commandName): found after \(search.scrollCount) scrolls\(itemInfo)"
        }
        if let element = search.foundElement {
            header += "\n  \(compactElementLine(element))"
        }
        return header
    }

    private static func compactScrollSearchNotFound(
        _ search: ScrollSearchResult,
        method: ActionMethod,
        errorKind: ErrorKind,
        screenId: String?
    ) -> String {
        let commandName = method.compactScrollSearchCommandName
        var text: String
        if search.exhaustive {
            let itemInfo = scrollSearchItemInfo(search)
            text = "\(commandName): error[\(errorKind.rawValue)]: not found\(itemInfo) (exhaustive)"
        } else if search.scrollCount > 0 {
            let itemInfo = scrollSearchItemInfo(search)
            text = "\(commandName): error[\(errorKind.rawValue)]: not found after \(search.scrollCount) scrolls\(itemInfo)"
        } else {
            text = "\(commandName): error[\(errorKind.rawValue)]: not found"
        }
        if let screenId {
            text = "\(screenId) | \(text)"
        }
        return text
    }

    private static func scrollSearchItemInfo(_ search: ScrollSearchResult) -> String {
        if let total = search.totalItems {
            let percentage = total > 0 ? Int(Double(search.uniqueElementsSeen) / Double(total) * 100) : 0
            return " (\(search.uniqueElementsSeen)/\(total) items seen, \(percentage)%)"
        } else if search.uniqueElementsSeen > 0 {
            return " (\(search.uniqueElementsSeen) unique elements seen)"
        }
        return ""
    }

}

private extension ActionMethod {
    var compactScrollSearchCommandName: String {
        switch self {
        case .elementSearch:
            return ScrollMode.search.canonicalCommand
        case .scrollToVisible:
            return ScrollMode.toVisible.canonicalCommand
        default:
            return rawValue
        }
    }
}
