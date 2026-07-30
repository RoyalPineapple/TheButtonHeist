#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

extension InterfaceTreeTests {
    func testCapturePlanUsesLandscapeFrameForRotatedWindow() throws {
        let window = TheVault.ScreenCaptureWindowGeometry(
            frame: CGRect(x: 0, y: 0, width: 200, height: 100),
            bounds: CGRect(x: 0, y: 0, width: 100, height: 200),
            center: CGPoint(x: 100, y: 50),
            transform: CGAffineTransform(rotationAngle: .pi / 2)
        )

        let captureBounds = try XCTUnwrap(TheVault.screenCaptureBounds(for: [window]))
        let transform = TheVault.screenCaptureTransform(for: window, relativeTo: captureBounds)
        let transformedBounds = window.bounds.applyingToCorners(transform)

        assertRect(
            CGRect(origin: .zero, size: captureBounds.size),
            equals: CGRect(x: 0, y: 0, width: 200, height: 100)
        )
        assertRect(
            transformedBounds,
            equals: CGRect(x: 0, y: 0, width: 200, height: 100)
        )
    }

    func testCapturePlanNormalizesNonZeroWindowOrigin() throws {
        let window = TheVault.ScreenCaptureWindowGeometry(
            frame: CGRect(x: 20, y: 30, width: 100, height: 200),
            bounds: CGRect(x: 0, y: 0, width: 100, height: 200),
            center: CGPoint(x: 70, y: 130),
            transform: .identity
        )

        let captureBounds = try XCTUnwrap(TheVault.screenCaptureBounds(for: [window]))
        let transform = TheVault.screenCaptureTransform(for: window, relativeTo: captureBounds)
        let transformedBounds = window.bounds.applyingToCorners(transform)

        assertRect(
            CGRect(origin: .zero, size: captureBounds.size),
            equals: CGRect(x: 0, y: 0, width: 100, height: 200)
        )
        assertRect(
            transformedBounds,
            equals: CGRect(x: 0, y: 0, width: 100, height: 200)
        )
    }

    private func assertRect(
        _ actual: CGRect,
        equals expected: CGRect,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.origin.x, expected.origin.x, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.origin.y, expected.origin.y, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.001, file: file, line: line)
    }
}

private extension CGRect {
    func applyingToCorners(_ transform: CGAffineTransform) -> CGRect {
        let transformedPoints = [
            CGPoint(x: minX, y: minY),
            CGPoint(x: maxX, y: minY),
            CGPoint(x: minX, y: maxY),
            CGPoint(x: maxX, y: maxY),
        ]
        .map { $0.applying(transform) }

        let xs = transformedPoints.map(\.x)
        let ys = transformedPoints.map(\.y)
        guard let minX = xs.min(),
              let maxX = xs.max(),
              let minY = ys.min(),
              let maxY = ys.max() else {
            return .null
        }

        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }
}

#endif // canImport(UIKit)
