import SwiftUI

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var emailError: String?
    @State private var passwordError: String?
    @State private var generalError: String?
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer()
                    .frame(height: 40)

                // App icon and title
                VStack(spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Color.accentColor)
                    Text("Sign In")
                        .font(.largeTitle.bold())
                }

                // General error banner
                if let generalError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(generalError)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.red.gradient, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityIdentifier("buttonheist.login.generalError")
                }

                // Form fields
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Email", text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding()
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                            .disabled(isLoading)
                            .accessibilityIdentifier("buttonheist.login.email")

                        if let emailError {
                            Text(emailError)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .accessibilityIdentifier("buttonheist.login.emailError")
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .padding()
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                            .disabled(isLoading)
                            .accessibilityIdentifier("buttonheist.login.password")

                        if let passwordError {
                            Text(passwordError)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .accessibilityIdentifier("buttonheist.login.passwordError")
                        }
                    }
                }

                // Sign In button
                Button {
                    signIn()
                } label: {
                    Group {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                                .accessibilityIdentifier("buttonheist.login.spinner")
                        } else {
                            Text("Sign In")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading)
                .accessibilityIdentifier("buttonheist.login.signIn")

                // Secondary actions
                VStack(spacing: 12) {
                    Button("Forgot Password?") {
                        NSLog("[Login] Forgot password tapped")
                    }
                    .font(.subheadline)
                    .accessibilityIdentifier("buttonheist.login.forgotPassword")

                    Button("Create Account") {
                        NSLog("[Login] Create account tapped")
                    }
                    .font(.subheadline)
                    .accessibilityIdentifier("buttonheist.login.createAccount")
                }

                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Sign In")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Validation

    private func validate() -> Bool {
        emailError = nil
        passwordError = nil
        generalError = nil
        var valid = true

        if email.trimmingCharacters(in: .whitespaces).isEmpty {
            emailError = "Email is required"
            valid = false
        } else if !email.contains("@") {
            emailError = "Enter a valid email address"
            valid = false
        }

        if password.isEmpty {
            passwordError = "Password is required"
            valid = false
        }

        return valid
    }

    // MARK: - Sign In

    private func signIn() {
        guard validate() else {
            NSLog("[Login] Validation failed")
            return
        }

        NSLog("[Login] Attempting sign in: %@", email)
        isLoading = true

        Task {
            try? await Task.sleep(for: .seconds(2))
            isLoading = false
            generalError = "Invalid email or password"
            NSLog("[Login] Sign in failed (demo — always fails)")
        }
    }
}

#Preview {
    NavigationStack {
        LoginView()
    }
    .environment(AppSettings())
}
