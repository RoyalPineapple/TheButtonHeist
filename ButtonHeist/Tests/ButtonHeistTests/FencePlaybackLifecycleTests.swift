import XCTest

@testable import ButtonHeist
import TheScore

final class FencePlaybackLifecycleTests: XCTestCase {
    @ButtonHeistActor
    func testBeginsAndEndsPlayback() async throws {
        let lifecycle = FencePlaybackLifecycle()
        XCTAssertEqual(lifecycle.snapshot, .init(isPlaying: false, startedAt: nil))
        XCTAssertTrue(lifecycle.isIdle)

        let startedAt = Date(timeIntervalSince1970: 42)
        try lifecycle.begin(startedAt: startedAt)

        XCTAssertEqual(lifecycle.snapshot, .init(isPlaying: true, startedAt: startedAt))
        XCTAssertFalse(lifecycle.isIdle)

        lifecycle.end()

        XCTAssertEqual(lifecycle.snapshot, .init(isPlaying: false, startedAt: nil))
        XCTAssertTrue(lifecycle.isIdle)
    }

    @ButtonHeistActor
    func testRejectsReentrantPlayback() async throws {
        let lifecycle = FencePlaybackLifecycle()
        try lifecycle.begin(startedAt: Date(timeIntervalSince1970: 42))

        XCTAssertThrowsError(try lifecycle.begin()) { error in
            guard case FenceError.invalidRequest(let message) = error else {
                return XCTFail("Expected invalidRequest, got \(error)")
            }
            XCTAssertEqual(message, "Cannot nest play_heist inside an active playback")
        }
    }

}
