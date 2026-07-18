import SwiftUI

struct MeTabView: View {
    let profile: Profile?

    @EnvironmentObject private var auth: AuthService

    var body: some View {
        NavigationStack {
            Group {
                if let profile {
                    ProfileView(profile: profile)
                        .toolbar(.hidden, for: .navigationBar)
                        .overlay(alignment: .topTrailing) {
                            Button {
                                Task { try? await auth.signOut() }
                            } label: {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.8))
                                    .padding(10)
                                    .background(.white.opacity(0.12), in: Circle())
                            }
                            .padding(.trailing, 16)
                            .padding(.top, 8)
                        }
                } else {
                    SignInPromptView(message: "Sign in to see your career stats and teams.")
                        .toolbar(.hidden, for: .navigationBar)
                }
            }
        }
    }
}
