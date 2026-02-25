# Stakeout Screen Recording Implementation Plan

## Overview

Add screen recording capability to InsideMan via a new `Stakeout` class that captures frames using the existing `captureScreen()` compositing approach and encodes them into H.264/MP4 on-device using `AVAssetWriter`. The recording is start/stop controlled with an inactivity auto-stop: if no screen changes and no client commands arrive for a configurable timeout, the recording stops automatically. The compressed video is base64-encoded and sent as a single wire protocol message, following the same pattern as screenshots.

## Current State Analysis

**Screenshot flow today:**
1. `InsideMan.captureScreen()` (`InsideMan.swift:494`) composites all visible `UIWindow` layers via `UIGraphicsImageRenderer` + `drawHierarchy`
2. The `UIImage` is PNG-encoded, base64'd into a `ScreenPayload` (`Messages.swift:543`)
3. Sent as `ServerMessage.screen(ScreenPayload)` — a single newline-delimited JSON line over TCP

**Wire protocol constraints:**
- 10MB receive buffer ceiling (`SimpleSocketServer.swift:9`) — a single message exceeding this disconnects the client
- Base64 inflates binary by ~33%, so effective raw data cap is ~7.5MB per message
- No chunking mechanism — every message must be one complete JSON line
- 30 messages/second rate limit (`SimpleSocketServer.swift:11`)

**No recording exists today.** No ReplayKit, AVFoundation capture, or video encoding anywhere in the codebase.

### Key Discoveries:
- `captureScreen()` at `InsideMan.swift:494-507` already handles window filtering (excludes `TapOverlayWindow`) and compositing — we reuse this directly
- `checkForChanges()` at `InsideMan.swift:467-491` already computes a hierarchy hash to detect screen changes — we can piggyback on this for inactivity detection
- The existing polling loop (`InsideMan.swift:455-465`) runs at a configurable interval and drives change detection
- `handleClientMessage` at `InsideMan.swift:262-327` is the dispatch point for all client commands — we can track "last command received" here for inactivity timeout

## Desired End State

A client can send `startRecording` to begin capturing frames and `stopRecording` (or let the inactivity timeout trigger) to finalize. The server responds with a `recording(RecordingPayload)` message containing the H.264/MP4 video as base64-encoded data, along with metadata (duration, frame count, dimensions).

**Verification:**
1. All existing targets build: `ButtonHeist`, `Wheelman`, `TheGoods`, `InsideMan`, `ButtonHeistCLI`, `ButtonHeistMCP`
2. All existing tests pass: `TheGoodsTests`, `WheelmanTests`, `ButtonHeistTests`
3. CLI command works: `buttonheist record --output test.mp4` produces a playable MP4
4. Session command works: `{"command":"start_recording"}` followed by interactions, then `{"command":"stop_recording"}` returns video data
5. MCP tool works: `record_screen` returns video as base64 content

## What We're NOT Doing

- **ReplayKit integration** — requires user permission dialogs, shows recording indicator, can't filter overlay windows
- **Audio capture** — screen-only; audio adds complexity and file size with no debugging value
- **Streaming/chunked transfer** — the wire protocol stays unchanged; videos must fit in a single message
- **Protocol version bump** — new message types are additive; old clients simply won't send them, old servers will fail to decode (acceptable)
- **Real-time video streaming** — this is record-then-deliver, not live preview

## Implementation Approach

Capture frames at a configurable FPS (default 8) and feed them into an `AVAssetWriter` configured for H.264 in an MP4 container.

**Frame capture**: Uses InsideMan's window compositing approach (`UIGraphicsImageRenderer` + `drawHierarchy`) but with two key differences from screenshots:
1. **Includes the `TapOverlayWindow`** — recordings show where taps land (the white circle indicators). Screenshots exclude this overlay, but recordings need it to show interactions.
2. **Action-triggered frames** — in addition to the regular FPS timer, an extra frame is captured immediately after any action completes (tap, swipe, type, etc.). This guarantees every interaction is visible in the video regardless of timer alignment. These bonus frames don't reset the timer — the next timer-driven frame still fires on schedule.

To support this, we add a `captureScreenForRecording()` method to InsideMan that includes all windows (no `TapOverlayWindow` filter), and the Stakeout class exposes a `captureActionFrame()` method called from action handlers.

**Resolution strategy**: By default, recording resolution equals the screen's 1x point size — i.e., native pixel dimensions divided by `UIScreen.main.scale`. On a 3x iPhone (1179×2556 native), this produces 393×852 video. On a 2x iPad it halves the native resolution. This naturally normalizes file size across devices while remaining perfectly readable for debugging. The caller can override with a `scale` parameter (0.25–1.0 of native), where `scale: 1.0` means full native resolution (no reduction).

An inactivity timer auto-stops the recording when no screen changes and no client commands arrive for N seconds (default 5). A file size guard stops recording early if the output approaches the 7MB raw limit (leaving headroom for base64 + JSON wrapper under the 10MB buffer ceiling). On stop, the MP4 is read from the temp file, base64-encoded, and sent as a `recording` message.

---

## Phase 1: Protocol Types (TheGoods)

### Overview
Add the new message types and payload structs to the shared protocol layer.

### Changes Required:

#### 1. New Client Message Cases
**File**: `ButtonHeist/Sources/TheGoods/Messages.swift`
**Changes**: Add `startRecording` and `stopRecording` cases to `ClientMessage` enum

```swift
// Add after case requestScreen (line 84):

/// Start recording the screen
case startRecording(RecordingConfig)

/// Stop an in-progress recording
case stopRecording
```

#### 2. New Recording Config Payload
**File**: `ButtonHeist/Sources/TheGoods/Messages.swift`
**Changes**: Add `RecordingConfig` struct

```swift
/// Configuration for screen recording
public struct RecordingConfig: Codable, Sendable {
    /// Frames per second (default: 8, range: 1-15)
    public let fps: Int?
    /// Resolution scale relative to native pixels (0.25-1.0).
    /// Default: nil — uses 1x point resolution (native pixels / screen scale).
    /// 1.0 = full native resolution (no reduction).
    public let scale: Double?
    /// Inactivity timeout in seconds — auto-stop when no screen changes
    /// and no commands received for this duration (default: 5.0)
    public let inactivityTimeout: Double?
    /// Maximum recording duration in seconds as a hard safety cap (default: 60.0)
    public let maxDuration: Double?

    public init(
        fps: Int? = nil,
        scale: Double? = nil,
        inactivityTimeout: Double? = nil,
        maxDuration: Double? = nil
    ) {
        self.fps = fps
        self.scale = scale
        self.inactivityTimeout = inactivityTimeout
        self.maxDuration = maxDuration
    }
}
```

#### 3. New Server Message Cases
**File**: `ButtonHeist/Sources/TheGoods/Messages.swift`
**Changes**: Add recording-related cases to `ServerMessage` enum

```swift
// Add after case screen(ScreenPayload) (line 447):

/// Recording has started
case recordingStarted

/// Recording complete with video data
case recording(RecordingPayload)

/// Recording failed or was not active
case recordingError(String)
```

#### 4. New Recording Payload
**File**: `ButtonHeist/Sources/TheGoods/Messages.swift`
**Changes**: Add `RecordingPayload` struct

```swift
/// Payload containing screen recording video data
public struct RecordingPayload: Codable, Sendable {
    /// Base64-encoded MP4 video data (H.264)
    public let videoData: String
    /// Video width in pixels
    public let width: Int
    /// Video height in pixels
    public let height: Int
    /// Recording duration in seconds
    public let duration: Double
    /// Number of frames captured
    public let frameCount: Int
    /// Frames per second used during recording
    public let fps: Int
    /// Timestamp when recording started
    public let startTime: Date
    /// Timestamp when recording ended
    public let endTime: Date
    /// Reason recording stopped
    public let stopReason: StopReason

    public enum StopReason: String, Codable, Sendable {
        case manual          // Client sent stopRecording
        case inactivity      // No changes + no commands for timeout duration
        case maxDuration     // Hit the hard duration cap
        case fileSizeLimit   // Approaching wire protocol size limit
    }

    public init(
        videoData: String,
        width: Int,
        height: Int,
        duration: Double,
        frameCount: Int,
        fps: Int,
        startTime: Date,
        endTime: Date,
        stopReason: StopReason
    ) {
        self.videoData = videoData
        self.width = width
        self.height = height
        self.duration = duration
        self.frameCount = frameCount
        self.fps = fps
        self.startTime = startTime
        self.endTime = endTime
        self.stopReason = stopReason
    }
}
```

### Success Criteria:

#### Automated Verification:
- [x] TheGoods builds: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme TheGoods build`
- [x] Existing TheGoodsTests pass: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme TheGoodsTests test`

---

## Phase 2: Stakeout Recording Engine (InsideMan)

### Overview
Create the `Stakeout` class — the on-device recording engine that captures frames, encodes H.264 video, and manages the recording lifecycle including inactivity detection.

### Changes Required:

#### 1. New Stakeout Class
**File**: `ButtonHeist/Sources/InsideMan/Stakeout.swift` (new file)
**Changes**: Full recording engine implementation

```swift
#if canImport(UIKit)
#if DEBUG
import UIKit
import AVFoundation
import TheGoods

private func stakeoutLog(_ message: String) {
    NSLog("[Stakeout] %@", message)
}

/// Screen recording engine. Captures frames using InsideMan's window compositing
/// and encodes them as H.264/MP4 using AVAssetWriter.
@MainActor
final class Stakeout {

    enum State {
        case idle
        case recording
        case finalizing
    }

    private(set) var state: State = .idle

    // Configuration (with clamped defaults)
    private var fps: Int = 8
    private var inactivityTimeout: TimeInterval = 5.0
    private var maxDuration: TimeInterval = 60.0

    // AVAssetWriter pipeline
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var outputURL: URL?

    // Frame capture
    private var captureTimer: Task<Void, Never>?
    private var frameCount: Int = 0
    private var startTime: Date?
    private var lastFrameTime: CMTime = .zero
    private var screenBounds: CGRect = .zero

    // Inactivity tracking
    private var lastActivityTime: Date = Date()
    private var inactivityCheckTask: Task<Void, Never>?

    // Frame provider closure — set by InsideMan to provide captureScreen()
    var captureFrame: (() -> UIImage?)?

    // Completion handler — called when recording finishes for any reason
    var onRecordingComplete: ((Result<RecordingPayload, Error>) -> Void)?

    // MARK: - Public API

    func startRecording(config: RecordingConfig) throws {
        guard state == .idle else {
            throw StakeoutError.alreadyRecording
        }

        // Apply config with clamping
        fps = max(1, min(15, config.fps ?? 8))
        inactivityTimeout = max(1.0, config.inactivityTimeout ?? 5.0)
        maxDuration = max(1.0, config.maxDuration ?? 60.0)

        // Determine output dimensions from screen.
        // Default: 1x point resolution (native pixels / screen scale).
        // If caller provides scale, use that fraction of native resolution.
        let screen = UIScreen.main
        let nativeWidth = screen.bounds.width * screen.scale
        let nativeHeight = screen.bounds.height * screen.scale
        let effectiveScale: CGFloat
        if let requestedScale = config.scale {
            effectiveScale = max(0.25, min(1.0, CGFloat(requestedScale)))
        } else {
            // Default: 1x point size = native / screen.scale
            effectiveScale = 1.0 / screen.scale
        }
        let width = Int(nativeWidth * effectiveScale)
        let height = Int(nativeHeight * effectiveScale)
        // AVAssetWriter requires even dimensions
        let evenWidth = width % 2 == 0 ? width : width + 1
        let evenHeight = height % 2 == 0 ? height : height + 1
        screenBounds = CGRect(x: 0, y: 0, width: evenWidth, height: evenHeight)

        // Set up temp file
        let tempDir = NSTemporaryDirectory()
        let fileName = "stakeout-\(UUID().uuidString).mp4"
        let url = URL(fileURLWithPath: tempDir).appendingPathComponent(fileName)
        outputURL = url

        // Configure AVAssetWriter
        let writer = try AVAssetWriter(url: url, fileType: .mp4)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: evenWidth,
            AVVideoHeightKey: evenHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: evenWidth * evenHeight * 2, // ~2 bits/pixel
                AVVideoMaxKeyFrameIntervalKey: fps * 2, // Keyframe every 2 seconds
                AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel,
            ]
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true

        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: evenWidth,
            kCVPixelBufferHeightKey as String: evenHeight,
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: sourcePixelBufferAttributes
        )

        writer.add(input)
        guard writer.startWriting() else {
            throw StakeoutError.writerSetupFailed(writer.error?.localizedDescription ?? "Unknown error")
        }
        writer.startSession(atSourceTime: .zero)

        assetWriter = writer
        videoInput = input
        pixelBufferAdaptor = adaptor
        frameCount = 0
        startTime = Date()
        lastFrameTime = .zero
        lastActivityTime = Date()
        state = .recording

        stakeoutLog("Recording started: \(evenWidth)x\(evenHeight) @ \(fps)fps, scale=\(scale)")

        // Start frame capture timer
        startCaptureTimer()

        // Start inactivity monitor
        startInactivityMonitor()
    }

    func stopRecording(reason: RecordingPayload.StopReason = .manual) {
        guard state == .recording else { return }
        state = .finalizing

        stakeoutLog("Stopping recording: reason=\(reason.rawValue), frames=\(frameCount)")

        captureTimer?.cancel()
        captureTimer = nil
        inactivityCheckTask?.cancel()
        inactivityCheckTask = nil

        finalizeRecording(reason: reason)
    }

    /// Call this whenever client activity occurs (commands received, etc.)
    func noteActivity() {
        lastActivityTime = Date()
    }

    /// Call this whenever a screen change is detected (hierarchy hash change)
    func noteScreenChange() {
        lastActivityTime = Date()
    }

    // MARK: - Frame Capture

    private func startCaptureTimer() {
        let interval = UInt64(1_000_000_000 / UInt64(fps))
        captureTimer = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.captureAndAppendFrame()
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }

    private func captureAndAppendFrame() {
        guard state == .recording,
              let input = videoInput, input.isReadyForMoreMediaData,
              let adaptor = pixelBufferAdaptor,
              let image = captureFrame?() else {
            return
        }

        // Check file size guard (7MB raw = ~9.3MB base64, under 10MB buffer limit)
        if let url = outputURL,
           let fileSize = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int,
           fileSize > 7_000_000 {
            stakeoutLog("File size limit reached: \(fileSize) bytes")
            stopRecording(reason: .fileSizeLimit)
            return
        }

        // Check max duration
        if let start = startTime, Date().timeIntervalSince(start) >= maxDuration {
            stakeoutLog("Max duration reached")
            stopRecording(reason: .maxDuration)
            return
        }

        // Create pixel buffer from UIImage
        guard let pixelBuffer = createPixelBuffer(from: image) else { return }

        let frameTime = CMTime(value: Int64(frameCount), timescale: Int32(fps))
        if adaptor.append(pixelBuffer, withPresentationTime: frameTime) {
            frameCount += 1
            lastFrameTime = frameTime
        }
    }

    private func createPixelBuffer(from image: UIImage) -> CVPixelBuffer? {
        guard let pool = pixelBufferAdaptor?.pixelBufferPool else { return nil }

        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        guard let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(screenBounds.width),
            height: Int(screenBounds.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        guard let cgImage = image.cgImage else { return nil }

        // Draw the image scaled into the pixel buffer
        context.draw(cgImage, in: screenBounds)

        return buffer
    }

    // MARK: - Inactivity Detection

    private func startInactivityMonitor() {
        inactivityCheckTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // Check every second
                guard let self, self.state == .recording else { continue }

                let elapsed = Date().timeIntervalSince(self.lastActivityTime)
                if elapsed >= self.inactivityTimeout {
                    stakeoutLog("Inactivity timeout: \(elapsed)s since last activity")
                    self.stopRecording(reason: .inactivity)
                    return
                }
            }
        }
    }

    // MARK: - Finalization

    private func finalizeRecording(reason: RecordingPayload.StopReason) {
        guard let writer = assetWriter, let input = videoInput else {
            deliverError(.finalizationFailed("No active writer"))
            return
        }

        input.markAsFinished()

        let endTime = Date()
        let startTime = self.startTime ?? endTime
        let frameCount = self.frameCount
        let fps = self.fps
        let width = Int(screenBounds.width)
        let height = Int(screenBounds.height)
        let url = outputURL

        writer.finishWriting { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                defer { self.cleanup() }

                if writer.status == .failed {
                    self.deliverError(.finalizationFailed(writer.error?.localizedDescription ?? "Unknown"))
                    return
                }

                guard let url,
                      let videoData = try? Data(contentsOf: url) else {
                    self.deliverError(.finalizationFailed("Could not read output file"))
                    return
                }

                let duration = endTime.timeIntervalSince(startTime)

                let payload = RecordingPayload(
                    videoData: videoData.base64EncodedString(),
                    width: width,
                    height: height,
                    duration: duration,
                    frameCount: frameCount,
                    fps: fps,
                    startTime: startTime,
                    endTime: endTime,
                    stopReason: reason
                )

                stakeoutLog("Recording complete: \(frameCount) frames, \(String(format: "%.1f", duration))s, \(videoData.count) bytes")
                self.onRecordingComplete?(.success(payload))
            }
        }
    }

    private func deliverError(_ error: StakeoutError) {
        stakeoutLog("Recording error: \(error)")
        onRecordingComplete?(.failure(error))
        cleanup()
    }

    private func cleanup() {
        state = .idle
        captureTimer?.cancel()
        captureTimer = nil
        inactivityCheckTask?.cancel()
        inactivityCheckTask = nil
        assetWriter = nil
        videoInput = nil
        pixelBufferAdaptor = nil

        // Clean up temp file
        if let url = outputURL {
            try? FileManager.default.removeItem(at: url)
        }
        outputURL = nil
    }

    enum StakeoutError: Error, LocalizedError {
        case alreadyRecording
        case writerSetupFailed(String)
        case finalizationFailed(String)

        var errorDescription: String? {
            switch self {
            case .alreadyRecording: return "Recording is already in progress"
            case .writerSetupFailed(let msg): return "Failed to set up video writer: \(msg)"
            case .finalizationFailed(let msg): return "Failed to finalize recording: \(msg)"
            }
        }
    }
}

#endif
#endif
```

**Key design decisions:**
- **FPS default 8, clamped 1-15**: Higher than needed wastes file size; 8 is smooth enough for UI debugging
- **Resolution default = 1x point size**: Native pixels divided by screen scale (e.g., 393×852 on a 3x iPhone). Normalizes file size across devices. Caller can override up to `scale: 1.0` for full native resolution.
- **Bitrate = width × height × 2**: ~2 bits/pixel is conservative for screen content (lots of flat color)
- **File size guard at 7MB**: Leaves room for base64 overhead (~9.3MB) + JSON wrapper under the 10MB ceiling
- **`captureFrame` closure**: Decouples Stakeout from InsideMan's window compositing — InsideMan provides the closure
- **Inactivity = no screen changes AND no commands**: Both `noteActivity()` (commands) and `noteScreenChange()` (hierarchy changes) reset the timer

### Success Criteria:

#### Automated Verification:
- [x] InsideMan builds: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme InsideMan -destination 'generic/platform=iOS' build`

---

## Phase 3: InsideMan Integration

### Overview
Wire Stakeout into InsideMan's message handler, activity tracking, and screen change detection.

### Changes Required:

#### 1. Add Stakeout Instance and Recording-Aware Capture
**File**: `ButtonHeist/Sources/InsideMan/InsideMan.swift`
**Changes**: Add stakeout property and a capture method that includes the tap overlay

```swift
// Add property alongside existing state (near line 24):
private var stakeout: Stakeout?
```

Add a new capture method that includes all windows (including `TapOverlayWindow`):
```swift
/// Capture the screen including the tap overlay (for recordings).
/// Unlike captureScreen(), this includes TapOverlayWindow so
/// tap/swipe indicators are visible in the video.
private func captureScreenForRecording() -> UIImage? {
    guard let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else {
        return nil
    }

    let allWindows = windowScene.windows
        .filter { !$0.isHidden && $0.bounds.size != .zero }
        .sorted { $0.windowLevel < $1.windowLevel }

    guard let background = allWindows.first else { return nil }
    let bounds = background.bounds

    let renderer = UIGraphicsImageRenderer(bounds: bounds)
    return renderer.image { _ in
        for window in allWindows {
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
    }
}
```

Note: uses `afterScreenUpdates: false` for recording frames to avoid forcing a CA commit every frame, reducing main thread impact at 8 FPS.

#### 2. Handle New Client Messages
**File**: `ButtonHeist/Sources/InsideMan/InsideMan.swift`
**Changes**: Add cases to `handleClientMessage` switch (after `case .requestScreen:` at line 296)

```swift
case .startRecording(let config):
    handleStartRecording(config, respond: respond)
case .stopRecording:
    handleStopRecording(respond: respond)
```

#### 3. Add Recording Handler Methods
**File**: `ButtonHeist/Sources/InsideMan/InsideMan.swift`
**Changes**: Add handler methods

```swift
private func handleStartRecording(_ config: RecordingConfig, respond: @escaping (Data) -> Void) {
    if stakeout?.state == .recording {
        sendMessage(.recordingError("Recording already in progress"), respond: respond)
        return
    }

    let recorder = Stakeout()
    recorder.captureFrame = { [weak self] in
        self?.captureScreenForRecording()
    }
    recorder.onRecordingComplete = { [weak self] result in
        switch result {
        case .success(let payload):
            if let data = try? JSONEncoder().encode(ServerMessage.recording(payload)) {
                self?.socketServer?.broadcastToAll(data)
            }
        case .failure(let error):
            if let data = try? JSONEncoder().encode(ServerMessage.recordingError(error.localizedDescription)) {
                self?.socketServer?.broadcastToAll(data)
            }
        }
        self?.stakeout = nil
    }

    stakeout = recorder
    do {
        try recorder.startRecording(config: config)
        sendMessage(.recordingStarted, respond: respond)
    } catch {
        sendMessage(.recordingError(error.localizedDescription), respond: respond)
        stakeout = nil
    }
}

private func handleStopRecording(respond: @escaping (Data) -> Void) {
    guard let stakeout, stakeout.state == .recording else {
        sendMessage(.recordingError("No recording in progress"), respond: respond)
        return
    }
    stakeout.stopRecording(reason: .manual)
    // Response comes asynchronously via onRecordingComplete
}
```

#### 4. Track Command Activity for Inactivity Timeout
**File**: `ButtonHeist/Sources/InsideMan/InsideMan.swift`
**Changes**: Add activity notification at the top of `handleClientMessage` (after line 271)

```swift
// Notify stakeout of client activity (for inactivity timeout)
stakeout?.noteActivity()
```

#### 5. Track Screen Changes for Inactivity Timeout
**File**: `ButtonHeist/Sources/InsideMan/InsideMan.swift`
**Changes**: Add screen change notification in `checkForChanges()` (inside the `if currentHash != lastHierarchyHash` block at line 477)

```swift
// Notify stakeout of screen change (for inactivity timeout)
stakeout?.noteScreenChange()
```

#### 6. Capture Frames on Action Completion
**File**: `ButtonHeist/Sources/InsideMan/InsideMan.swift`
**Changes**: After every action that produces an `ActionResult`, capture an extra frame so the interaction is guaranteed to appear in the recording. Add a helper and call it from `sendActionResult` or equivalent:

```swift
/// If recording, capture a bonus frame to ensure the action's visual effect is captured.
private func captureActionFrame() {
    stakeout?.captureActionFrame()
}
```

Call `captureActionFrame()` after dispatching the action result in each action handler (tap, swipe, long press, type, etc.). This captures the state right after the action — with the tap overlay still visible.

**In Stakeout.swift**, add the corresponding method:
```swift
/// Capture an extra frame outside the regular timer cadence.
/// Used to ensure actions are represented in the recording.
func captureActionFrame() {
    guard state == .recording else { return }
    captureAndAppendFrame()
}
```

### Success Criteria:

#### Automated Verification:
- [x] InsideMan builds: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme InsideMan -destination 'generic/platform=iOS' build`
- [x] Full build: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme AccessibilityTestApp -destination 'platform=iOS Simulator,name=iPhone 16' build`

---

## Phase 4: Client-Side API (Wheelman + HeistClient)

### Overview
Add recording support to the Mac-side client libraries so consumers (CLI, MCP) can start/stop recordings and receive the video data.

### Changes Required:

#### 1. Handle Recording Messages in DeviceConnection
**File**: `ButtonHeist/Sources/Wheelman/DeviceConnection.swift`
**Changes**: Add callbacks and handle new server messages

```swift
// Add callbacks (alongside existing onScreen):
public var onRecordingStarted: (() -> Void)?
public var onRecording: ((RecordingPayload) -> Void)?
public var onRecordingError: ((String) -> Void)?
```

And in the message handling switch:
```swift
case .recordingStarted:
    onRecordingStarted?()
case .recording(let payload):
    onRecording?(payload)
case .recordingError(let message):
    onRecordingError?(message)
```

#### 2. Add Recording API to HeistClient
**File**: `ButtonHeist/Sources/ButtonHeist/HeistClient.swift`
**Changes**: Add recording state, callbacks, and async wait methods

```swift
// Add observable state (near line 21):
public private(set) var isRecording: Bool = false

// Add callbacks (near line 39):
public var onRecordingStarted: (() -> Void)?
public var onRecording: ((RecordingPayload) -> Void)?
public var onRecordingError: ((String) -> Void)?
```

Wire up in `connect(to:)`:
```swift
connection?.onRecordingStarted = { [weak self] in
    self?.isRecording = true
    self?.onRecordingStarted?()
}
connection?.onRecording = { [weak self] payload in
    self?.isRecording = false
    self?.onRecording?(payload)
}
connection?.onRecordingError = { [weak self] message in
    self?.isRecording = false
    self?.onRecordingError?(message)
}
```

Add async wait method:
```swift
/// Wait for a recording result with timeout
public func waitForRecording(timeout: TimeInterval = 120.0) async throws -> RecordingPayload {
    try await withCheckedThrowingContinuation { continuation in
        var didResume = false

        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            if !didResume {
                didResume = true
                continuation.resume(throwing: ActionError.timeout)
            }
        }

        onRecording = { payload in
            if !didResume {
                didResume = true
                timeoutTask.cancel()
                continuation.resume(returning: payload)
            }
        }

        onRecordingError = { message in
            if !didResume {
                didResume = true
                timeoutTask.cancel()
                continuation.resume(throwing: RecordingError.serverError(message))
            }
        }
    }
}

public enum RecordingError: Error, LocalizedError {
    case serverError(String)
    public var errorDescription: String? {
        switch self {
        case .serverError(let msg): return "Recording failed: \(msg)"
        }
    }
}
```

Reset `isRecording` on disconnect (in `disconnect()` and `onDisconnected`).

### Success Criteria:

#### Automated Verification:
- [x] Wheelman builds: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme Wheelman build`
- [x] ButtonHeist builds: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme ButtonHeist build`
- [x] Existing WheelmanTests pass: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme WheelmanTests test`
- [x] Existing ButtonHeistTests pass: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme ButtonHeistTests test`

---

## Phase 5: CLI Support

### Overview
Add a `record` CLI command and session commands for starting/stopping recordings.

### Changes Required:

#### 1. New Record Command
**File**: `ButtonHeistCLI/Sources/RecordCommand.swift` (new file)
**Changes**: Standalone `buttonheist record` command

```swift
import ArgumentParser
import Foundation
import ButtonHeist

struct RecordCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "record",
        abstract: "Record the screen of the connected device"
    )

    @Option(name: .shortAndLong, help: "Output file path (default: recording.mp4)")
    var output: String = "recording.mp4"

    @Option(name: .long, help: "Frames per second (1-15, default: 8)")
    var fps: Int = 8

    @Option(name: .long, help: "Resolution scale of native pixels (0.25-1.0, default: 1x point size)")
    var scale: Double?

    @Option(name: .long, help: "Inactivity timeout in seconds (default: 5)")
    var inactivityTimeout: Double = 5.0

    @Option(name: .long, help: "Max recording duration in seconds (default: 60)")
    var maxDuration: Double = 60.0

    @Option(name: .long, help: "Connection timeout in seconds")
    var timeout: Double = 10.0

    @Flag(name: .shortAndLong, help: "Suppress status messages")
    var quiet: Bool = false

    @Option(name: .long, help: "Target device by name, ID prefix, or index")
    var device: String?

    @MainActor
    func run() async throws {
        let connector = DeviceConnector(deviceFilter: device, quiet: quiet)
        try await connector.connect()
        defer { connector.disconnect() }
        let client = connector.client

        if !quiet { logStatus("Starting recording...") }

        let config = RecordingConfig(
            fps: fps,
            scale: scale,
            inactivityTimeout: inactivityTimeout,
            maxDuration: maxDuration
        )
        client.send(.startRecording(config))

        let payload = try await client.waitForRecording(timeout: maxDuration + 30)

        guard let videoData = Data(base64Encoded: payload.videoData) else {
            throw ValidationError("Failed to decode video data")
        }

        let url = URL(fileURLWithPath: output)
        try videoData.write(to: url)

        if !quiet {
            logStatus("Recording saved: \(output)")
            logStatus("  Duration: \(String(format: "%.1f", payload.duration))s")
            logStatus("  Frames: \(payload.frameCount)")
            logStatus("  Resolution: \(payload.width)x\(payload.height)")
            logStatus("  Size: \(videoData.count / 1024)KB")
            logStatus("  Stop reason: \(payload.stopReason.rawValue)")
        }
    }
}
```

#### 2. Register Record Command
**File**: `ButtonHeistCLI/Sources/main.swift`
**Changes**: Add `RecordCommand` to the command list (alongside `ScreenshotCommand`)

#### 3. Session Commands
**File**: `ButtonHeistCLI/Sources/SessionCommand.swift`
**Changes**: Add `start_recording` and `stop_recording` to the session dispatch

In the help list (line 212-220):
```swift
"start_recording", "stop_recording",
```

In the dispatch switch:
```swift
case "start_recording":
    guard client.connectionState == .connected else {
        throw SessionError.notConnected
    }
    let config = RecordingConfig(
        fps: intArg(args, "fps"),
        scale: doubleArg(args, "scale"),
        inactivityTimeout: doubleArg(args, "inactivity_timeout"),
        maxDuration: doubleArg(args, "max_duration")
    )
    client.send(.startRecording(config))
    return .ok(message: "Recording started")

case "stop_recording":
    guard client.connectionState == .connected else {
        throw SessionError.notConnected
    }
    client.send(.stopRecording)
    do {
        let recording = try await client.waitForRecording(timeout: 30)
        if let outputPath = stringArg(args, "output") {
            guard let videoData = Data(base64Encoded: recording.videoData) else {
                return .error("Failed to decode video data")
            }
            try videoData.write(to: URL(fileURLWithPath: outputPath))
            return .recording(path: outputPath, payload: recording)
        } else {
            return .recordingData(payload: recording)
        }
    } catch {
        client.forceDisconnect()
        throw SessionError.actionTimeout
    }
```

#### 4. Session Response Cases
**File**: `ButtonHeistCLI/Sources/SessionCommand.swift`
**Changes**: Add recording response variants to `SessionResponse` enum and formatting

```swift
case recording(path: String, payload: RecordingPayload)
case recordingData(payload: RecordingPayload)
```

With corresponding `humanFormatted()` and `jsonDict()` implementations.

### Success Criteria:

#### Automated Verification:
- [x] CLI builds: `swift build --package-path ButtonHeistCLI`
- [x] Existing CLI tests pass: `swift test --package-path ButtonHeistCLI`

---

## Phase 6: MCP Tool Support

### Overview
Add `record_screen` tool to the MCP server, following the same temp-file pattern used for `get_screen`.

### Changes Required:

#### 1. MCP Record Screen Tool
**File**: `ButtonHeistMCP/Sources/main.swift`
**Changes**: Add recording support to the tool handler

The flow mirrors the screenshot pattern:
1. MCP tool receives `record_screen` command with optional config params
2. Sends `start_recording` through the session pipe
3. Waits for recording to complete
4. Sends `stop_recording` if the caller provides a stop signal
5. Writes the MP4 to a temp file
6. Returns the video data as a base64-encoded resource or file path

Since recording is async (start → interact → stop), the MCP tool should support:
- `{"command": "start_recording", "fps": 8, "scale": 0.5}` — begins recording, returns immediately
- `{"command": "stop_recording", "output": "/tmp/video.mp4"}` — stops and writes file

This maps naturally to the existing session command architecture — no special MCP handling needed beyond routing these commands through the pipe.

### Success Criteria:

#### Automated Verification:
- [x] MCP server builds: `cd ButtonHeistMCP && swift build -c release`

---

## Phase 7: Tests

### Overview
Add protocol tests for the new message types and payload encoding.

### Changes Required:

#### 1. Recording Payload Tests
**File**: `ButtonHeist/Tests/TheGoodsTests/RecordingPayloadTests.swift` (new file)
**Changes**: Test encode/decode round-tripping for all new types

- `RecordingConfig` encode/decode with all fields, with defaults (nil fields)
- `RecordingPayload` encode/decode with all stop reasons
- `ClientMessage.startRecording` encode/decode
- `ClientMessage.stopRecording` encode/decode
- `ServerMessage.recording` encode/decode
- `ServerMessage.recordingStarted` encode/decode
- `ServerMessage.recordingError` encode/decode

#### 2. Session Response Tests
**File**: `ButtonHeistCLI/Tests/SessionResponseTests.swift`
**Changes**: Add tests for new recording response types (human + JSON formatting)

### Success Criteria:

#### Automated Verification:
- [x] TheGoodsTests pass: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme TheGoodsTests test`
- [x] CLI tests pass: `swift test --package-path ButtonHeistCLI`

---

## Phase 8: Documentation

### Overview
Update all affected documentation to reflect the new recording capability.

### Changes Required:

#### 1. API Documentation
**File**: `docs/API.md`
- Add `RecordingConfig` and `RecordingPayload` type docs
- Add `startRecording` / `stopRecording` client message docs
- Add `recording` / `recordingStarted` / `recordingError` server message docs
- Add `HeistClient.waitForRecording()` API docs
- Add `buttonheist record` CLI docs
- Add `start_recording` / `stop_recording` session command docs

#### 2. Wire Protocol Documentation
**File**: `docs/WIRE-PROTOCOL.md`
- Add recording message format examples
- Document inactivity timeout behavior
- Document file size guardrails

#### 3. Architecture Documentation
**File**: `docs/ARCHITECTURE.md`
- Add Stakeout component description
- Update data flow diagrams

#### 4. README
**File**: `README.md`
- Add screen recording to feature list
- Add recording usage example

### Success Criteria:

#### Automated Verification:
- [x] All builds pass (full pre-commit checklist)
- [x] All tests pass

---

## Testing Strategy

### Unit Tests:
- `RecordingConfig` / `RecordingPayload` Codable round-trips (all permutations of optional fields)
- `ClientMessage.startRecording` / `.stopRecording` encode/decode
- `ServerMessage.recording` / `.recordingStarted` / `.recordingError` encode/decode
- `StopReason` enum encode/decode
- Session response formatting (human + JSON) for recording variants

### Integration Tests:
- Full simulator round-trip: `start_recording` → tap some elements → `stop_recording` → verify MP4 is playable
- Inactivity timeout: start recording with short timeout, do nothing, verify auto-stop with correct reason
- File size guard: start recording with very high FPS and scale, verify early stop with `fileSizeLimit` reason
- Already-recording error: send `startRecording` twice, verify error on second attempt
- Stop-without-start error: send `stopRecording` without starting, verify error

### CLI Tests:
- `buttonheist record --output test.mp4` produces a valid MP4 file
- `buttonheist record --fps 5 --scale 0.25` respects config options

## Performance Considerations

- **Frame capture cost**: `drawHierarchy(in:afterScreenUpdates:true)` is the bottleneck — at 8 FPS this means ~125ms budget per frame. The `afterScreenUpdates:true` flag forces a CA commit which can take 10-30ms. At half resolution this should be comfortable.
- **Memory**: `AVAssetWriter` writes to disk progressively, so memory usage stays bounded regardless of duration. The pixel buffer pool reuses buffers.
- **CPU**: H.264 encoding happens on VideoToolbox hardware (even in simulator on Apple Silicon). CPU overhead is primarily the frame capture, not encoding.
- **Disk**: Temp file is cleaned up in `cleanup()`. If the app crashes mid-recording, temp files accumulate in `NSTemporaryDirectory()` — the OS cleans these periodically.
- **Wire size**: At default 1x point resolution (e.g., 393×852 on a 3x iPhone) and 8fps, a 30-second recording of typical app UI should be 1-3MB raw (1.3-4MB base64), well under the 10MB limit. The 7MB file size guard provides a hard backstop.

## References

- Existing screenshot flow: `InsideMan.swift:494-522`
- Wire protocol constraints: `SimpleSocketServer.swift:9` (10MB buffer), `WIRE-PROTOCOL.md`
- Client API pattern: `HeistClient.swift:190-210` (`waitForScreen` — model `waitForRecording` after this)
- CLI command pattern: `ScreenshotCommand.swift` (model `RecordCommand` after this)
- MCP temp file pattern: `ButtonHeistMCP/Sources/main.swift:147-169`
- Session dispatch pattern: `SessionCommand.swift:206-477`
