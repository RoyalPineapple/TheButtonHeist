import SwiftUI

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var submission: SubmissionState = .idle
    @State private var pendingTask: Task<Void, Never>?

    struct FieldErrors {
        var email: String?
        var password: String?
        var general: String?
    }

    enum SubmissionState {
        case idle
        case submitting
        case failed(FieldErrors)
    }

    private var isSubmitting: Bool {
        if case .submitting = submission { return true }
        return false
    }

    private var fieldErrors: FieldErrors? {
        if case .failed(let errors) = submission { return errors }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer()
                    .frame(height: 40)

                VStack(spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Color.accentColor)
                    Text("Sign In")
                        .font(.largeTitle.bold())
                }

                if let general = fieldErrors?.general {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(general)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.red.gradient, in: RoundedRectangle(cornerRadius: 10))
                }

                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Email", text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding()
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                            .disabled(isSubmitting)

                        if let emailError = fieldErrors?.email {
                            Text(emailError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .padding()
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                            .disabled(isSubmitting)

                        if let passwordError = fieldErrors?.password {
                            Text(passwordError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }

                Button {
                    signIn()
                } label: {
                    Group {
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Sign In")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSubmitting)

                VStack(spacing: 12) {
                    Button("Forgot Password?") {
                    }
                    .font(.subheadline)

                    Button("Create Account") {
                    }
                    .font(.subheadline)
                }

                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Sign In")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            pendingTask?.cancel()
            pendingTask = nil
        }
    }

    private func validate() -> FieldErrors? {
        var errors = FieldErrors()

        if email.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.email = "Email is required"
        } else if !email.contains("@") {
            errors.email = "Enter a valid email address"
        }

        if password.isEmpty {
            errors.password = "Password is required"
        }

        return (errors.email != nil || errors.password != nil) ? errors : nil
    }

    private func signIn() {
        if let errors = validate() {
            submission = .failed(errors)
            return
        }

        submission = .submitting

        pendingTask?.cancel()
        pendingTask = Task {
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
            submission = .failed(FieldErrors(general: "Invalid email or password"))
        }
    }
}

#Preview {
    NavigationStack {
        LoginView()
    }
    .environment(AppSettings())
}
