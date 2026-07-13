import SwiftUI

struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @State private var adversarialRoute: AdversarialRoute?

    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Controls Demo") {
                    ControlsDemoView()
                }
                NavigationLink("Adversarial Lab") {
                    AdversarialLabView()
                }
                NavigationLink("Todo List") {
                    TodoListView()
                }
                NavigationLink("Notes") {
                    NotesView()
                }
                NavigationLink("Calculator") {
                    CalculatorView()
                }
                NavigationLink("Words") {
                    DictionaryView()
                }
                NavigationLink("Touch Canvas") {
                    TouchCanvasView()
                }
                NavigationLink("Playlist") {
                    PlaylistView()
                }
                NavigationLink("Messages") {
                    MessagesView()
                }
                NavigationLink("Contacts") {
                    ContactsView()
                }
                NavigationLink("Dashboard") {
                    DashboardView()
                }
                NavigationLink("Photos") {
                    PhotosView()
                }
                NavigationLink("Login") {
                    LoginView()
                }
                NavigationLink("Cart") {
                    CartView()
                }
                NavigationLink("Menu") {
                    MenuOrderView()
                }
                NavigationLink("Long List") {
                    LongListView()
                }
                NavigationLink("Settings") {
                    SettingsView()
                }
                NavigationLink("Custom Content") {
                    CustomContentDemo()
                }
                NavigationLink("Custom Rotors") {
                    RotorsDemo()
                }
                NavigationLink("Tab Bar") {
                    TabBarDemoView()
                }

                Section("Auto-Settle Fixtures") {
                    NavigationLink("Transient Flow") {
                        TransientFlowDemo()
                    }
                    NavigationLink("Analog Clock") {
                        AnalogClockDemo()
                    }
                }

                Section("Modals") {
                    NavigationLink("Modal Window") {
                        ModalWindowDemo()
                    }
                    NavigationLink("Modal Permutations") {
                        ModalPermutationsDemo()
                    }
                    NavigationLink("Alerts & Sheets") {
                        AlertsSheetDemo()
                    }
                }

                Section("Scroll Tests") {
                    NavigationLink("Grid Gallery") {
                        GridGalleryView()
                    }
                    NavigationLink("Corner Scroll") {
                        CornerScrollView()
                    }
                    NavigationLink("Albums") {
                        AlbumFlowView()
                    }
                }

                Section("UIKit") {
                    NavigationLink("UIKit Form") {
                        UIKitFormDemoView()
                    }
                    NavigationLink("UIKit Table") {
                        UIKitTableDemoView()
                    }
                    NavigationLink("UIKit Collection") {
                        UIKitCollectionDemoView()
                    }
                }

                Section("Research") {
                    NavigationLink("Scroll SPI Harness") {
                        ScrollSPIHarnessView()
                    }
                    NavigationLink("Obscuring Harness") {
                        PresentationObscuringHarnessView()
                    }
                    NavigationLink("Trait Probe") {
                        TraitProbeView()
                    }
                    NavigationLink("Trait Validation") {
                        TraitValidationView()
                    }
                }
            }
            .navigationTitle("ButtonHeist Demo")
            .listRowInsets(settings.compactMode ? EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16) : nil)
            .navigationDestination(item: $adversarialRoute) { route in
                AdversarialScenarioView(scenario: route.scenario)
                    .id(route.id)
            }
        }
        .onOpenURL(perform: openDemoRoute)
    }

    private func openDemoRoute(_ url: URL) {
        guard url.scheme == "buttonheist-demo",
              url.host == "adversarial",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let title = components.queryItems?.first(where: { $0.name == "scenario" })?.value,
              let scenario = AdversarialScenario.allCases.first(where: { $0.title == title })
        else { return }
        adversarialRoute = AdversarialRoute(scenario: scenario)
    }
}

private struct AdversarialRoute: Identifiable, Hashable {
    let id = UUID()
    let scenario: AdversarialScenario
}
