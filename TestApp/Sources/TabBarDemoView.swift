import SwiftUI

struct TabBarDemoView: View {
    var body: some View {
        TabView {
            CheckoutTabView()
                .tabItem {
                    Label("Checkout", systemImage: "cart")
                }
            TransactionsTabView()
                .tabItem {
                    Label("Transactions", systemImage: "list.bullet.rectangle")
                }
            AccountTabView()
                .tabItem {
                    Label("Account", systemImage: "person.circle")
                }
        }
        .navigationBarBackButtonHidden(true)
    }
}

private struct CheckoutTabView: View {
    var body: some View {
        List {
            Section {
                Text("Espresso")
                    .accessibilityLabel("Espresso")
                Text("Latte")
                    .accessibilityLabel("Latte")
                Text("Cappuccino")
                    .accessibilityLabel("Cappuccino")
                Text("Mocha")
                    .accessibilityLabel("Mocha")
                Text("Americano")
                    .accessibilityLabel("Americano")
                Text("Cold Brew")
                    .accessibilityLabel("Cold Brew")
                Text("Matcha")
                    .accessibilityLabel("Matcha")
                Text("Chai")
                    .accessibilityLabel("Chai")
            } header: {
                Text("Checkout")
            }

            Section {
                Text("Subtotal: $24.50")
                Text("Tax: $2.10")
                Text("Total: $26.60")
            } header: {
                Text("Summary")
            }

            Button("Pay Now") {}
                .accessibilityLabel("Pay Now")
        }
    }
}

private struct TransactionsTabView: View {
    var body: some View {
        List {
            Section {
                ForEach(1...12, id: \.self) { index in
                    HStack {
                        Text("Transaction #\(index)")
                        Spacer()
                        Text("$\(index * 5).00")
                    }
                    .accessibilityLabel("Transaction \(index), \(index * 5) dollars")
                }
            } header: {
                Text("Transactions")
            }
        }
    }
}

private struct AccountTabView: View {
    var body: some View {
        List {
            Section {
                Text("Name: Demo User")
                    .accessibilityLabel("Name, Demo User")
                Text("Email: demo@example.com")
                    .accessibilityLabel("Email, demo at example dot com")
                Text("Plan: Premium")
                    .accessibilityLabel("Plan, Premium")
            } header: {
                Text("Account")
            }

            Section {
                Text("Notifications")
                Text("Privacy")
                Text("Help & Support")
                Text("Sign Out")
            } header: {
                Text("Settings")
            }
        }
    }
}
