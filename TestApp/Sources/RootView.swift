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
                .accessibilityIdentifier("buttonheist.root.messages")
                NavigationLink("Contacts") {
                    ContactsView()
                }
                .accessibilityIdentifier("buttonheist.root.contacts")
                NavigationLink("Dashboard") {
                    DashboardView()
                }
                .accessibilityIdentifier("buttonheist.root.dashboard")
                NavigationLink("Photos") {
                    PhotosView()
                }
                .accessibilityIdentifier("buttonheist.root.photos")
                NavigationLink("Login") {
                    LoginView()
                }
                .accessibilityIdentifier("buttonheist.root.login")
                NavigationLink("Cart") {
                    CartView()
                }
                .accessibilityIdentifier("buttonheist.root.cart")
                NavigationLink("Menu") {
                    MenuOrderView()
                }
                .accessibilityIdentifier("buttonheist.root.menu")
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
                    NavigationLink("Albums") {
                        AlbumFlowView()
                    }
                    .accessibilityIdentifier("buttonheist.root.albums")
                }
            }
            .navigationTitle("ButtonHeist Demo")
            .listRowInsets(settings.compactMode ? EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16) : nil)
        }
    }
}
