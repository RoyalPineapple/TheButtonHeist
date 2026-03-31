import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Appearance") {
                Picker("Color Scheme", selection: $settings.colorScheme) {
                    ForEach(AppSettings.AppColorScheme.allCases, id: \.self) { scheme in
                        Text(scheme.rawValue).tag(scheme)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("buttonheist.settings.colorScheme")
                .onChange(of: settings.colorScheme) { _, newValue in
                    NSLog("[Settings] Color scheme: %@", newValue.rawValue)
                }

                Picker("Accent Color", selection: $settings.accentColor) {
                    ForEach(AppSettings.AppAccentColor.allCases, id: \.self) { color in
                        Text(color.rawValue).tag(color)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("buttonheist.settings.accentColor")
                .onChange(of: settings.accentColor) { _, newValue in
                    NSLog("[Settings] Accent color: %@", newValue.rawValue)
                }

                Picker("Text Size", selection: $settings.textSize) {
                    ForEach(AppSettings.AppTextSize.allCases, id: \.self) { size in
                        Text(size.rawValue).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("buttonheist.settings.textSize")
                .onChange(of: settings.textSize) { _, newValue in
                    NSLog("[Settings] Text size: %@", newValue.rawValue)
                }
            }

            Section("Profile") {
                TextField("Username", text: $settings.username)
                    .accessibilityIdentifier("buttonheist.settings.username")
                    .onChange(of: settings.username) { _, newValue in
                        NSLog("[Settings] Username: \"%@\"", newValue)
                    }
            }

            Section("Behavior") {
                Toggle("Show Completed Todos", isOn: $settings.showCompletedTodos)
                    .accessibilityIdentifier("buttonheist.settings.showCompleted")
                    .onChange(of: settings.showCompletedTodos) { _, newValue in
                        NSLog("[Settings] Show completed todos: %@", newValue ? "on" : "off")
                    }

                Toggle("Compact Mode", isOn: $settings.compactMode)
                    .accessibilityIdentifier("buttonheist.settings.compactMode")
                    .onChange(of: settings.compactMode) { _, newValue in
                        NSLog("[Settings] Compact mode: %@", newValue ? "on" : "off")
                    }
            }

            Section("Current Values") {
                HStack {
                    Text("Color Scheme")
                    Spacer()
                    Text(settings.colorScheme.rawValue)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("buttonheist.settings.currentColorScheme")

                HStack {
                    Text("Accent Color")
                    Spacer()
                    Text(settings.accentColor.rawValue)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("buttonheist.settings.currentAccentColor")

                HStack {
                    Text("Text Size")
                    Spacer()
                    Text(settings.textSize.rawValue)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("buttonheist.settings.currentTextSize")

                HStack {
                    Text("Username")
                    Spacer()
                    Text(settings.username.isEmpty ? "(not set)" : settings.username)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("buttonheist.settings.currentUsername")
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
