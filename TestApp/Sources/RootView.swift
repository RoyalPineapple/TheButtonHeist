import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject private var settings: AppSettings
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
            .navigationDestination(isPresented: Binding(
                get: { adversarialRoute != nil },
                set: { isPresented in
                    if !isPresented {
                        adversarialRoute = nil
                    }
                }
            )) {
                if let route = adversarialRoute {
                    AdversarialScenarioView(scenario: route.scenario)
                        .id(route.id)
                        .task {
                            await Task.yield()
                            AdversarialLabRoute.markReady(route.id)
                        }
                }
            }
        }
        .onOpenURL(perform: openDemoRoute)
    }

    private func openDemoRoute(_ url: URL) {
        guard url.scheme == "buttonheist-demo",
              url.host == "adversarial",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let rawScenario = components.queryItems?.first(where: { $0.name == "scenario" })?.value,
              let scenario = AdversarialScenario(rawValue: rawScenario),
              let rawRouteID = components.queryItems?.first(where: { $0.name == "route_id" })?.value,
              let routeID = UUID(uuidString: rawRouteID)
        else { return }
        AdversarialLabRoute.begin()
        adversarialRoute = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(10))
            adversarialRoute = AdversarialRoute(id: routeID, scenario: scenario)
        }
    }
}

private struct AdversarialRoute: Identifiable, Hashable {
    let id: UUID
    let scenario: AdversarialScenario
}

@MainActor
internal final class AdversarialLabRoute {
    private static var readyRouteID: UUID?

    private init() {}

    internal static func open(_ scenario: AdversarialScenario) async throws {
        let routeID = UUID()
        var components = URLComponents()
        components.scheme = "buttonheist-demo"
        components.host = "adversarial"
        components.queryItems = [
            URLQueryItem(name: "scenario", value: scenario.rawValue),
            URLQueryItem(name: "route_id", value: routeID.uuidString),
        ]
        guard let url = components.url else {
            throw AdversarialLabRouteError.invalidURL
        }
        guard await UIApplication.shared.open(url) else {
            throw AdversarialLabRouteError.rejectedByApplication
        }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while readyRouteID != routeID {
            guard clock.now < deadline else {
                throw AdversarialLabRouteError.timedOut(scenario)
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    fileprivate static func begin() {
        readyRouteID = nil
    }

    fileprivate static func markReady(_ routeID: UUID) {
        readyRouteID = routeID
    }
}

internal enum AdversarialLabRouteError: Error {
    case invalidURL
    case rejectedByApplication
    case timedOut(AdversarialScenario)
}
