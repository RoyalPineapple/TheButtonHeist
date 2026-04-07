#if canImport(UIKit)
import XCTest
import CoreGraphics
import TheScore
@testable import TheInsideJob

final class BezierSamplerTests: XCTestCase {

    func testSampleCountMatchesRequested() {
        let samples = TheSafecracker.BezierSampler.sampleCubicBezier(
            p0: .zero, p1: CGPoint(x: 0, y: 100),
            p2: CGPoint(x: 100, y: 100), p3: CGPoint(x: 100, y: 0),
            sampleCount: 10
        )
        XCTAssertEqual(samples.count, 10)
    }

    func testFirstAndLastPointMatchEndpoints() {
        let p0 = CGPoint(x: 10, y: 20)
        let p3 = CGPoint(x: 300, y: 400)
        let samples = TheSafecracker.BezierSampler.sampleCubicBezier(
            p0: p0, p1: CGPoint(x: 50, y: 100),
            p2: CGPoint(x: 200, y: 300), p3: p3,
            sampleCount: 50
        )
        guard let first = samples.first, let last = samples.last else {
            return XCTFail("Expected non-empty samples")
        }
        XCTAssertEqual(first.x, p0.x, accuracy: 0.001)
        XCTAssertEqual(first.y, p0.y, accuracy: 0.001)
        XCTAssertEqual(last.x, p3.x, accuracy: 0.001)
        XCTAssertEqual(last.y, p3.y, accuracy: 0.001)
    }

    func testMinimumSampleCount() {
        let samples = TheSafecracker.BezierSampler.sampleCubicBezier(
            p0: .zero, p1: .zero, p2: CGPoint(x: 100, y: 100), p3: CGPoint(x: 100, y: 100),
            sampleCount: 1
        )
        XCTAssertEqual(samples.count, 2) // Clamped to minimum of 2
    }

    func testStraightLineBezier() {
        let samples = TheSafecracker.BezierSampler.sampleCubicBezier(
            p0: CGPoint(x: 0, y: 0),
            p1: CGPoint(x: 33, y: 0),
            p2: CGPoint(x: 66, y: 0),
            p3: CGPoint(x: 100, y: 0),
            sampleCount: 5
        )
        // All Y values should be ~0 for a horizontal line
        for sample in samples {
            XCTAssertEqual(sample.y, 0, accuracy: 0.001)
        }
        // X should be monotonically increasing
        for i in 1..<samples.count {
            XCTAssertGreaterThan(samples[i].x, samples[i-1].x)
        }
    }

    func testMultiSegmentPath() {
        let samples = TheSafecracker.BezierSampler.sampleBezierPath(
            startPoint: CGPoint(x: 0, y: 0),
            segments: [
                BezierSegment(cp1X: 33, cp1Y: 0, cp2X: 66, cp2Y: 0, endX: 100, endY: 0),
                BezierSegment(cp1X: 100, cp1Y: 33, cp2X: 100, cp2Y: 66, endX: 100, endY: 100),
            ],
            samplesPerSegment: 10
        )
        // First segment: 10 points. Second segment: 9 points (first dropped to avoid duplicate).
        XCTAssertEqual(samples.count, 19)
        guard let first = samples.first, let last = samples.last else {
            return XCTFail("Expected non-empty samples")
        }
        // First point is start
        XCTAssertEqual(first.x, 0, accuracy: 0.001)
        XCTAssertEqual(first.y, 0, accuracy: 0.001)
        // Last point is end
        XCTAssertEqual(last.x, 100, accuracy: 0.001)
        XCTAssertEqual(last.y, 100, accuracy: 0.001)
    }

    func testEmptySegments() {
        let samples = TheSafecracker.BezierSampler.sampleBezierPath(
            startPoint: CGPoint(x: 50, y: 50),
            segments: []
        )
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples[0].x, 50)
        XCTAssertEqual(samples[0].y, 50)
    }
}
#endif // canImport(UIKit)
