import SwiftUI

struct LogInView: View {
    @EnvironmentObject private var auth: AuthService

    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                SecureField("Password", text: $password)
                    .textContentType(.password)
            }
            if let errorMessage {
                ErrorBanner(message: errorMessage)
            }
            Section {
                Button {
                    Task { await logIn() }
                } label: {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Text("Log In").frame(maxWidth: .infinity)
                    }
                }
                .disabled(isSubmitting || email.isEmpty || password.isEmpty)
            }
        }
        .navigationTitle("Log In")
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
