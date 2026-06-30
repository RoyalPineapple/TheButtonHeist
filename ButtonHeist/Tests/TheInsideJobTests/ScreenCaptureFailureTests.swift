import Foundation
import Testing

#if canImport(UIKit)
@testable import TheInsideJob
#endif

@Suite struct ScreenCaptureFailureSourceShapeTests {
    @Test func `screen capture gateway carries typed failures`() throws {
        let source = try sourceFile(
            relativePath: "ButtonHeist/Sources/TheInsideJob/TheBrains/TheBrains+ScreenCapture.swift"
        )

        #expect(source.contains("enum ScreenCaptureFailure: Equatable, Sendable"))
        #expect(source.contains("case failure(ScreenCaptureFailure)"))
        #expect(!source.contains("case failure(String)"))
        #expect(!source.contains(#"return .failure(""#))
        #expect(!source.contains("return .failure(Self.runtimeInactiveMessage)"))
    }
}

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
}
#endif

private func sourceFile(relativePath: String) throws -> String {
    try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
