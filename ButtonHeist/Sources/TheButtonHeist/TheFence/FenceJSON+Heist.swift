import Foundation
import ThePlans

import TheScore

struct PublicHeistCatalogResponse: FencePublicJSONResponse {
    let status = PublicStatus.ok
    private let heists: [PublicHeistCatalogEntry]

    init(catalog: HeistDiscoveryCatalog) {
        heists = catalog.heists.map(PublicHeistCatalogEntry.init)
    }
}

struct PublicHeistDescriptionResponse: FencePublicJSONResponse {
    let status = PublicStatus.ok
    private let heist: PublicHeistDescription

    init(heist: HeistDescription) {
        self.heist = PublicHeistDescription(heist)
    }
}

private struct PublicHeistCatalogEntry: Encodable {
    let name: String
    let role: HeistCatalogRole
    let parameterKind: HeistParameterKind
    let requiresArgument: Bool
    let summary: String?
    let tags: [String]
    let parameterName: HeistReferenceName?
    let nestedRunHeists: [String]?
    let actionCommands: [String]?
    let waitCount: Int?
    let expectationCount: Int?
    let semanticSurfaces: [String]?
    let validationStatus: HeistValidationStatus?

    init(_ entry: HeistCatalogEntry) {
        name = entry.name
        role = entry.role
        parameterKind = entry.parameterKind
        requiresArgument = entry.requiresArgument
        summary = entry.summary
        tags = entry.tags.map(\.heistDiscoveryDisplayValue)
        parameterName = entry.parameterName
        nestedRunHeists = entry.nestedRunHeists?.map(\.heistDiscoveryDisplayValue)
        actionCommands = entry.actionCommands?.map(\.heistDiscoveryDisplayValue)
        waitCount = entry.waitCount
        expectationCount = entry.expectationCount
        semanticSurfaces = entry.semanticSurfaces?.map(\.heistDiscoveryDisplayValue)
        validationStatus = entry.validationStatus
    }
}

private struct PublicHeistDescription: Encodable {
    let name: String
    let role: HeistCatalogRole
    let parameterKind: HeistParameterKind
    let parameterName: HeistReferenceName?
    let requiresArgument: Bool
    let summary: String?
    let validationStatus: HeistValidationStatus
    let semanticSurface: PublicHeistSemanticSurface

    init(_ description: HeistDescription) {
        name = description.name
        role = description.role
        parameterKind = description.parameterKind
        parameterName = description.parameterName
        requiresArgument = description.requiresArgument
        summary = description.summary
        validationStatus = description.validationStatus
        semanticSurface = PublicHeistSemanticSurface(description.semanticSurface)
    }
}

private struct PublicHeistSemanticSurface: Encodable {
    let actionCommands: [String]
    let targetPredicates: [String]
    let waits: [String]
    let expectations: [String]
    let nestedRunHeists: [String]
    let expectedEffects: [String]
    let semanticSurfaces: [String]

    init(_ surface: HeistSemanticSurface) {
        actionCommands = surface.actionCommands.map(\.heistDiscoveryDisplayValue)
        targetPredicates = surface.targetPredicates.map(\.heistDiscoveryDisplayValue)
        waits = surface.waits.map(\.heistDiscoveryDisplayValue)
        expectations = surface.expectations.map(\.heistDiscoveryDisplayValue)
        nestedRunHeists = surface.nestedRunHeists.map(\.heistDiscoveryDisplayValue)
        expectedEffects = surface.expectedEffects.map(\.heistDiscoveryDisplayValue)
        semanticSurfaces = surface.semanticSurfaces.map(\.heistDiscoveryDisplayValue)
    }
}
