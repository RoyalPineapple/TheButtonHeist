import Foundation

import TheScore

struct PublicScreenshotResponse: Encodable {
    let status = PublicResponseStatus.ok
    let width: Double
    let height: Double
    let pngData: String?
    let interface: InterfaceProjection?
    let path: String?

    init(projection: ScreenshotProjection) {
        self.width = projection.width
        self.height = projection.height
        self.interface = projection.interface
        switch projection.storage {
        case .artifact(let path):
            self.pngData = nil
            self.path = path
        case .inlinePNG(let pngData):
            self.pngData = pngData
            self.path = nil
        }
    }
}
