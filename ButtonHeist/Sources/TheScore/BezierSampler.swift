import Foundation
import CoreGraphics

/// Converts cubic bezier curves into evenly-spaced polyline samples.
public enum BezierSampler {

    /// Sample a cubic bezier curve into a polyline.
    /// - Parameters:
    ///   - p0: Start point
    ///   - p1: First control point
    ///   - p2: Second control point
    ///   - p3: End point
    ///   - sampleCount: Number of points to generate (minimum 2)
    /// - Returns: Array of PathPoint samples along the curve
    static func sampleCubicBezier(
        p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint,
        sampleCount: Int = 20
    ) -> [PathPoint] {
        let count = max(sampleCount, 2)
        return (0..<count).map { i in
            let t = CGFloat(i) / CGFloat(count - 1)
            let point = cubicBezierPoint(t: t, p0: p0, p1: p1, p2: p2, p3: p3)
            return PathPoint(x: point.x, y: point.y)
        }
    }

    /// Sample a sequence of cubic bezier segments into a single polyline.
    /// Uses `BezierSegment` from the wire protocol directly.
    /// - Parameters:
    ///   - startPoint: Starting point of the path
    ///   - segments: Array of BezierSegment (from wire protocol)
    ///   - samplesPerSegment: Samples per bezier segment (default 20)
    /// - Returns: Combined polyline as PathPoint array
    public static func sampleBezierPath(
        startPoint: CGPoint,
        segments: [BezierSegment],
        samplesPerSegment: Int = 20
    ) -> [PathPoint] {
        guard !segments.isEmpty else {
            return [PathPoint(x: startPoint.x, y: startPoint.y)]
        }

        var result: [PathPoint] = []
        var current = startPoint

        for (i, seg) in segments.enumerated() {
            let samples = sampleCubicBezier(
                p0: current, p1: seg.cp1, p2: seg.cp2, p3: seg.end,
                sampleCount: samplesPerSegment
            )
            // Skip first point of subsequent segments to avoid duplicates
            result.append(contentsOf: i == 0 ? samples : Array(samples.dropFirst()))
            current = seg.end
        }

        return result
    }

    // MARK: - Private

    private static func cubicBezierPoint(
        t: CGFloat, p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint
    ) -> CGPoint {
        let mt = 1 - t
        let mt2 = mt * mt
        let t2 = t * t
        return CGPoint(
            x: mt2 * mt * p0.x + 3 * mt2 * t * p1.x + 3 * mt * t2 * p2.x + t2 * t * p3.x,
            y: mt2 * mt * p0.y + 3 * mt2 * t * p1.y + 3 * mt * t2 * p2.y + t2 * t * p3.y
        )
    }
}
