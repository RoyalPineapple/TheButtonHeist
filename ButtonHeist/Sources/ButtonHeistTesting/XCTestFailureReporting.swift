#if canImport(UIKit)
#if DEBUG
import XCTest

enum HeistXCTestIssue: CustomStringConvertible {
    case joinedSessionRequiresMainThread
    case requestConstructionFailed(Error)
    case synchronousHeistRequiresMainThread
    case synchronousOperationRequiresMainThread
    case operationFailed(Error)

    var description: String {
        switch self {
        case .joinedSessionRequiresMainThread:
            return "Joined heist sessions must stop on the main thread so the main run loop can be pumped."
        case .requestConstructionFailed(let error):
            return "Heist failed before execution: \(error)"
        case .synchronousHeistRequiresMainThread:
            return "runHeistSync must be called on the main thread so it can pump the main run loop."
        case .synchronousOperationRequiresMainThread:
            return "runHeistSyncOperation must be called on the main thread so it can pump the main run loop."
        case .operationFailed(let error):
            return String(describing: error)
        }
    }
}

func recordHeistXCTestIssue(
    _ issue: HeistXCTestIssue,
    file: StaticString,
    line: UInt
) {
    XCTFail(issue.description, file: file, line: line)
}
#endif // DEBUG
#endif // canImport(UIKit)
