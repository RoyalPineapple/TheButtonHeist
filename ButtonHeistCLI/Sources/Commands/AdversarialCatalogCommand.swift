import ArgumentParser
import Foundation
@_spi(AdversarialLab) import ThePlans

struct AdversarialCatalogCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "adversarial_catalog",
        shouldDisplay: false
    )

    func run() throws {
        let manifests = try AdversarialScenarioCatalog.Scenario.allCases.map { try $0.manifest() }
        FileHandle.standardOutput.write(try JSONEncoder().encode(manifests))
    }
}
