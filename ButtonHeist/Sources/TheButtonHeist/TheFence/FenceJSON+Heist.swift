import Foundation

struct PublicHeistStartedResponse: FencePublicJSONResponse {
    let status = PublicStatus.ok
    let recording = true
}

struct PublicHeistStoppedResponse: FencePublicJSONResponse {
    let status = PublicStatus.ok
    let path: String
    let stepCount: Int
}
