import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Appearance") {
                Picker("Color Scheme", selection: $settings.colorScheme) {
                    ForEach(AppColorScheme.allCases, id: \.self) { scheme in
                        Text(scheme.rawValue).tag(scheme)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Accent Color", selection: $settings.accentColor) {
                    ForEach(AppAccentColor.allCases, id: \.self) { color in
                        Text(color.rawValue).tag(color)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Text Size", selection: $settings.textSize) {
                    ForEach(AppTextSize.allCases, id: \.self) { size in
                        Text(size.rawValue).tag(size)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Profile") {
                TextField("Username", text: $settings.username)
            }

            Section("Behavior") {
                Toggle("Show Completed Todos", isOn: $settings.showCompletedTodos)

                Toggle("Compact Mode", isOn: $settings.compactMode)
            }

            Section("Current Values") {
                HStack {
                    Text("Color Scheme")
                    Spacer()
                    Text(settings.colorScheme.rawValue)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)

                HStack {
                    Text("Accent Color")
                    Spacer()
                    Text(settings.accentColor.rawValue)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)

                HStack {
                    Text("Text Size")
                    Spacer()
                    Text(settings.textSize.rawValue)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)

                HStack {
                    Text("Username")
                    Spacer()
                    Text(settings.username.isEmpty ? "(not set)" : settings.username)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environment(AppSettings())
}
