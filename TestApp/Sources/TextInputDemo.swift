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
                    .accessibilityIdentifier("buttonheist.text.nameField")

                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .accessibilityIdentifier("buttonheist.text.emailField")

                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .accessibilityIdentifier("buttonheist.text.passwordField")

                TextEditor(text: $bio)
                    .frame(height: 80)
                    .accessibilityIdentifier("buttonheist.text.bioEditor")
            }
        }
        .navigationTitle("Text Input")
    }
}

#Preview {
    TextInputDemo()
}
