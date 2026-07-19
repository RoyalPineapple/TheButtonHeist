import Testing

#if canImport(UIKit)
@testable import TheInsideJob
#endif

#if canImport(UIKit)
@Suite struct ScreenCaptureFailureMessageTests {
    @Test func `screen capture failures render stable boundary messages`() {
        #expect(
            TheBrains.ScreenCaptureFailure.inactiveRuntime.message
                == TheBrains.runtimeInactiveMessage
        )
        #expect(
            TheBrains.ScreenCaptureFailure.accessibilityTreeUnavailable.message
                == "Could not access accessibility tree"
        )
        #expect(
            TheBrains.ScreenCaptureFailure.appWindowUnavailable.message
                == "Could not access app window"
        )
        #expect(
            TheBrains.ScreenCaptureFailure.pngEncodingFailed.message
                == "Failed to encode screen as PNG"
        )
    }

    @Test func `screen capture failures own exhaustive public error classification`() {
        #expect(TheBrains.ScreenCaptureFailure.inactiveRuntime.actionFailureKind == .accessibilityTreeUnavailable)
        #expect(
            TheBrains.ScreenCaptureFailure.accessibilityTreeUnavailable.actionFailureKind
                == .accessibilityTreeUnavailable
        )
        #expect(TheBrains.ScreenCaptureFailure.appWindowUnavailable.actionFailureKind == .actionFailed)
        #expect(TheBrains.ScreenCaptureFailure.accessibilitySnapshotRenderingFailed.actionFailureKind == .actionFailed)
        #expect(TheBrains.ScreenCaptureFailure.pngEncodingFailed.actionFailureKind == .actionFailed)
    }

    @Test func `interface query failures own exhaustive public error classification`() {
        #expect(TheBrains.InterfaceQueryFailure.rootViewUnavailable.actionFailureKind == .accessibilityTreeUnavailable)
        #expect(TheBrains.InterfaceQueryFailure.inactiveRuntime.actionFailureKind == .accessibilityTreeUnavailable)
        #expect(
            TheBrains.InterfaceQueryFailure.selection(.subtreeNotFound).actionFailureKind
                == .validationError
        )
    }
}
#endif
