import ThePlans
import Foundation

// MARK: - Request Envelope

/// Wraps a client message with an optional request ID for response correlation.
/// When `requestId` is present, the server echoes it in the corresponding response
/// so the client can match request-response pairs. Push broadcasts have no requestId.
public struct RequestEnvelope: Codable, Sendable {
    /// Client's `buttonHeistVersion`. The handshake requires exact equality
    /// with the server's `buttonHeistVersion` — there is no separate wire
    /// protocol version.
    public let buttonHeistVersion: String
    public let requestId: String?
    public let message: ClientMessage

    public init(
        buttonHeistVersion: String = TheScore.buttonHeistVersion,
        requestId: String? = nil,
        message: ClientMessage
    ) {
        self.buttonHeistVersion = buttonHeistVersion
        self.requestId = requestId
        self.message = message
    }

    /// Decode a request envelope from JSON data. Returns nil on decode failure.
    public static func decoded(from data: Data) throws -> RequestEnvelope {
        try JSONDecoder().decode(RequestEnvelope.self, from: data)
    }
}

// MARK: - Client -> Server Messages

/// Messages sent from a connected client to the Inside Job server.
public enum ClientMessage: Codable, Sendable, Equatable {
    /// Version-negotiation hello sent immediately after receiving serverHello.
    case clientHello

    /// Authenticate with a token (sent after clientHello handshake completes)
    case authenticate(AuthenticatePayload)

    /// Request current semantic interface (app accessibility state)
    case requestInterface(InterfaceQuery)

    /// Ping for keepalive
    case ping

    /// Lightweight status command (identity + availability) for authenticated clients.
    case status

    // MARK: - Action Commands

    /// Activate an element
    case activate(ElementTarget)

    /// Increment an adjustable element (e.g., slider)
    case increment(ElementTarget)

    /// Decrement an adjustable element
    case decrement(ElementTarget)

    /// Perform a custom action on an element
    case performCustomAction(CustomActionTarget)

    /// Move through a custom accessibility rotor.
    case rotor(RotorTarget)

    // MARK: - Gesture Commands

    /// Tap at a point or element
    case oneFingerTap(TapTarget)

    /// Long press at a point or element
    case longPress(LongPressTarget)

    /// Swipe from one point to another
    case swipe(SwipeTarget)

    /// Drag from one point to another
    case drag(DragTarget)

    /// Type text character-by-character by tapping keyboard keys
    case typeText(TypeTextTarget)

    /// Perform a standard edit action (copy, paste, cut, select, selectAll, delete) on the first responder
    case editAction(EditActionTarget)

    /// Scroll via accessibility scroll action (bubbles up to nearest scroll view)
    case scroll(ScrollTarget)

    /// One-shot scroll: jump to a known element's position in its scroll view.
    /// Fails if the element has no recorded content-space position.
    case scrollToVisible(ScrollToVisibleTarget)

    /// Scroll the nearest scroll view ancestor to an edge (top, bottom, left, right)
    case scrollToEdge(ScrollToEdgeTarget)

    /// Resign first responder (dismiss keyboard)
    case resignFirstResponder

    /// Write text to the general pasteboard (in-app, avoids paste dialog for subsequent reads)
    case setPasteboard(SetPasteboardTarget)

    /// Read text from the general pasteboard
    case getPasteboard

    /// Wait until an accessibility predicate is satisfied.
    /// `present`/`absent` poll the current interface; `changed` rides through
    /// intermediate states until the change predicate is met.
    case wait(WaitTarget)

    /// Execute a typed heist plan with the root argument required by its parameter.
    case heistPlan(HeistPlanRun)

    /// Request a capture of the current screen
    case requestScreen

}

public struct HeistPlanRun: Codable, Sendable, Equatable {
    public let plan: HeistPlan
    public let argument: HeistArgument

    public init(plan: HeistPlan, argument: HeistArgument = .none) {
        self.plan = plan
        self.argument = argument
    }
}
