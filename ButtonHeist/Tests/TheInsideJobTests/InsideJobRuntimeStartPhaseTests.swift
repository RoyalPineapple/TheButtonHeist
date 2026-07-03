import Testing

#if canImport(UIKit)
@testable import TheInsideJob
#endif

#if canImport(UIKit)
@Suite struct InsideJobStartupErrorTests {

    @Test func `token requirement diagnostics render closed runtime phases`() {
        #expect(
            InsideJobStartupError
                .tokenRequired(phase: .startup)
                .errorDescription?
                .contains("during startup;") == true
        )
        #expect(
            InsideJobStartupError
                .tokenRequired(phase: .resume)
                .errorDescription?
                .contains("during resume;") == true
        )
    }
}
#endif
