import Foundation

import TheScore

struct PublicScreenshotResponse: FencePublicJSONResponse {
    let status = PublicStatus.ok
    let width: Double
    let height: Double
    let pngData: String?
    let interface: PublicInterface?
    let path: String?

    init(projection: ScreenshotProjection) {
        self.width = projection.width
        self.height = projection.height
        self.pngData = projection.pngData
        self.interface = projection.interface.map(PublicInterface.init(projection:))
        self.path = projection.path
    }
}
