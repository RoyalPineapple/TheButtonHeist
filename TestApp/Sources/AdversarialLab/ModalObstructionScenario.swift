import SwiftUI

internal struct ModalObstructionScenarioView: View {
    @State private var showingReview = false
    @State private var lastAction = "None"

    var body: some View {
        List {
            Section {
                Button("Review order") { showingReview = true }
                Text("Status: \(lastAction)")
            }
            Section("Orders") {
                ForEach(1...100, id: \.self) { order in
                    Button("Archive order \(order)") {
                        lastAction = "Archived order \(order)"
                    }
                }
            }
        }
        .navigationTitle("Modal Obstruction")
        .sheet(isPresented: $showingReview) {
            NavigationStack {
                VStack(spacing: 16) {
                    Text("Order review")
                        .font(.title2)
                        .accessibilityAddTraits(.isHeader)
                    Text("Status: \(lastAction)")
                    Button("Confirm review") {
                        lastAction = "Review confirmed"
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Close") {
                        showingReview = false
                    }
                }
                .padding()
            }
        }
        .onAppear {
            showingReview = false
            lastAction = "None"
        }
    }
}
