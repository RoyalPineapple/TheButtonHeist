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
        /// fingerprint has been stable for 2+ frames. Animation keys remain
        /// diagnostic; platform-owned stable animations must not block settle.
        var isSettled: Bool {
            !layoutPending && quietFrames >= 2
        }
    }

    /// Fingerprint of all presentation layer positions in the window hierarchy.
    /// Summing positions is cheap and catches any layer movement — if anything
    /// shifts, the sum shifts.
    struct PresentationFingerprint {
        let positionXSum: CGFloat
        let positionYSum: CGFloat
        let opacitySum: CGFloat
        let layerCount: Int

        private static let posTolerance: CGFloat = 0.5
        private static let opacityTolerance: CGFloat = 0.05

        func matches(_ other: PresentationFingerprint) -> Bool {
            layerCount == other.layerCount
                && abs(positionXSum - other.positionXSum) < Self.posTolerance
                && abs(positionYSum - other.positionYSum) < Self.posTolerance
                && abs(opacitySum - other.opacitySum) < Self.opacityTolerance
        }
    }

    /// Result of a single layer-tree walk that collects fingerprint,
    /// animation, and layout data in one pass.
    struct LayerScan {
        var positionXSum: CGFloat = 0
        var positionYSum: CGFloat = 0
        var opacitySum: CGFloat = 0
        var layerCount: Int = 0
        var hasRelevantAnimations = false
        var hasPendingLayout = false
        var windowCount: Int = 0

        var fingerprint: PresentationFingerprint {
            PresentationFingerprint(
                positionXSum: positionXSum,
                positionYSum: positionYSum,
                opacitySum: opacitySum,
                layerCount: layerCount
            )
        }
    }

    /// Walk every layer once, collecting fingerprint + animations + layout.
    func scanLayers() -> LayerScan {
        var scan = LayerScan()
        let windows = getTraversableWindows()
        scan.windowCount = windows.count
        for (window, _) in windows {
            var stack: [CALayer] = [window.layer]
            while let layer = stack.popLast() {
                let presentationLayer = layer.presentation() ?? layer
                scan.positionXSum += presentationLayer.position.x
                scan.positionYSum += presentationLayer.position.y
                scan.opacitySum += CGFloat(presentationLayer.opacity)
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
