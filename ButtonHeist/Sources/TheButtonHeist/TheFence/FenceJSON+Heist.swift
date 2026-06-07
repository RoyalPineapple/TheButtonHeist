import Foundation

import TheScore

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
