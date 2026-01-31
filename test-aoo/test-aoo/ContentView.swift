//
//  ContentView.swift
//  test-aoo
//
//  Created by aodawa on 31/01/2026.
//

import SwiftUI
import AccessibilityBridgeServer

struct ContentView: View {
    var autoStartDemo: Bool = false

    @State private var selectedTab = 0
    @State private var isAutoDemoRunning = false
    @State private var demoStep = 0
    @State private var demoTimer: Timer?

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeTab(isAutoDemoRunning: $isAutoDemoRunning, startDemo: startAutoDemo, stopDemo: stopAutoDemo)
                .tabItem {
                    Label("Home", systemImage: "house")
                }
                .tag(0)

            FormsTab()
                .tabItem {
                    Label("Forms", systemImage: "list.bullet.rectangle")
                }
                .tag(1)

            ListTab()
                .tabItem {
                    Label("List", systemImage: "list.dash")
                }
                .tag(2)

            SettingsTab()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(3)
        }
        .onChange(of: selectedTab) { _, _ in
            AccessibilityBridgeServer.shared.notifyChange()
        }
        .onAppear {
            if autoStartDemo {
                // Delay slightly to let the UI settle
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    startAutoDemo()
                }
            }
        }
    }

    private func startAutoDemo() {
        guard !isAutoDemoRunning else { return }
        isAutoDemoRunning = true
        demoStep = 0

        demoTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in
                runDemoStep()
            }
        }
    }

    private func stopAutoDemo() {
        isAutoDemoRunning = false
        demoTimer?.invalidate()
        demoTimer = nil
    }

    private func runDemoStep() {
        let steps = [0, 1, 2, 3, 0] // Cycle through tabs
        selectedTab = steps[demoStep % steps.count]
        demoStep += 1

        if demoStep >= 10 {
            stopAutoDemo()
        }
    }
}

// MARK: - Home Tab

struct HomeTab: View {
    @Binding var isAutoDemoRunning: Bool
    var startDemo: () -> Void
    var stopDemo: () -> Void

    @State private var counter = 0
    @State private var message = "Welcome to the accessibility demo!"

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "accessibility")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)
                    .accessibilityLabel("Accessibility icon")

                Text(message)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel(message)

                Text("Counter: \(counter)")
                    .font(.title2)
                    .accessibilityLabel("Counter value is \(counter)")

                HStack(spacing: 16) {
                    Button("Decrement") {
                        counter -= 1
                        message = "Counter decreased to \(counter)"
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Decrement counter")

                    Button("Increment") {
                        counter += 1
                        message = "Counter increased to \(counter)"
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Increment counter")
                }

                Divider()

                Button(isAutoDemoRunning ? "Stop Auto Demo" : "Start Auto Demo") {
                    if isAutoDemoRunning {
                        stopDemo()
                    } else {
                        startDemo()
                    }
                }
                .buttonStyle(.bordered)
                .tint(isAutoDemoRunning ? .red : .green)
                .accessibilityLabel(isAutoDemoRunning ? "Stop automatic demonstration" : "Start automatic demonstration")
                .accessibilityHint("Cycles through all tabs automatically")

                if isAutoDemoRunning {
                    ProgressView()
                        .accessibilityLabel("Demo in progress")
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Home")
        }
        .onChange(of: counter) { _, _ in
            AccessibilityBridgeServer.shared.notifyChange()
        }
        .onChange(of: message) { _, _ in
            AccessibilityBridgeServer.shared.notifyChange()
        }
    }
}

// MARK: - Forms Tab

struct FormsTab: View {
    @State private var name = ""
    @State private var email = ""
    @State private var isSubscribed = false
    @State private var volume: Double = 50
    @State private var selectedColor = 0
    let colors = ["Red", "Green", "Blue", "Yellow"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Personal Info") {
                    TextField("Name", text: $name)
                        .accessibilityLabel("Name input field")
                        .accessibilityValue(name.isEmpty ? "Empty" : name)

                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .accessibilityLabel("Email input field")
                        .accessibilityValue(email.isEmpty ? "Empty" : email)
                }

                Section("Preferences") {
                    Toggle("Subscribe to newsletter", isOn: $isSubscribed)
                        .accessibilityLabel("Newsletter subscription toggle")
                        .accessibilityValue(isSubscribed ? "Subscribed" : "Not subscribed")

                    VStack(alignment: .leading) {
                        Text("Volume: \(Int(volume))%")
                            .accessibilityHidden(true)
                        Slider(value: $volume, in: 0...100, step: 1)
                            .accessibilityLabel("Volume slider")
                            .accessibilityValue("\(Int(volume)) percent")
                    }

                    Picker("Favorite Color", selection: $selectedColor) {
                        ForEach(0..<colors.count, id: \.self) { index in
                            Text(colors[index]).tag(index)
                        }
                    }
                    .accessibilityLabel("Favorite color picker")
                    .accessibilityValue(colors[selectedColor])
                }

                Section("Actions") {
                    Button("Submit Form") {
                        // Simulate form submission
                        name = ""
                        email = ""
                    }
                    .accessibilityLabel("Submit form button")
                    .accessibilityHint("Clears all form fields")

                    Button("Fill Sample Data") {
                        name = "John Doe"
                        email = "john@example.com"
                        isSubscribed = true
                        volume = 75
                        selectedColor = 2
                    }
                    .accessibilityLabel("Fill sample data button")
                    .accessibilityHint("Populates form with example values")
                }
            }
            .navigationTitle("Forms")
        }
        .onChange(of: name) { _, _ in AccessibilityBridgeServer.shared.notifyChange() }
        .onChange(of: email) { _, _ in AccessibilityBridgeServer.shared.notifyChange() }
        .onChange(of: isSubscribed) { _, _ in AccessibilityBridgeServer.shared.notifyChange() }
        .onChange(of: volume) { _, _ in AccessibilityBridgeServer.shared.notifyChange() }
        .onChange(of: selectedColor) { _, _ in AccessibilityBridgeServer.shared.notifyChange() }
    }
}

// MARK: - List Tab

struct ListTab: View {
    @State private var items = ["Apple", "Banana", "Cherry", "Date", "Elderberry"]
    @State private var selectedItem: String?

    var body: some View {
        NavigationStack {
            List {
                ForEach(items, id: \.self) { item in
                    HStack {
                        Image(systemName: "leaf.fill")
                            .foregroundStyle(.green)
                            .accessibilityHidden(true)

                        Text(item)

                        Spacer()

                        if selectedItem == item {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedItem = item
                    }
                    .accessibilityLabel(item)
                    .accessibilityValue(selectedItem == item ? "Selected" : "Not selected")
                    .accessibilityAddTraits(selectedItem == item ? .isSelected : [])
                }
                .onDelete { indexSet in
                    items.remove(atOffsets: indexSet)
                }
                .onMove { from, to in
                    items.move(fromOffsets: from, toOffset: to)
                }
            }
            .navigationTitle("Fruits")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                        .accessibilityLabel("Edit list")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        let newFruits = ["Fig", "Grape", "Honeydew", "Kiwi", "Lemon"]
                        if let newFruit = newFruits.first(where: { !items.contains($0) }) {
                            items.append(newFruit)
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add fruit")
                    .accessibilityHint("Adds a new fruit to the list")
                }
            }
        }
        .onChange(of: items) { _, _ in AccessibilityBridgeServer.shared.notifyChange() }
        .onChange(of: selectedItem) { _, _ in AccessibilityBridgeServer.shared.notifyChange() }
    }
}

// MARK: - Settings Tab

struct SettingsTab: View {
    @State private var isDarkMode = false
    @State private var notificationsEnabled = true
    @State private var fontSize: Double = 16
    @State private var language = "English"
    let languages = ["English", "Spanish", "French", "German", "Japanese"]

    var body: some View {
        NavigationStack {
            List {
                Section("Appearance") {
                    Toggle("Dark Mode", isOn: $isDarkMode)
                        .accessibilityLabel("Dark mode toggle")
                        .accessibilityValue(isDarkMode ? "Enabled" : "Disabled")

                    VStack(alignment: .leading) {
                        Text("Font Size: \(Int(fontSize))pt")
                            .accessibilityHidden(true)
                        Slider(value: $fontSize, in: 12...24, step: 1)
                            .accessibilityLabel("Font size slider")
                            .accessibilityValue("\(Int(fontSize)) points")
                    }
                }

                Section("Notifications") {
                    Toggle("Enable Notifications", isOn: $notificationsEnabled)
                        .accessibilityLabel("Notifications toggle")
                        .accessibilityValue(notificationsEnabled ? "Enabled" : "Disabled")
                }

                Section("Language") {
                    Picker("Language", selection: $language) {
                        ForEach(languages, id: \.self) { lang in
                            Text(lang).tag(lang)
                        }
                    }
                    .accessibilityLabel("Language picker")
                    .accessibilityValue(language)
                }

                Section("About") {
                    LabeledContent("Version", value: "1.0.0")
                        .accessibilityLabel("App version")
                        .accessibilityValue("1.0.0")

                    LabeledContent("Build", value: "2026.01.31")
                        .accessibilityLabel("Build date")
                        .accessibilityValue("January 31, 2026")

                    NavigationLink {
                        AboutDetailView()
                    } label: {
                        Text("More Info")
                    }
                    .accessibilityLabel("More information")
                    .accessibilityHint("Opens detailed app information")
                }

                Section("Debug") {
                    Button("Trigger Manual Update") {
                        AccessibilityBridgeServer.shared.notifyChange()
                    }
                    .accessibilityLabel("Trigger manual accessibility update")
                    .accessibilityHint("Forces an immediate hierarchy refresh")
                }
            }
            .navigationTitle("Settings")
        }
        .onChange(of: isDarkMode) { _, _ in AccessibilityBridgeServer.shared.notifyChange() }
        .onChange(of: notificationsEnabled) { _, _ in AccessibilityBridgeServer.shared.notifyChange() }
        .onChange(of: fontSize) { _, _ in AccessibilityBridgeServer.shared.notifyChange() }
        .onChange(of: language) { _, _ in AccessibilityBridgeServer.shared.notifyChange() }
    }
}

// MARK: - About Detail View

struct AboutDetailView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue)
                .accessibilityLabel("Information icon")

            Text("Accessibility Test App")
                .font(.title)
                .accessibilityAddTraits(.isHeader)

            Text("This app demonstrates SwiftUI accessibility features and the accessibility bridge for remote inspection.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .accessibilityLabel("App description: This app demonstrates SwiftUI accessibility features and the accessibility bridge for remote inspection.")

            Spacer()
        }
        .padding()
        .navigationTitle("About")
        .onAppear {
            AccessibilityBridgeServer.shared.notifyChange()
        }
    }
}

#Preview {
    ContentView()
}
