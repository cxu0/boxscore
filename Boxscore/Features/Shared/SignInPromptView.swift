import SwiftUI

/// Shown in place of a tab's real content when a guest tries to do something
/// that needs a known identity. Must be placed inside a NavigationStack —
/// it pushes Sign Up / Log In rather than presenting a separate root.
struct SignInPromptView: View {
    let message: String

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Wordmark(size: 40)
            Text("Your league. Your stats. Your story.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(.top, 6)

            Text("Join the game.")
                .font(.display(40))
                .padding(.top, 36)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.top, 6)

            VStack(spacing: 10) {
                NavigationLink { SignUpView() } label: {
                    Text("Sign Up")
                }
                .buttonStyle(BrandPrimaryButtonStyle())
                NavigationLink { LogInView() } label: {
                    Text("Log In")
                }
                .buttonStyle(BrandSecondaryButtonStyle())
            }
            .padding(.horizontal, 40)
            .padding(.top, 28)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
