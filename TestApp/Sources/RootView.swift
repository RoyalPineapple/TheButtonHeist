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
                NavigationLink("Settings") {
                    SettingsView()
                }

                Section("Scroll Tests") {
                    NavigationLink("Long List") {
                        LongListView()
                    }
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
            }
            .navigationTitle("ButtonHeist Demo")
            .listRowInsets(settings.compactMode ? EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16) : nil)
        }
    }
}
