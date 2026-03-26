import Foundation

/// Bonjour service type for discovery
public let buttonHeistServiceType = "_buttonheist._tcp"

/// Protocol version for compatibility checking
public let protocolVersion = "6.2"

/// Explicit wire message discriminator used at JSON boundaries.
public enum WireMessageType: String, Codable, CaseIterable, Sendable {
    case clientHello
    case serverHello
    case protocolMismatch
    case authenticate
    case authRequired
    case authFailed
    case authApproved
    case info
    case requestInterface
    case interface
    case subscribe
    case unsubscribe
    case ping
    case pong
    case status
    case error
    case activate
    case increment
    case decrement
    case performCustomAction
    case actionResult
    case touchTap
    case touchLongPress
    case touchSwipe
    case touchDrag
    case touchPinch
    case touchRotate
    case touchTwoFingerTap
    case touchDrawPath
    case touchDrawBezier
    case typeText
    case editAction
    case setPasteboard
    case getPasteboard
    case scroll
    case scrollToVisible
    case scrollToEdge
    case resignFirstResponder
    case requestScreen
    case screen
    case waitForIdle
    case sessionLocked
    case startRecording
    case stopRecording
    case recordingStarted
    case recordingStopped
    case recording
    case recordingError
    case interaction
    case watch
}
