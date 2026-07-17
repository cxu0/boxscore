import SwiftUI

struct MeTabView: View {
    let profile: Profile?

    @EnvironmentObject private var auth: AuthService

    var body: some View {
        NavigationStack {
            Group {
                if let profile {
                    ProfileView(profile: profile)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Sign Out") {
                                    Task { try? await auth.signOut() }
                                }
                            }
                        }
                } else {
                    SignInPromptView(message: "Sign in to see your career stats and teams.")
                        .navigationTitle("Me")
                }
            }
        }
    }
}
