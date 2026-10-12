import SwiftUI

struct SignUpView: View {
    @EnvironmentObject private var auth: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Create your\nplayer account.")
                    .font(.display(36))
                    .padding(.top, 12)

                VStack(spacing: 10) {
                    BrandTextField(placeholder: "Name", text: $displayName)
                        .textContentType(.name)
                    BrandTextField(placeholder: "Email address", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    BrandTextField(placeholder: "Password", text: $password, isSecure: true)
                        .textContentType(.newPassword)
                }
                .padding(.top, 8)

                Text("In a league? Use the email you registered with — you'll be added to your team automatically.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                if let errorMessage {
                    ErrorBanner(message: errorMessage)
                }

                Button {
                    Task { await signUp() }
                } label: {
                    if isSubmitting {
                        ProgressView().tint(.white)
                    } else {
                        Text("Create Account")
                    }
                }
                .buttonStyle(BrandPrimaryButtonStyle())
                .disabled(isSubmitting || !isValid)
                .opacity(isValid ? 1 : 0.5)

                Text("One account for everything — run leagues, play in them, and build your career stats.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
        }
        .navigationTitle("Sign Up")
        .navigationBarTitleDisplayMode(.inline)
        .brandBackground()
    }

    private var isValid: Bool {
        !displayName.isEmpty && !email.isEmpty && password.count >= 6
    }

    private func signUp() async {
        isSubmitting = true
        errorMessage = nil
        do {
            try await auth.signUp(email: email, password: password, displayName: displayName)
            // Pop this screen so the app drops straight into the signed-in state
            // instead of leaving the completed form on screen.
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSubmitting = false
    }
}

/// Rounded filled text field matching the prototype's input style.
struct BrandTextField: View {
    let placeholder: String
    @Binding var text: String
    var isSecure = false

    var body: some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .font(.system(size: 15))
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Brand.card, in: RoundedRectangle(cornerRadius: 14))
    }
}
