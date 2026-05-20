import Foundation

import TheScore

struct PublicSessionStateResponse: FencePublicJSONResponse {
    let status = PublicStatus.ok
    let connected: Bool
    let phase: String
    let isRecording: Bool
    let actionTimeoutSeconds: TimeInterval
    let longActionTimeoutSeconds: TimeInterval
    let deviceName: String?
    let appName: String?
    let connectionType: String?
    let shortId: String?
    let lastFailure: PublicSessionFailure?
    let lastAction: PublicSessionLastAction?

    init(payload: SessionStatePayload) {
        self.connected = payload.connected
        self.phase = payload.phase.rawValue
        self.isRecording = payload.isRecording
        self.actionTimeoutSeconds = payload.actionTimeoutSeconds
        self.longActionTimeoutSeconds = payload.longActionTimeoutSeconds
        self.deviceName = payload.device?.deviceName
        self.appName = payload.device?.appName
        self.connectionType = payload.device?.connectionType.rawValue
        self.shortId = payload.device?.shortId
        self.lastFailure = payload.lastFailure.map { PublicSessionFailure(payload: $0) }
        self.lastAction = payload.lastAction.map { PublicSessionLastAction(payload: $0) }
    }
}

struct PublicSessionFailure: Encodable {
    let errorCode: String
    let phase: String
    let retryable: Bool
    let message: String?
    let hint: String?

    init(payload: SessionFailurePayload) {
        self.errorCode = payload.errorCode
        self.phase = payload.phase.rawValue
        self.retryable = payload.retryable
        self.message = payload.message
        self.hint = payload.hint
    }
}

struct PublicSessionLastAction: Encodable {
    let method: String
    let success: Bool
    let message: String?
    let latencyMs: Int

    private enum CodingKeys: String, CodingKey {
        case method
        case success
        case message
        case latencyMs = "latency_ms"
    }

    init(payload: SessionLastActionPayload) {
        self.method = payload.method.rawValue
        self.success = payload.success
        self.message = payload.message
        self.latencyMs = payload.latencyMs
    }
}

struct PublicOKResponse: FencePublicJSONResponse {
    let status = PublicStatus.ok
    let message: String
}

struct PublicHelpResponse: FencePublicJSONResponse {
    let status = PublicStatus.ok
    let commands: [String]
}

struct PublicStatusResponse: FencePublicJSONResponse {
    let status = PublicStatus.ok
    let connected: Bool
    let device: String?
}

struct PublicDevicesResponse: FencePublicJSONResponse {
    let status = PublicStatus.ok
    let devices: [PublicDiscoveredDevice]

    init(devices: [DiscoveredDevice]) {
        self.devices = devices.map(PublicDiscoveredDevice.init)
    }
}

struct PublicDiscoveredDevice: Encodable {
    let name: String
    let appName: String
    let deviceName: String
    let connectionType: String
    let shortId: String?
    let simulatorUDID: String?

    init(device: DiscoveredDevice) {
        self.name = device.name
        self.appName = device.appName
        self.deviceName = device.deviceName
        self.connectionType = device.connectionType.rawValue
        self.shortId = device.shortId
        self.simulatorUDID = device.simulatorUDID
    }
}

struct PublicTargetsResponse: FencePublicJSONResponse {
    let status = PublicStatus.ok
    let targets: [String: PublicTargetConfig]
    let `default`: String?

    init(targets: [String: TargetConfig], defaultTarget: String?) {
        self.targets = targets.mapValues(PublicTargetConfig.init)
        self.default = defaultTarget
    }
}

struct PublicTargetConfig: Encodable {
    let device: String
    let hasToken: Bool?

    init(target: TargetConfig) {
        self.device = target.device
        self.hasToken = target.token == nil ? nil : true
    }
}

struct PublicSessionLogResponse: FencePublicJSONResponse {
    let status = PublicStatus.ok
    let formatVersion: String
    let sessionId: String
    let startTime: Date
    let endTime: Date?
    let commandCount: Int
    let errorCount: Int
    let artifactCount: Int
    let projectionStatus: PublicProjectionStatus?
    let artifacts: [PublicArtifactEntry]
    let path: String?

    init(snapshot: SessionLogSnapshot, path: String? = nil) {
        self.formatVersion = snapshot.manifest.formatVersion
        self.sessionId = snapshot.manifest.sessionId
        self.startTime = snapshot.manifest.startTime
        self.endTime = snapshot.manifest.endTime
        self.commandCount = snapshot.counts.commandCount
        self.errorCount = snapshot.counts.errorCount
        self.artifactCount = snapshot.artifacts.count
        self.projectionStatus = snapshot.projectionStatus.isDegraded
            ? PublicProjectionStatus(status: snapshot.projectionStatus)
            : nil
        self.artifacts = snapshot.artifacts.map(PublicArtifactEntry.init)
        self.path = path
    }
}

struct PublicArtifactEntry: Encodable {
    let type: String
    let path: String
    let size: Int
    let timestamp: Date
    let command: String
    let metadata: [String: Double]?

    init(artifact: ArtifactEntry) {
        self.type = artifact.type.rawValue
        self.path = artifact.path
        self.size = artifact.size
        self.timestamp = artifact.timestamp
        self.command = artifact.command
        self.metadata = artifact.metadata.isEmpty ? nil : artifact.metadata
    }
}

struct PublicProjectionStatus: Encodable {
    let degraded = true
    let malformedLineCount: Int
    let firstMalformedLineNumber: Int?
    let firstMalformedLineCause: String?
    let malformedArtifactCount: Int

    init(status: SessionLogProjectionStatus) {
        self.malformedLineCount = status.malformedLineCount
        self.firstMalformedLineNumber = status.firstMalformedLineNumber
        self.firstMalformedLineCause = status.firstMalformedLineCause
        self.malformedArtifactCount = status.malformedArtifactCount
    }
}
