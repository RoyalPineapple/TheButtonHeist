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
        #expect(TheBrains.ScreenCaptureFailure.inactiveRuntime.errorKind == .accessibilityTreeUnavailable)
        #expect(TheBrains.ScreenCaptureFailure.accessibilityTreeUnavailable.errorKind == .accessibilityTreeUnavailable)
        #expect(TheBrains.ScreenCaptureFailure.appWindowUnavailable.errorKind == .actionFailed)
        #expect(TheBrains.ScreenCaptureFailure.accessibilitySnapshotRenderingFailed.errorKind == .actionFailed)
        #expect(TheBrains.ScreenCaptureFailure.pngEncodingFailed.errorKind == .actionFailed)
    }

    @Test func `interface query failures own exhaustive public error classification`() {
        #expect(TheBrains.InterfaceQueryFailure.rootViewUnavailable.errorKind == .accessibilityTreeUnavailable)
        #expect(TheBrains.InterfaceQueryFailure.inactiveRuntime.errorKind == .accessibilityTreeUnavailable)
        #expect(
            TheBrains.InterfaceQueryFailure.selection(.subtreeNotFound).errorKind
                == .validationError
        )
    }
}
#endif
