#if canImport(UIKit)
#if DEBUG
import UIKit

extension TheTripwire {
    /// Snapshot of all monitored UI signals at a single tick.
    struct PulseReading {
        let tick: UInt64
        let timestamp: CFAbsoluteTime

        let layoutPending: Bool
        let fingerprint: PresentationFingerprint
        let hasRelevantAnimations: Bool
        let topmostVC: ObjectIdentifier?
        let tripwireSignal: TripwireSignal
        let windowCount: Int

        // Derived settle state
        let quietFrames: Int

        /// The UI is settled when no layout is pending and the presentation
        /// geometry fingerprint has been stable for 2+ frames. Animation keys
        /// remain diagnostic; layer churn that does not move or resize frames
        /// must not block settle.
        var isSettled: Bool {
            !layoutPending && quietFrames >= 2
        }
    }

    /// Fingerprint of all presentation layer frames in the window hierarchy.
    /// Summing geometry is cheap and catches movement or resizing while
    /// ignoring layer-only noise such as opacity animations.
    struct PresentationFingerprint {
        let frameMinXSum: CGFloat
        let frameMinYSum: CGFloat
        let frameWidthSum: CGFloat
        let frameHeightSum: CGFloat
        let layerCount: Int

        private static let frameTolerance: CGFloat = 0.5

        func matches(_ other: PresentationFingerprint) -> Bool {
            layerCount == other.layerCount
                && abs(frameMinXSum - other.frameMinXSum) < Self.frameTolerance
                && abs(frameMinYSum - other.frameMinYSum) < Self.frameTolerance
                && abs(frameWidthSum - other.frameWidthSum) < Self.frameTolerance
                && abs(frameHeightSum - other.frameHeightSum) < Self.frameTolerance
        }
    }

    /// Result of a single layer-tree walk that collects fingerprint,
    /// animation, and layout data in one pass.
    struct LayerScan {
        var frameMinXSum: CGFloat = 0
        var frameMinYSum: CGFloat = 0
        var frameWidthSum: CGFloat = 0
        var frameHeightSum: CGFloat = 0
        var layerCount: Int = 0
        var hasRelevantAnimations = false
        var hasPendingLayout = false
        var windowCount: Int = 0

        var fingerprint: PresentationFingerprint {
            PresentationFingerprint(
                frameMinXSum: frameMinXSum,
                frameMinYSum: frameMinYSum,
                frameWidthSum: frameWidthSum,
                frameHeightSum: frameHeightSum,
                layerCount: layerCount
            )
        }
    }

    /// Walk every layer once, collecting fingerprint + animations + layout.
    func scanLayers() -> LayerScan {
        var scan = LayerScan()
        let windows = getTraversableWindows()
        scan.windowCount = windows.count
        for entry in windows {
            let window = entry.window
            var stack: [CALayer] = [window.layer]
            while let layer = stack.popLast() {
                let presentationLayer = layer.presentation() ?? layer
                let frame = presentationLayer.frame
                scan.frameMinXSum += frame.minX
                scan.frameMinYSum += frame.minY
                scan.frameWidthSum += frame.width
                scan.frameHeightSum += frame.height
                scan.layerCount += 1

                if layer.needsLayout() {
                    scan.hasPendingLayout = true
                }

                if !scan.hasRelevantAnimations, let keys = layer.animationKeys() {
                    scan.hasRelevantAnimations = keys.contains { key in
                        !Self.ignoredAnimationKeyPrefixes.contains { key.hasPrefix($0) }
                    }
                }

                if let sublayers = layer.sublayers {
                    stack.append(contentsOf: sublayers)
                }
            }
        }
        return scan
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
