import SwiftUI

struct RootView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Accessibility Demo") {
                    ContentView()
                }
                NavigationLink("Touch Canvas") {
                    TouchCanvasView()
                }
            }
            .navigationTitle("ButtonHeist Test App")
        }
    }
}
