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

                    Section("Exploration") {
                        NavigationLink("Obscuring Harness") {
                            PresentationObscuringHarnessView()
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

                    Section("Representable") {
                        NavigationLink("Representable Stitching Probe") {
                            RepresentableStitchingProbeView()
                        }
                    }
                }
                .navigationTitle("Research")
            }
        }
    }
}
