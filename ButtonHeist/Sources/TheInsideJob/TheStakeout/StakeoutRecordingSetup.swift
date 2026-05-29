#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

extension TheStakeout {
    struct RecordingSetup {
        let caps: [RecordedInputCap]
        let fps: Int
        let maxDuration: TimeInterval
        let inactivityTimeout: TimeInterval?
        let effectiveScale: CGFloat
        let screenBounds: CGRect
        let evenWidth: Int
        let evenHeight: Int
    }

    static func makeRecordingSetup(config: RecordingConfig, screen: ScreenInfo) -> RecordingSetup {
        var caps: [RecordedInputCap] = []

        let fps = cappedInt(
            name: "fps",
            requested: config.fps,
            defaultValue: 8,
            range: 1...15,
            reason: "recording fps is capped to the encoder-supported range",
            caps: &caps
        )
        let timing = resolvedStakeoutTiming(for: config)
        let inactivityTimeout = timing.inactivityTimeout
        let maxDuration = timing.maxDuration
        if let requested = config.inactivityTimeout,
           let applied = inactivityTimeout,
           requested != applied {
            caps.append(RecordedInputCap(
                name: "inactivityTimeout",
                requested: .double(requested),
                applied: .double(applied),
                minimum: .double(1.0),
                reason: "recording inactivity timeout must be at least 1 second"
            ))
        }
        if let requested = config.maxDuration, requested != maxDuration {
            caps.append(RecordedInputCap(
                name: "maxDuration",
                requested: .double(requested),
                applied: .double(maxDuration),
                minimum: .double(1.0),
                reason: "recording max duration must be at least 1 second"
            ))
        }

        let nativeWidth = screen.bounds.width * screen.scale
        let nativeHeight = screen.bounds.height * screen.scale
        let effectiveScale = CGFloat(cappedScale(config.scale, screenScale: screen.scale, caps: &caps))
        let width = Int(nativeWidth * effectiveScale)
        let height = Int(nativeHeight * effectiveScale)
        let evenWidth = width.isMultiple(of: 2) ? width : width + 1
        let evenHeight = height.isMultiple(of: 2) ? height : height + 1
        appendEvenDimensionCap(name: "width", requested: width, applied: evenWidth, caps: &caps)
        appendEvenDimensionCap(name: "height", requested: height, applied: evenHeight, caps: &caps)

        return RecordingSetup(
            caps: caps,
            fps: fps,
            maxDuration: maxDuration,
            inactivityTimeout: inactivityTimeout,
            effectiveScale: effectiveScale,
            screenBounds: CGRect(x: 0, y: 0, width: evenWidth, height: evenHeight),
            evenWidth: evenWidth,
            evenHeight: evenHeight
        )
    }

    private static func cappedScale(
        _ requested: Double?,
        screenScale: CGFloat,
        caps: inout [RecordedInputCap]
    ) -> Double {
        guard let requested else { return Double(1.0 / screenScale) }
        return cappedDouble(
            name: "scale",
            requested: requested,
            minimum: 0.25,
            maximum: 1.0,
            reason: "recording scale is capped to the supported output range",
            caps: &caps
        )
    }

    private static func cappedInt(
        name: String,
        requested: Int?,
        defaultValue: Int,
        range: ClosedRange<Int>,
        reason: String,
        caps: inout [RecordedInputCap]
    ) -> Int {
        let value = requested ?? defaultValue
        let applied = min(max(value, range.lowerBound), range.upperBound)
        if let requested, requested != applied {
            caps.append(RecordedInputCap(
                name: name,
                requested: .int(requested),
                applied: .int(applied),
                minimum: .int(range.lowerBound),
                maximum: .int(range.upperBound),
                reason: reason
            ))
        }
        return applied
    }

    private static func cappedDouble(
        name: String,
        requested: Double,
        minimum: Double,
        maximum: Double?,
        reason: String,
        caps: inout [RecordedInputCap]
    ) -> Double {
        var applied = max(requested, minimum)
        if let maximum {
            applied = min(applied, maximum)
        }
        if requested != applied {
            caps.append(RecordedInputCap(
                name: name,
                requested: .double(requested),
                applied: .double(applied),
                minimum: .double(minimum),
                maximum: maximum.map { .double($0) },
                reason: reason
            ))
        }
        return applied
    }

    private static func appendEvenDimensionCap(
        name: String,
        requested: Int,
        applied: Int,
        caps: inout [RecordedInputCap]
    ) {
        guard requested != applied else { return }
        caps.append(RecordedInputCap(
            name: name,
            requested: .int(requested),
            applied: .int(applied),
            reason: "H.264 output dimensions must be even"
        ))
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
