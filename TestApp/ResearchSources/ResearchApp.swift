import SwiftUI
import TheInsideJob

@main
struct ResearchApp: App {
    @State private var insideJob = TheInsideJob()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                List {
                    Section("Scroll SPI") {
                        NavigationLink("Scroll SPI Harness") {
                            ScrollSPIHarnessView()
                        }
                    }

                    Section("Traits") {
                        NavigationLink("Trait Probe") {
                            TraitProbeView()
                        }
                        NavigationLink("Trait Validation") {
                            TraitValidationView()
                        }
                    }
                }
                .navigationTitle("Research")
            }
        }
    }
}
