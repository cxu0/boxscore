import SwiftUI

struct SignUpView: View {
    @EnvironmentObject private var auth: AuthService

    @State private var displayName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var role: UserRole = .player
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Account") {
                TextField("Name", text: $displayName)
                    .textContentType(.name)
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                SecureField("Password", text: $password)
                    .textContentType(.newPassword)
            }
            Section("I am a...") {
                Picker("Role", selection: $role) {
                    Text("Player").tag(UserRole.player)
                    Text("Commissioner").tag(UserRole.commissioner)
                }
                .pickerStyle(.segmented)
            }
            if let errorMessage {
                ErrorBanner(message: errorMessage)
            }
            Section {
                Button {
                    Task { await signUp() }
                } label: {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Text("Create Account").frame(maxWidth: .infinity)
                    }
                }
                .disabled(isSubmitting || !isValid)
            }
        }
        .navigationTitle("Sign Up")
    }

    private var isValid: Bool {
        !displayName.isEmpty && !email.isEmpty && password.count >= 6
    }

    private func signUp() async {
        isSubmitting = true
        errorMessage = nil
        do {
            try await auth.signUp(email: email, password: password, displayName: displayName, role: role)
        } catch {
            errorMessage = error.localizedDescription
        }
        isSubmitting = false
    }
}
