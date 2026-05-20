import Foundation

import TheScore

struct PublicRecordingResponse: FencePublicJSONResponse {
    let status = PublicStatus.ok
    let width: Int
    let height: Int
    let duration: Double
    let frameCount: Int
    let fps: Int
    let stopReason: String
    let interactionCount: Int
    let path: String?
    let videoData: String?
    let interactionLog: [InteractionEvent]?

    init(path: String?, payload: RecordingPayload, options: RecordingResponseOptions) {
        self.width = payload.width
        self.height = payload.height
        self.duration = payload.duration
        self.frameCount = payload.frameCount
        self.fps = payload.fps
        self.stopReason = payload.stopReason.rawValue
        self.interactionCount = payload.interactionLog?.count ?? 0
        self.path = path
        self.videoData = options.inlineData ? payload.videoData : nil
        self.interactionLog = options.includeInteractionLog ? payload.interactionLog : nil
    }
}

struct PublicHeistStartedResponse: FencePublicJSONResponse {
    let status = PublicStatus.ok
    let recording = true
}

struct PublicHeistStoppedResponse: FencePublicJSONResponse {
    let status = PublicStatus.ok
    let path: String
    let stepCount: Int
}
