import Foundation

extension AccessibilityTrace {
    var captureEndpointScreenName: String? {
        captures.last?.screenNameProjection
    }

    var captureEndpointScreenId: String? {
        captures.last?.screenIdProjection
    }
}

extension AccessibilityTrace.Capture {
    var screenNameProjection: String? {
        interface.elements
            .first(where: { $0.traits.contains(.header) })
            .flatMap(\.label)
    }

    var screenIdProjection: String? {
        context.screenId ?? interface.screenId
    }
}
