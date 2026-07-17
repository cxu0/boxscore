import SwiftUI

/// Browsable by anyone — no sign-in required. Phase 1 keeps this to a simple
/// placeholder; the real activity feed and AI-written game recaps come later
/// once there's actual game data flowing through the app.
struct HomeTabView: View {
    let profile: Profile?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "basketball.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                Text("Boxscore")
                    .font(.largeTitle.bold())
                Text("Your career basketball stats, everywhere you've played.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer()
                if profile == nil {
                    VStack(spacing: 12) {
                        Text("Sign in to follow your leagues here")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            NavigationLink("Sign Up") { SignUpView() }
                                .buttonStyle(.borderedProminent)
                            NavigationLink("Log In") { LogInView() }
                                .buttonStyle(.bordered)
                        }
                    }
                    .padding(.bottom, 24)
                } else {
                    Text("Your league activity will show up here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 24)
                }
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
