import Foundation

import TheScore

struct PublicHeistStartedResponse: FencePublicJSONResponse {
    let status = PublicStatus.ok
    let recording = true
}

struct PublicHeistStoppedResponse: FencePublicJSONResponse {
    let status = PublicStatus.ok
    let path: String
    let stepCount: Int
}

struct PublicHeistCatalogResponse: FencePublicJSONResponse {
    let status = PublicStatus.ok
    let heists: [HeistCatalogEntry]

    init(catalog: HeistDiscoveryCatalog) {
        heists = catalog.heists
    }
}

struct PublicHeistDescriptionResponse: FencePublicJSONResponse {
    let status = PublicStatus.ok
    let heist: HeistDescription
}
