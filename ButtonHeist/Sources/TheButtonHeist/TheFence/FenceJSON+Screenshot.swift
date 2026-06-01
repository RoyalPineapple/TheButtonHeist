import Foundation

import TheScore

struct PublicScreenshotResponse: FencePublicJSONResponse {
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
        self.interface = includeInterface ? payload.interface.map { PublicInterface(interface: $0, detail: .full) } : nil
        self.path = path
    }
}
