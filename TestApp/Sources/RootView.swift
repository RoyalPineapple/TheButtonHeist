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
                NavigationLink("Touch Canvas") {
                    TouchCanvasView()
                }
                NavigationLink("Settings") {
                    SettingsView()
                }
            }
            .navigationTitle("ButtonHeist Test App")
            .listRowInsets(settings.compactMode ? EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16) : nil)
        }
    }
}
