#if canImport(UIKit)
#if DEBUG
import UIKit
import TheScore

extension TheInsideJob {

    // MARK: - Wait For Idle Handler

    func handleWaitForIdle(_ target: WaitForIdleTarget, requestId: String? = nil, respond: @escaping (Data) -> Void) async {
        let timeoutSeconds = min(target.timeout ?? 5.0, 60.0)
        let maxFrames = max(1, Int(timeoutSeconds * Double(TheTripwire.settleFrameRate)))
        let settled = await tripwire.waitForAllClear(maxFrames: maxFrames)

        guard let hierarchyTree = bagman.refreshAccessibilityData() else {
            sendMessage(.error("Could not access root view"), requestId: requestId, respond: respond)
            return
        }

        let snapshot = bagman.snapshotElements()
        let tree = hierarchyTree.map { bagman.convertHierarchyNode($0) }
        let payload = Interface(timestamp: Date(), elements: snapshot.elements, tree: tree)

        let result = ActionResult(
            success: true,
            method: .waitForIdle,
            message: settled ? "UI idle" : "Timed out after \(timeoutSeconds)s, UI may still be animating",
            interfaceDelta: InterfaceDelta(
                kind: .screenChanged,
                elementCount: snapshot.elements.count,
                newInterface: payload
            ),
            animating: settled ? nil : true
        )
        sendMessage(.actionResult(result), requestId: requestId, respond: respond)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
