import SwiftUI

struct LogInView: View {
    @EnvironmentObject private var auth: AuthService

    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Welcome\nback.")
                    .font(.display(36))
                    .padding(.top, 12)

                VStack(spacing: 10) {
                    BrandTextField(placeholder: "Email address", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    BrandTextField(placeholder: "Password", text: $password, isSecure: true)
                        .textContentType(.password)
                }
                .padding(.top, 8)

                if let errorMessage {
                    ErrorBanner(message: errorMessage)
                }

                Button {
                    Task { await logIn() }
                } label: {
                    if isSubmitting {
                        ProgressView().tint(.white)
                    } else {
                        Text("Log In")
                    }
                }
                .buttonStyle(BrandPrimaryButtonStyle())
                .disabled(isSubmitting || email.isEmpty || password.isEmpty)
                .opacity(email.isEmpty || password.isEmpty ? 0.5 : 1)
            }
            .padding(.horizontal, 24)
        }
        .navigationTitle("Log In")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func logIn() async {
        isSubmitting = true
        errorMessage = nil
        do {
            try await auth.signIn(email: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
        isSubmitting = false
    }
}
