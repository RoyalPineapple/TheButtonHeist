import SwiftUI

struct RootView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Controls Demo") {
                    ControlsDemoView()
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
                NavigationLink("Touch Canvas") {
                    TouchCanvasView()
                }
                NavigationLink("Settings") {
                    SettingsView()
                }

                Section("Scroll Tests") {
                    NavigationLink("Long List") {
                        LongListView()
                    }
                    .accessibilityIdentifier("buttonheist.root.longList")
                    NavigationLink("Grid Gallery") {
                        GridGalleryView()
                    }
                    .accessibilityIdentifier("buttonheist.root.gridGallery")
                    NavigationLink("Corner Scroll") {
                        CornerScrollView()
                    }
                    .accessibilityIdentifier("buttonheist.root.cornerScroll")
                    NavigationLink("Nested Scrolls") {
                        NestedScrollView()
                    }
                    .accessibilityIdentifier("buttonheist.root.nestedScrolls")
                }
            }
            .navigationTitle("ButtonHeist Test App")
            .listRowInsets(settings.compactMode ? EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16) : nil)
        }
    }
}
