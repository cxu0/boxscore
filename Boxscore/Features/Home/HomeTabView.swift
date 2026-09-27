import SwiftUI

/// Browsable by anyone — no sign-in required. Phase 1 keeps this to a branded
/// placeholder; the real activity feed and AI-written game recaps come later
/// once there's game data flowing through the app.
struct HomeTabView: View {
    let profile: Profile?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Wordmark()
                        Spacer()
                    }
                    .padding(.top, 8)

                    // Hero placeholder card — where the featured game recap will live.
                    VStack(alignment: .leading, spacing: 10) {
                        Text("GAME RECAPS")
                            .font(.system(size: 10, weight: .black).width(.condensed))
                            .kerning(1.5)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Brand.orange, in: Capsule())
                        Text("Your games,\ncovered like the pros.")
                            .font(.display(34))
                            .foregroundStyle(.white)
                            .lineSpacing(2)
                        Text("Play a game, get a story. AI-written recaps of every game land here the moment the box score goes final.")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        LinearGradient(
                            colors: [Color(white: 0.16), Color(white: 0.05)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        in: RoundedRectangle(cornerRadius: 18)
                    )

                    if profile == nil {
                        SectionHeaderText("Get in the game")
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
                    } else {
                        SectionHeaderText("In your leagues")
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No activity yet")
                                .font(.system(size: 15, weight: .bold))
                            Text("Standings updates, milestones, and recaps from your leagues will show up here.")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .brandCard()
                    }
                }
                .padding(.horizontal, 18)
            }
            .toolbar(.hidden, for: .navigationBar)
            .brandBackground()
        }
    }
}
