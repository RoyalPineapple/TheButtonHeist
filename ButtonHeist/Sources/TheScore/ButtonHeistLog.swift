import OSLog

package enum ButtonHeistLog {
    package enum Channel: Sendable {
        case handoff(Handoff)
        case score(Score)
    }

    package enum Handoff: String, Sendable {
        case config
        case driverIdentity = "driver-identity"
        case server
    }

    package enum Score: String, Sendable {
        case receipts
    }

    package static func logger(_ channel: Channel) -> Logger {
        Logger(subsystem: channel.subsystem.rawValue, category: channel.category)
    }
}

private extension ButtonHeistLog.Channel {
    var subsystem: ButtonHeistLogSubsystem {
        switch self {
        case .handoff:
            return .handoff
        case .score:
            return .score
        }
    }

    var category: String {
        switch self {
        case .handoff(let category):
            return category.rawValue
        case .score(let category):
            return category.rawValue
        }
    }
}

private enum ButtonHeistLogSubsystem: String {
    case handoff = "com.buttonheist.thehandoff"
    case score = "com.buttonheist.thescore"
}
