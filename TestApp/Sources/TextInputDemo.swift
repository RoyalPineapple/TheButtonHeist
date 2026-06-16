import SwiftUI

struct TextInputDemo: View {
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var bio = ""

    var body: some View {
        Form {
            Section("Text Input") {
                TextField("Name", text: $name)
                    .accessibilityIdentifier("text-input-name")

                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .accessibilityIdentifier("text-input-email")

                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .accessibilityIdentifier("text-input-password")

                TextEditor(text: $bio)
                    .frame(height: 80)
                    .accessibilityIdentifier("text-input-bio")
            }
        }
        .navigationTitle("Text Input")
        .onAppear(perform: resetFields)
    }

    private func resetFields() {
        name = ""
        email = ""
        password = ""
        bio = ""
    }
}

#Preview {
    TextInputDemo()
}
