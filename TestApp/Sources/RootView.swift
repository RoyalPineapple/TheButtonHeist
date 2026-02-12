import SwiftUI

struct RootView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Controls Demo") {
                    ControlsDemoView()
                }
                NavigationLink("Touch Canvas") {
                    TouchCanvasView()
                }
            }
            .navigationTitle("ButtonHeist Test App")
        }
    }
}
