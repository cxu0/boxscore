import SwiftUI

struct WelcomeView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "basketball.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.orange)
                    Text("Boxscore")
                        .font(.largeTitle.bold())
                    Text("Your career basketball stats, everywhere you've played.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                Spacer()
                VStack(spacing: 12) {
                    NavigationLink("Sign Up") { SignUpView() }
                        .buttonStyle(.borderedProminent)
                    NavigationLink("Log In") { LogInView() }
                        .buttonStyle(.bordered)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
        }
    }
}
