import SwiftUI

/// Shown in place of a tab's real content when a guest tries to do something
/// that needs a known identity. Must be placed inside a NavigationStack —
/// it pushes Sign Up / Log In rather than presenting a separate root.
struct SignInPromptView: View {
    let message: String

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            VStack(spacing: 12) {
                NavigationLink("Sign Up") { SignUpView() }
                    .buttonStyle(.borderedProminent)
                NavigationLink("Log In") { LogInView() }
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: 240)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
