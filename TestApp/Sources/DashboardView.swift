import SwiftUI

struct DashboardView: View {
    enum Tab: String, CaseIterable {
        case activity = "Activity"
        case stats = "Stats"
        case alerts = "Alerts"
    }

    @State private var selectedTab: Tab = .activity
    @State private var alerts: [AlertItem] = AlertItem.defaults

    var body: some View {
        VStack(spacing: 0) {
            Picker("Tab", selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            switch selectedTab {
            case .activity:
                activityTab
            case .stats:
                statsTab
            case .alerts:
                alertsTab
            }
        }
        .navigationTitle("Dashboard")
    }

    private var activityTab: some View {
        List(Array(ActivityItem.defaults.enumerated()), id: \.element.id) { _, item in
            HStack(spacing: 12) {
                Image(systemName: item.icon)
                    .font(.title3)
                    .foregroundStyle(item.color)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.description)
                        .font(.headline)
                    Text(item.timeAgo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var statsTab: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(StatCard.defaults) { stat in
                    VStack(spacing: 8) {
                        Text(stat.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(stat.value)
                            .font(.system(.title, design: .rounded, weight: .bold))
                        HStack(spacing: 4) {
                            Image(systemName: stat.trendUp ? "arrow.up.right" : "arrow.down.right")
                            Text(stat.trendText)
                                .font(.caption2)
                        }
                        .foregroundStyle(stat.trendUp ? .green : .red)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(stat.label), \(stat.value)")
                    .accessibilityCustomContent(Text("Trend"), Text(stat.trendText))
                }
            }
            .padding()
        }
    }

    private var alertsTab: some View {
        Group {
            if alerts.isEmpty {
                ContentUnavailableView(
                    "All Clear",
                    systemImage: "checkmark.shield.fill",
                    description: Text("No active alerts")
                )
            } else {
                List {
                    ForEach(alerts) { alert in
                        HStack(spacing: 12) {
                            Image(systemName: alert.severity.icon)
                                .foregroundStyle(alert.severity.color)
                                .font(.title3)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(alert.severity.rawValue.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(alert.severity.color)
                                    .fontWeight(.semibold)
                                Text(alert.message)
                                    .font(.subheadline)
                            }
                            Spacer()
                            Button {
                                dismissAlert(alert)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Dismiss")
                        }
                    }
                }
            }
        }
    }

    private func dismissAlert(_ alert: AlertItem) {
        withAnimation {
            alerts.removeAll { $0.id == alert.id }
        }
    }
}

// MARK: - Model

private struct ActivityItem: Identifiable {
    let id = UUID()
    let description: String
    let icon: String
    let color: Color
    let timeAgo: String

    static let defaults: [ActivityItem] = [
        ActivityItem(description: "Merged PR #412", icon: "arrow.triangle.merge", color: .purple, timeAgo: "2m ago"),
        ActivityItem(description: "Deployed v2.1 to staging", icon: "shippingbox.fill", color: .blue, timeAgo: "18m ago"),
        ActivityItem(description: "Reviewed design spec", icon: "doc.text.magnifyingglass", color: .orange, timeAgo: "45m ago"),
        ActivityItem(description: "Fixed flaky test suite", icon: "checkmark.circle.fill", color: .green, timeAgo: "1h ago"),
        ActivityItem(description: "Updated API documentation", icon: "book.closed.fill", color: .teal, timeAgo: "2h ago"),
        ActivityItem(description: "Closed issue #389", icon: "xmark.circle.fill", color: .red, timeAgo: "3h ago"),
        ActivityItem(description: "Rebased feature branch", icon: "arrow.triangle.branch", color: .indigo, timeAgo: "5h ago"),
        ActivityItem(description: "Added monitoring dashboard", icon: "chart.line.uptrend.xyaxis", color: .cyan, timeAgo: "Yesterday"),
    ]
}

private struct StatCard: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let trendUp: Bool
    let trendText: String

    static let defaults: [StatCard] = [
        StatCard(label: "Open PRs", value: "12", trendUp: true, trendText: "+3 this week"),
        StatCard(label: "Build Time", value: "4:32", trendUp: false, trendText: "+12s avg"),
        StatCard(label: "Test Coverage", value: "94%", trendUp: true, trendText: "+2.1%"),
        StatCard(label: "Deploys Today", value: "7", trendUp: true, trendText: "+2 vs yesterday"),
        StatCard(label: "Open Issues", value: "23", trendUp: false, trendText: "+5 this week"),
        StatCard(label: "Uptime", value: "99.9%", trendUp: true, trendText: "30-day avg"),
    ]
}

private struct AlertItem: Identifiable {
    let id = UUID()
    let severity: Severity
    let message: String

    enum Severity: String {
        case critical
        case warning
        case info

        var icon: String {
            switch self {
            case .critical: return "exclamationmark.triangle.fill"
            case .warning: return "exclamationmark.circle.fill"
            case .info: return "info.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .critical: return .red
            case .warning: return .orange
            case .info: return .blue
            }
        }
    }

    static let defaults: [AlertItem] = [
        AlertItem(severity: .critical, message: "Database replica lag exceeds 30s threshold"),
        AlertItem(severity: .warning, message: "API response times elevated in us-east-1"),
        AlertItem(severity: .warning, message: "Certificate expiry in 14 days for api.example.com"),
        AlertItem(severity: .info, message: "Scheduled maintenance window tonight at 2 AM UTC"),
        AlertItem(severity: .info, message: "New team member onboarding: access provisioned"),
    ]
}

#Preview {
    NavigationStack {
        DashboardView()
    }
    .environment(AppSettings())
}
