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
                .onChange(of: settings.colorScheme) { _, newValue in
                    NSLog("[Settings] Color scheme: %@", newValue.rawValue)
                }

                Picker("Accent Color", selection: $settings.accentColor) {
                    ForEach(AppSettings.AppAccentColor.allCases, id: \.self) { color in
                        Text(color.rawValue).tag(color)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: settings.accentColor) { _, newValue in
                    NSLog("[Settings] Accent color: %@", newValue.rawValue)
                }

                Picker("Text Size", selection: $settings.textSize) {
                    ForEach(AppSettings.AppTextSize.allCases, id: \.self) { size in
                        Text(size.rawValue).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: settings.textSize) { _, newValue in
                    NSLog("[Settings] Text size: %@", newValue.rawValue)
                }
            }

            Section("Profile") {
                TextField("Username", text: $settings.username)
                    .onChange(of: settings.username) { _, newValue in
                        NSLog("[Settings] Username: \"%@\"", newValue)
                    }
            }

            Section("Behavior") {
                Toggle("Show Completed Todos", isOn: $settings.showCompletedTodos)
                    .onChange(of: settings.showCompletedTodos) { _, newValue in
                        NSLog("[Settings] Show completed todos: %@", newValue ? "on" : "off")
                    }

                Toggle("Compact Mode", isOn: $settings.compactMode)
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
