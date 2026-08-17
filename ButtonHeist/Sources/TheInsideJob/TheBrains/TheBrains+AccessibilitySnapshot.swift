#if canImport(UIKit) && canImport(SwiftUI)
#if DEBUG
import AccessibilitySnapshotCore
import AccessibilitySnapshotModel
import AccessibilitySnapshotPreviews
import SwiftUI
import UIKit

import TheScore

extension TheBrains {
    func renderAccessibilitySnapshotPayload(
        image: UIImage,
        bounds: CGRect,
        interface: Interface
    ) -> ScreenPayload? {
        guard #available(iOS 16.0, *) else { return nil }

        let view = PreParsedAccessibilitySnapshotView(
            snapshotImage: image,
            markers: Self.accessibilitySnapshotMarkers(in: interface),
            configuration: AccessibilitySnapshotConfiguration(
                viewRenderingMode: .drawHierarchyInRect,
                colorRenderingMode: .fullColor,
                activationPointDisplay: .always
            ),
            renderSize: bounds.size
        )

        let hosting = UIHostingController(rootView: view)
        if #available(iOS 16.4, *) {
            hosting.safeAreaRegions = []
        }
        let fittingSize = hosting.sizeThatFits(in: CGSize(
            width: bounds.width,
            height: UIView.layoutFittingExpandedSize.height
        ))
        guard fittingSize.width > 0, fittingSize.height > 0 else { return nil }

        let renderer = ImageRenderer(content: view.frame(width: fittingSize.width, height: fittingSize.height))
        renderer.scale = UIScreen.main.scale
        guard let pngData = renderer.uiImage?.pngData() else { return nil }

        return ScreenPayload.admit(
            pngData: pngData.base64EncodedString(),
            width: fittingSize.width,
            height: fittingSize.height,
            interface: interface
        )
    }

    nonisolated static func accessibilitySnapshotMarkers(in interface: Interface) -> [AccessibilityElement] {
        interface.tree.pathIndexedElements.compactMap { entry in
            entry.element.visibility == .onscreen ? entry.element : nil
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit) && canImport(SwiftUI)
