#if canImport(UIKit)
#if DEBUG

/// Every string settlement emits, in one place.
///
/// Two audiences share this file. `Terminal` is the log vocabulary: grepped,
/// stable, never translated. Everything else is what a caller reads when a run
/// did not do what was asked. Keeping both here means a word never gets spelled
/// two ways by two files that did not know about each other.
///
/// A string with nothing to fill in is a computed var; one that takes a payload
/// is a func. That is the only distinction — both are the same kind of thing,
/// and the signature says whether the caller has to supply anything.
internal enum Strings {

    /// Why a run ended without doing what was asked.
    ///
    /// There is only one failure — the clock ran out — so there is only one
    /// thing to say. Which predicate it ran out on is the whole content of the
    /// message; everything behind that one was never asked.
    internal enum Timeout {
        static func waitingOn(_ tip: String) -> String {
            "timed out while waiting on \(tip)"
        }

        static func stillWaitingOn(_ tip: String) -> String {
            "still waiting on: \(tip)"
        }

        static func settlementElapsed(_ milliseconds: Any) -> String {
            "settlement timed out after \(milliseconds)ms"
        }

        static func settlementElapsed(_ milliseconds: Any, waitingOn tip: String) -> String {
            "\(settlementElapsed(milliseconds)) while waiting on \(tip)"
        }

        static func dispatchIncomplete(_ milliseconds: Any) -> String {
            "action dispatch did not complete before settlement deadline after \(milliseconds)ms"
        }
    }

    /// What the run was looking for, and what it saw instead.
    internal enum Diagnostic {
        static var waitingToAppear: String { " waiting for element to appear" }
        static var waitingToDisappear: String { " waiting for element to disappear" }
        static var elementNotFound: String { "element not found" }
        static var elementStillPresent: String { "element still present" }
        static var none: String { "none" }

        static var nextStep: String {
            "Next: get_interface() to inspect current elements, "
                + "then retry wait with an exact predicate."
        }

        static func expected(_ target: String) -> String {
            "expected: \(target)"
        }

        static func interfaceElementCount(_ count: Int) -> String {
            "interface: \(count) elements"
        }

        static func lastResult(_ result: String) -> String {
            "last result: \(result)"
        }

        static func candidateDidNotMatch(_ candidate: String, _ predicate: String) -> String {
            "observed accessibility candidate \(candidate) did not match \(predicate)"
        }
    }

    /// Things that went wrong before any predicate could be asked.
    internal enum Failure {
        static var treeCaptureFailed: String { "Could not capture accessibility tree after action" }
        static var actionDispatchFailed: String { "action dispatch failed" }

        static func cancelled(_ milliseconds: Any) -> String {
            "cancelled after \(milliseconds)ms"
        }

        static func settlementCancelled(_ milliseconds: Any) -> String {
            "settlement cancelled after \(milliseconds)ms"
        }
    }

    /// The terminal log line's vocabulary.
    ///
    /// This is machine-readable output, so the words are fixed and the shape is
    /// `field=value`. A value with something to say about itself renders as
    /// `detail(payload)`.
    internal enum Terminal {
        static var prefix: String { "settlement terminal" }
        static var fieldSeparator: String { " " }
    }

    /// The field names of one terminal log line.
    internal enum TerminalField: String {
        case command
        case predicate
        case observation
        case dispatch
        case readiness
        case handoff
        case outcome
        case elapsedMs

        func pair(_ value: Any) -> String {
            "\(rawValue)=\(value)"
        }
    }

    /// Every fixed word a line can carry. Anything with a payload renders
    /// through `TerminalDetail`; these are the bare states.
    internal enum TerminalTerm: String {
        case settled
        case satisfied
        case notRequired
        case notApplicable
        case none
        case pending
        case cancelled
        case succeeded
        case captureRequested
        case dispatchFailed
        case baselineUnavailable
        case currentState
        case observation
        case action
    }

    /// A word that names what it is about: `waiting(the "Pay" button)`.
    internal enum TerminalDetail: String {
        case waiting
        case timedOut
        case viewportExitFailed
        case failed
        case established
        case admitted
        case captureFailed

        func callAsFunction(_ payload: Any) -> String {
            "\(rawValue)(\(payload))"
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
