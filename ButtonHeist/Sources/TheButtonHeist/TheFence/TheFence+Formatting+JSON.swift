import Foundation
import CoreGraphics
import os.log

import AccessibilitySnapshotModel
import TheScore

private let logger = Logger(subsystem: "com.buttonheist.thefence", category: "formatting")

private protocol FencePublicJSONResponse: Encodable {}

private struct PublicStatus: Encodable {
    static let ok = PublicStatus(value: "ok")
    static let error = PublicStatus(value: "error")

    let value: String

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

private struct PublicErrorResponse: FencePublicJSONResponse {
    let status = PublicStatus.error
    let message: String
    let errorCode: String?
    let phase: String?
    let retryable: Bool?
    let hint: String?

    init(message: String, details: FailureDetails?) {
        self.message = message
        self.errorCode = details?.errorCode
        self.phase = details?.phase.rawValue
        self.retryable = details?.retryable
        self.hint = details?.hint
    }
}

private struct PublicInterfaceResponse: FencePublicJSONResponse {
    let status = PublicStatus.ok
    let detail: String
    let interface: PublicInterface

    init(interface: Interface, detail: InterfaceDetail) {
        self.detail = detail.rawValue
        self.interface = PublicInterface(interface: interface, detail: detail)
    }
}

private struct PublicInterface: Encodable {
    let timestamp: String
    let screenDescription: String
    let screenId: String?
    let navigation: PublicNavigation
    let tree: [PublicTreeNode]

    init(interface: Interface, detail: InterfaceDetail) {
        let formatter = ISO8601DateFormatter()
        self.timestamp = formatter.string(from: interface.timestamp)
        self.screenDescription = interface.screenDescription
        self.screenId = interface.screenId
        self.navigation = PublicNavigation(navigation: interface.navigation)
        let counter = PublicIndexCounter()
        self.tree = PublicTreeNode.nodes(
            from: interface.tree,
            detail: detail,
            counter: counter,
            elementAnnotations: interface.annotations.elementByPath,
            containerAnnotations: interface.annotations.containerByPath
        )
    }
}

private struct PublicNavigation: Encodable {
    let screenTitle: String?
    let backButton: PublicNavigationItem?
    let tabBarItems: [PublicTabBarItem]?

    init(navigation: NavigationContext) {
        self.screenTitle = navigation.screenTitle
        self.backButton = navigation.backButton.map { PublicNavigationItem(item: $0) }
        self.tabBarItems = navigation.tabBarItems?.map { PublicTabBarItem(item: $0) }
    }
}

private struct PublicNavigationItem: Encodable {
    let heistId: String
    let label: String?
    let value: String?

    init(item: NavigationContext.NavigationItem) {
        self.heistId = item.heistId
        self.label = item.label
        self.value = item.value
    }
}

private struct PublicTabBarItem: Encodable {
    let heistId: String
    let label: String?
    let value: String?
    let selected: Bool?

    init(item: NavigationContext.TabBarItem) {
        self.heistId = item.heistId
        self.label = item.label
        self.value = item.value
        self.selected = item.selected ? true : nil
    }
}

private final class PublicIndexCounter {
    var value = 0
}

private enum PublicTreeNode: Encodable {
    case element(PublicElement)
    case container(PublicContainer)

    private enum CodingKeys: String, CodingKey {
        case element
        case container
    }

    static func nodes(
        from tree: [AccessibilityHierarchy],
        detail: InterfaceDetail,
        counter: PublicIndexCounter?,
        elementAnnotations: [TreePath: InterfaceElementAnnotation],
        containerAnnotations: [TreePath: InterfaceContainerAnnotation]
    ) -> [PublicTreeNode] {
        tree.enumerated().map { index, node in
            Self.node(
                from: node,
                path: TreePath([index]),
                detail: detail,
                counter: counter,
                elementAnnotations: elementAnnotations,
                containerAnnotations: containerAnnotations
            )
        }
    }

    static func node(
        from node: AccessibilityHierarchy,
        path: TreePath,
        detail: InterfaceDetail,
        counter: PublicIndexCounter?,
        elementAnnotations: [TreePath: InterfaceElementAnnotation],
        containerAnnotations: [TreePath: InterfaceContainerAnnotation]
    ) -> PublicTreeNode {
        switch node {
        case .element(let element, _):
            let projected = HeistElement(
                accessibilityElement: element,
                annotation: elementAnnotations[path]
            )
            let order = counter?.value
            counter?.value += 1
            return .element(PublicElement(element: projected, detail: detail, order: order))
        case .container(let container, let children):
            let childNodes = children.enumerated().map { index, child in
                Self.node(
                    from: child,
                    path: path.appending(index),
                    detail: detail,
                    counter: counter,
                    elementAnnotations: elementAnnotations,
                    containerAnnotations: containerAnnotations
                )
            }
            return .container(PublicContainer(
                container: container,
                annotation: containerAnnotations[path],
                detail: detail,
                children: childNodes
            ))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .element(let element):
            try container.encode(element, forKey: .element)
        case .container(let node):
            try container.encode(node, forKey: .container)
        }
    }
}

private struct PublicElement: Encodable {
    let heistId: String
    let traits: [String]
    let actions: [String]?
    let rotors: [String]?
    let label: String?
    let value: String?
    let identifier: String?
    let hint: String?
    let customContent: PublicCustomContent?
    let frameX: Double?
    let frameY: Double?
    let frameWidth: Double?
    let frameHeight: Double?
    let activationPointX: Double?
    let activationPointY: Double?
    let order: Int?

    init(element: HeistElement, detail: InterfaceDetail, order: Int? = nil) {
        self.heistId = element.heistId
        self.traits = element.traits.map(\.rawValue)
        let meaningfulActions = FenceResponse.meaningfulActions(element)
        self.actions = meaningfulActions.isEmpty ? nil : meaningfulActions.map(\.description)
        self.rotors = element.rotors?.isEmpty == false ? element.rotors?.map(\.name) : nil
        self.label = element.label
        self.value = element.value
        self.identifier = element.identifier
        self.order = order
        guard detail == .full else {
            self.hint = nil
            self.customContent = nil
            self.frameX = nil
            self.frameY = nil
            self.frameWidth = nil
            self.frameHeight = nil
            self.activationPointX = nil
            self.activationPointY = nil
            return
        }
        self.hint = element.hint
        self.customContent = element.customContent.map { PublicCustomContent(items: $0) }
        self.frameX = element.frameX
        self.frameY = element.frameY
        self.frameWidth = element.frameWidth
        self.frameHeight = element.frameHeight
        self.activationPointX = element.activationPointX
        self.activationPointY = element.activationPointY
    }
}

private struct PublicCustomContent: Encodable {
    let important: [PublicCustomContentEntry]?
    let `default`: [PublicCustomContentEntry]?

    init(items: [HeistCustomContent]) {
        let importantItems = items.filter(\.isImportant)
        let defaultItems = items.filter { !$0.isImportant }
        self.important = importantItems.isEmpty ? nil : importantItems.map { PublicCustomContentEntry(item: $0) }
        self.default = defaultItems.isEmpty ? nil : defaultItems.map { PublicCustomContentEntry(item: $0) }
    }
}

private struct PublicCustomContentEntry: Encodable {
    let label: String?
    let value: String?

    init(item: HeistCustomContent) {
        self.label = item.label.isEmpty ? nil : item.label
        self.value = item.value.isEmpty ? nil : item.value
    }
}

private struct PublicContainer: Encodable {
    let type: String
    let label: String?
    let value: String?
    let identifier: String?
    let rowCount: Int?
    let columnCount: Int?
    let contentWidth: Double?
    let contentHeight: Double?
    let isModalBoundary: Bool?
    let stableId: String?
    let frameX: Double?
    let frameY: Double?
    let frameWidth: Double?
    let frameHeight: Double?
    let children: [PublicTreeNode]

    init(
        container: AccessibilityContainer,
        annotation: InterfaceContainerAnnotation?,
        detail: InterfaceDetail,
        children: [PublicTreeNode]
    ) {
        switch container.type {
        case .semanticGroup(let label, let value, let identifier):
            self.type = "semanticGroup"
            self.label = label
            self.value = value
            self.identifier = identifier
            self.rowCount = nil
            self.columnCount = nil
            self.contentWidth = nil
            self.contentHeight = nil
        case .list:
            self.type = "list"
            self.label = nil
            self.value = nil
            self.identifier = nil
            self.rowCount = nil
            self.columnCount = nil
            self.contentWidth = nil
            self.contentHeight = nil
        case .landmark:
            self.type = "landmark"
            self.label = nil
            self.value = nil
            self.identifier = nil
            self.rowCount = nil
            self.columnCount = nil
            self.contentWidth = nil
            self.contentHeight = nil
        case .dataTable(let rowCount, let columnCount):
            self.type = "dataTable"
            self.label = nil
            self.value = nil
            self.identifier = nil
            self.rowCount = rowCount
            self.columnCount = columnCount
            self.contentWidth = nil
            self.contentHeight = nil
        case .tabBar:
            self.type = "tabBar"
            self.label = nil
            self.value = nil
            self.identifier = nil
            self.rowCount = nil
            self.columnCount = nil
            self.contentWidth = nil
            self.contentHeight = nil
        case .scrollable(let contentSize):
            self.type = "scrollable"
            self.label = nil
            self.value = nil
            self.identifier = nil
            self.rowCount = nil
            self.columnCount = nil
            self.contentWidth = Self.sanitizedDouble(contentSize.width)
            self.contentHeight = Self.sanitizedDouble(contentSize.height)
        }
        self.isModalBoundary = container.isModalBoundary ? true : nil
        self.stableId = annotation?.stableId
        self.children = children
        guard detail == .full else {
            self.frameX = nil
            self.frameY = nil
            self.frameWidth = nil
            self.frameHeight = nil
            return
        }
        self.frameX = Self.sanitizedDouble(container.frame.origin.x)
        self.frameY = Self.sanitizedDouble(container.frame.origin.y)
        self.frameWidth = Self.sanitizedDouble(container.frame.size.width)
        self.frameHeight = Self.sanitizedDouble(container.frame.size.height)
    }

    private static func sanitizedDouble(_ value: CGFloat) -> Double {
        value.isFinite ? Double(value) : 0
    }
}

private struct PublicSessionStateResponse: FencePublicJSONResponse {
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

private struct PublicSessionFailure: Encodable {
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

private struct PublicSessionLastAction: Encodable {
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

private struct PublicActionResponse: FencePublicJSONResponse {
    let status: PublicStatus
    let method: String
    let message: String?
    let value: String?
    let rotor: PublicRotorResult?
    let animating: Bool?
    let delta: PublicDelta?
    let screenName: String?
    let screenId: String?
    let explore: PublicExploreResult?
    let errorClass: String?
    let errorCode: String?
    let phase: String?
    let retryable: Bool?
    let hint: String?
    let expectation: PublicExpectationResult?

    init(result: ActionResult, expectation: ExpectationResult?) {
        if let expectation, !expectation.met {
            self.status = PublicStatus(value: "expectation_failed")
        } else {
            self.status = result.success ? .ok : .error
        }
        self.method = result.method.rawValue
        self.message = result.message
        if case .value(let value) = result.payload {
            self.value = value
        } else {
            self.value = nil
        }
        if case .rotor(let rotor) = result.payload {
            self.rotor = PublicRotorResult(result: rotor)
        } else {
            self.rotor = nil
        }
        self.animating = result.animating == true ? true : nil
        self.delta = result.accessibilityDelta.map(PublicDelta.init)
        self.screenName = result.screenName
        self.screenId = result.screenId
        if case .explore(let explore) = result.payload {
            self.explore = PublicExploreResult(result: explore)
        } else {
            self.explore = nil
        }
        if result.success {
            self.errorClass = nil
            self.errorCode = nil
            self.phase = nil
            self.retryable = nil
            self.hint = nil
        } else {
            self.errorClass = (result.errorKind ?? .actionFailed).rawValue
            let details = FenceResponse.actionFailureDetails(result)
            self.errorCode = details?.errorCode
            self.phase = details?.phase.rawValue
            self.retryable = details?.retryable
            self.hint = details?.hint
        }
        self.expectation = expectation.map { PublicExpectationResult(result: $0) }
    }
}

private struct PublicRotorResult: Encodable {
    let name: String
    let direction: String
    let foundElement: PublicElement?
    let textRange: PublicRotorTextRange?

    init(result: RotorResult) {
        self.name = result.rotor
        self.direction = result.direction.rawValue
        self.foundElement = result.foundElement.map { PublicElement(element: $0, detail: .summary) }
        self.textRange = result.textRange.map { PublicRotorTextRange(range: $0) }
    }
}

private struct PublicRotorTextRange: Encodable {
    let rangeDescription: String
    let text: String?
    let startOffset: Int?
    let endOffset: Int?

    init(range: RotorTextRange) {
        self.rangeDescription = range.rangeDescription
        self.text = range.text
        self.startOffset = range.startOffset
        self.endOffset = range.endOffset
    }
}

private struct PublicExploreResult: Encodable {
    let elementCount: Int
    let scrollCount: Int
    let containersExplored: Int
    let explorationTime: String

    init(result: ExploreResult) {
        self.elementCount = result.elementCount
        self.scrollCount = result.scrollCount
        self.containersExplored = result.containersExplored
        self.explorationTime = String(format: "%.2f", result.explorationTime)
    }
}

private struct PublicExpectationResult: Encodable {
    let met: Bool
    let actual: String?
    let expected: ActionExpectation?

    init(result: ExpectationResult) {
        self.met = result.met
        self.actual = result.actual
        self.expected = result.expectation
    }
}

private struct PublicDelta: Encodable {
    let kind: String
    let elementCount: Int
    let captureEdge: AccessibilityTrace.CaptureEdge?
    let transient: [PublicElement]?
    let edits: PublicElementEdits?
    let newInterface: PublicInterface?

    init(delta: AccessibilityTrace.Delta) {
        self.kind = delta.kindRawValue
        self.elementCount = delta.elementCount
        self.captureEdge = delta.captureEdge
        self.transient = delta.transient.isEmpty ? nil : delta.transient.map { PublicElement(element: $0, detail: .summary) }
        switch delta {
        case .noChange:
            self.edits = nil
            self.newInterface = nil
        case .elementsChanged(let payload):
            let edits = PublicElementEdits(edits: payload.edits)
            self.edits = edits.isEmpty ? nil : edits
            self.newInterface = nil
        case .screenChanged(let payload):
            self.edits = nil
            self.newInterface = PublicInterface(interface: payload.newInterface, detail: .summary)
        }
    }
}

private struct PublicElementEdits: Encodable {
    let added: [PublicElement]?
    let removed: [String]?
    let updated: [PublicElementUpdate]?
    let treeInserted: [PublicTreeInsertion]?
    let treeRemoved: [TreeRemoval]?
    let treeMoved: [TreeMove]?

    var isEmpty: Bool {
        added == nil && removed == nil && updated == nil && treeInserted == nil && treeRemoved == nil && treeMoved == nil
    }

    init(edits: ElementEdits) {
        self.added = edits.added.isEmpty ? nil : edits.added.map { PublicElement(element: $0, detail: .summary) }
        self.removed = edits.removed.isEmpty ? nil : edits.removed
        let filteredUpdates = edits.updated.compactMap { PublicElementUpdate(update: $0) }
        self.updated = filteredUpdates.isEmpty ? nil : filteredUpdates
        self.treeInserted = edits.treeInserted.isEmpty ? nil : edits.treeInserted.map { PublicTreeInsertion(insertion: $0) }
        self.treeRemoved = edits.treeRemoved.isEmpty ? nil : edits.treeRemoved
        self.treeMoved = edits.treeMoved.isEmpty ? nil : edits.treeMoved
    }
}

private struct PublicElementUpdate: Encodable {
    let heistId: String
    let changes: [PropertyChange]

    init?(update: ElementUpdate) {
        let meaningfulChanges = update.changes.filter { !$0.property.isGeometry }
        guard !meaningfulChanges.isEmpty else { return nil }
        self.heistId = update.heistId
        self.changes = meaningfulChanges
    }
}

private struct PublicTreeInsertion: Encodable {
    let location: TreeLocation
    let node: PublicTreeNode

    init(insertion: TreeInsertion) {
        self.location = insertion.location
        self.node = PublicTreeNode.node(
            from: insertion.node,
            path: .root,
            detail: .summary,
            counter: nil,
            elementAnnotations: insertion.annotations.elementByPath,
            containerAnnotations: insertion.annotations.containerByPath
        )
    }
}

private struct PublicRecordingResponse: FencePublicJSONResponse {
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

private struct PublicOKResponse: FencePublicJSONResponse {
    let status = PublicStatus.ok
    let message: String
}

private struct PublicHelpResponse: FencePublicJSONResponse {
    let status = PublicStatus.ok
    let commands: [String]
}

private struct PublicStatusResponse: FencePublicJSONResponse {
    let status = PublicStatus.ok
    let connected: Bool
    let device: String?
}

private struct PublicDevicesResponse: FencePublicJSONResponse {
    let status = PublicStatus.ok
    let devices: [PublicDiscoveredDevice]

    init(devices: [DiscoveredDevice]) {
        self.devices = devices.map(PublicDiscoveredDevice.init)
    }
}

private struct PublicDiscoveredDevice: Encodable {
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

private struct PublicScreenshotResponse: FencePublicJSONResponse {
    let status = PublicStatus.ok
    let width: Double
    let height: Double
    let pngData: String?
    let interface: PublicInterface?
    let path: String?

    init(path: String?, payload: ScreenPayload, includePNGData: Bool, includeInterface: Bool) {
        self.width = payload.width
        self.height = payload.height
        self.pngData = includePNGData ? payload.pngData : nil
        self.interface = includeInterface ? PublicInterface(interface: payload.interface, detail: .full) : nil
        self.path = path
    }
}

private struct PublicBatchResponse: FencePublicJSONResponse {
    let status: PublicStatus
    let results: [PublicResponseModel]
    let completedSteps: Int
    let totalTimingMs: Int
    let failedIndex: Int?
    let expectations: PublicBatchExpectations?
    let stepSummaries: [PublicBatchStepSummary]?
    let netDelta: PublicDelta?

    init(outcomes: [BatchStepOutcome], totalTimingMs: Int, accessibilityTrace: AccessibilityTrace?) {
        let failedIndex = outcomes.stoppedFailedIndex
        self.status = PublicStatus(value: failedIndex == nil ? "ok" : "partial")
        self.results = outcomes.compactMap(\.response).map(PublicResponseModel.init)
        self.completedSteps = outcomes.completedStepCount
        self.totalTimingMs = totalTimingMs
        self.failedIndex = failedIndex
        let checked = outcomes.expectationsChecked
        self.expectations = checked > 0
            ? PublicBatchExpectations(checked: checked, met: outcomes.expectationsMet)
            : nil
        let summaries = outcomes.stepSummaries.enumerated().map { index, summary in
            PublicBatchStepSummary(index: index, summary: summary)
        }
        self.stepSummaries = summaries.isEmpty ? nil : summaries
        self.netDelta = accessibilityTrace?.meaningfulCaptureEndpointDelta.map(PublicDelta.init)
    }
}

private struct PublicBatchExpectations: Encodable {
    let checked: Int
    let met: Int
    let allMet: Bool

    init(checked: Int, met: Int) {
        self.checked = checked
        self.met = met
        self.allMet = checked == met
    }
}

private struct PublicBatchStepSummary: Encodable {
    let index: Int
    let command: String
    let deltaKind: String?
    let screenName: String?
    let screenId: String?
    let expectationMet: Bool?
    let elementCount: Int?
    let error: String?
    let errorCode: String?
    let phase: String?
    let nextCommand: String?

    init(index: Int, summary: BatchStepSummary) {
        self.index = index
        self.command = summary.command
        self.deltaKind = summary.deltaKind
        self.screenName = summary.screenName
        self.screenId = summary.screenId
        self.expectationMet = summary.expectationMet
        self.elementCount = summary.elementCount
        self.error = summary.error
        self.errorCode = summary.errorCode
        self.phase = summary.phase
        self.nextCommand = summary.nextCommand
    }
}

private struct PublicTargetsResponse: FencePublicJSONResponse {
    let status = PublicStatus.ok
    let targets: [String: PublicTargetConfig]
    let `default`: String?

    init(targets: [String: TargetConfig], defaultTarget: String?) {
        self.targets = targets.mapValues(PublicTargetConfig.init)
        self.default = defaultTarget
    }
}

private struct PublicTargetConfig: Encodable {
    let device: String
    let hasToken: Bool?

    init(target: TargetConfig) {
        self.device = target.device
        self.hasToken = target.token == nil ? nil : true
    }
}

private struct PublicSessionLogResponse: FencePublicJSONResponse {
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

private struct PublicArtifactEntry: Encodable {
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

private struct PublicProjectionStatus: Encodable {
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

private struct PublicHeistStartedResponse: FencePublicJSONResponse {
    let status = PublicStatus.ok
    let recording = true
}

private struct PublicHeistStoppedResponse: FencePublicJSONResponse {
    let status = PublicStatus.ok
    let path: String
    let stepCount: Int
}

private struct PublicPlaybackResponse: FencePublicJSONResponse {
    let status: PublicStatus
    let completedSteps: Int
    let failedIndex: Int?
    let totalTimingMs: Int
    let failure: PublicPlaybackFailure?

    init(completedSteps: Int, failedIndex: Int?, totalTimingMs: Int, failure: PlaybackFailure?) {
        self.status = PublicStatus(value: failedIndex == nil ? "ok" : "error")
        self.completedSteps = completedSteps
        self.failedIndex = failedIndex
        self.totalTimingMs = totalTimingMs
        self.failure = failure.map(PublicPlaybackFailure.init)
    }
}

private struct PublicPlaybackFailure: Encodable {
    let command: String
    let error: String
    let target: PublicPlaybackTarget?
    let actionResult: PublicActionResponse?
    let expectation: PublicExpectationResult?
    let interface: PublicInterface?

    init(failure: PlaybackFailure) {
        self.command = failure.step.command
        self.error = failure.errorMessage
        self.target = failure.step.target.map(PublicPlaybackTarget.init)
        switch failure {
        case .actionFailed(_, let result, let expectation, let interface):
            self.actionResult = PublicActionResponse(result: result, expectation: nil)
            if let expectation, !expectation.met {
                self.expectation = PublicExpectationResult(result: expectation)
            } else {
                self.expectation = nil
            }
            self.interface = interface.map { PublicInterface(interface: $0, detail: .summary) }
        case .fenceError(_, _, let interface), .thrown(_, _, let interface):
            self.actionResult = nil
            self.expectation = nil
            self.interface = interface.map { PublicInterface(interface: $0, detail: .summary) }
        }
    }
}

private struct PublicPlaybackTarget: Encodable {
    let label: String?
    let identifier: String?
    let value: String?
    let traits: [String]?

    init(target: ElementMatcher) {
        self.label = target.label
        self.identifier = target.identifier
        self.value = target.value
        self.traits = target.traits?.map(\.rawValue)
    }
}

private struct PublicResponseModel: FencePublicJSONResponse {
    let response: FenceResponse

    func encode(to encoder: Encoder) throws {
        switch response {
        case .ok(let message):
            try PublicOKResponse(message: message).encode(to: encoder)
        case .error(let message, let details):
            try PublicErrorResponse(message: message, details: details).encode(to: encoder)
        case .help(let commands):
            try PublicHelpResponse(commands: commands).encode(to: encoder)
        case .status(let connected, let deviceName):
            try PublicStatusResponse(connected: connected, device: deviceName).encode(to: encoder)
        case .devices(let devices):
            try PublicDevicesResponse(devices: devices).encode(to: encoder)
        case .interface(let interface, let detail):
            try PublicInterfaceResponse(interface: interface, detail: detail).encode(to: encoder)
        case .action(let result, let expectation):
            try PublicActionResponse(result: result, expectation: expectation).encode(to: encoder)
        case .screenshot(let path, let payload, let options):
            try PublicScreenshotResponse(
                path: path,
                payload: payload,
                includePNGData: false,
                includeInterface: options.includeInterface
            ).encode(to: encoder)
        case .screenshotData(let payload, let options):
            try PublicScreenshotResponse(
                path: nil,
                payload: payload,
                includePNGData: true,
                includeInterface: options.includeInterface
            ).encode(to: encoder)
        case .recording(let path, let payload):
            try PublicRecordingResponse(
                path: path,
                payload: payload,
                options: RecordingResponseOptions()
            ).encode(to: encoder)
        case .recordingExpanded(let path, let payload, let options):
            try PublicRecordingResponse(path: path, payload: payload, options: options).encode(to: encoder)
        case .recordingData(let payload):
            try PublicRecordingResponse(
                path: nil,
                payload: payload,
                options: RecordingResponseOptions(inlineData: true)
            ).encode(to: encoder)
        case .batch(let outcomes, let totalTimingMs, let accessibilityTrace):
            try PublicBatchResponse(
                outcomes: outcomes,
                totalTimingMs: totalTimingMs,
                accessibilityTrace: accessibilityTrace
            ).encode(to: encoder)
        case .sessionState(let payload):
            try PublicSessionStateResponse(payload: payload).encode(to: encoder)
        case .targets(let targets, let defaultTarget):
            try PublicTargetsResponse(targets: targets, defaultTarget: defaultTarget).encode(to: encoder)
        case .sessionLog(let snapshot):
            try PublicSessionLogResponse(snapshot: snapshot).encode(to: encoder)
        case .archiveResult(let path, let snapshot):
            try PublicSessionLogResponse(snapshot: snapshot, path: path).encode(to: encoder)
        case .heistStarted:
            try PublicHeistStartedResponse().encode(to: encoder)
        case .heistStopped(let path, let stepCount):
            try PublicHeistStoppedResponse(path: path, stepCount: stepCount).encode(to: encoder)
        case .heistPlayback(let completedSteps, let failedIndex, let totalTimingMs, let failure, _):
            try PublicPlaybackResponse(
                completedSteps: completedSteps,
                failedIndex: failedIndex,
                totalTimingMs: totalTimingMs,
                failure: failure
            ).encode(to: encoder)
        }
    }
}

extension FenceResponse {

    // MARK: - JSON Encoding

    public func jsonData(outputFormatting: JSONEncoder.OutputFormatting = [.sortedKeys]) throws -> Data {
        do {
            return try Self.encodePublicJSON(PublicResponseModel(response: self), outputFormatting: outputFormatting)
        } catch {
            return try Self.encodePublicJSON(Self.jsonEncodingFailureResponse(), outputFormatting: outputFormatting)
        }
    }

    public func jsonDict() -> [String: Any] {
        guard let data = try? jsonData(outputFormatting: []),
              let dict = try? Self.jsonObjectDictionary(from: data)
        else { return Self.jsonEncodingFailureDict() }
        return dict
    }

    static func expectationResultDict(_ result: ExpectationResult) -> [String: Any] {
        var dict: [String: Any] = ["met": result.met]
        if let actual = result.actual { dict["actual"] = actual }
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(result.expectation)
            let object = try JSONSerialization.jsonObject(with: data)
            dict["expected"] = object
        } catch {
            logger.warning("Failed to encode expectation result: \(error.localizedDescription)")
        }
        return dict
    }

    private static func encodePublicJSON<T: Encodable>(
        _ response: T,
        outputFormatting: JSONEncoder.OutputFormatting
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = outputFormatting
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(response)
    }

    private static func jsonObjectDictionary(from data: Data) throws -> [String: Any] {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EncodingError.invalidValue(
                String(data: data, encoding: .utf8) ?? "<non-utf8>",
                EncodingError.Context(
                    codingPath: [],
                    debugDescription: "Encoded public JSON response was not an object"
                )
            )
        }
        return dict
    }

    private static func jsonEncodingFailureDict() -> [String: Any] {
        [
            "status": "error",
            "message": "Failed to encode JSON response: response contained non-JSON values",
            "errorCode": "formatting.json_encoding_failed",
            "phase": FailurePhase.client.rawValue,
            "retryable": false,
            "hint": "Report this diagnostic with the command that produced it.",
        ]
    }

    private static func jsonEncodingFailureResponse() -> PublicErrorResponse {
        PublicErrorResponse(
            message: "Failed to encode JSON response: response contained non-JSON values",
            details: FailureDetails(
                errorCode: "formatting.json_encoding_failed",
                phase: .client,
                retryable: false,
                hint: "Report this diagnostic with the command that produced it."
            )
        )
    }
}
