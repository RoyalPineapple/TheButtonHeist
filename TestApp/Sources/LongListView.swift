import SwiftUI

struct LongListView: View {
    var body: some View {
        List(0..<100, id: \.self) { index in
            Text("Item \(index)")
                .accessibilityIdentifier(identifierFor(index))
        }
        .accessibilityIdentifier("buttonheist.longList.list")
        .navigationTitle("Long List")
    }

    private func identifierFor(_ index: Int) -> String {
        switch index {
        case 0:  return "buttonheist.longList.first"
        case 99: return "buttonheist.longList.last"
        default: return "buttonheist.longList.item-\(index)"
        }
    }
}
