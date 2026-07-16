import SwiftUI

struct PlayerHomeView: View {
    let profile: Profile

    @EnvironmentObject private var auth: AuthService

    var body: some View {
        NavigationStack {
            ProfileView(profile: profile)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Sign Out") {
                            Task { try? await auth.signOut() }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            ClaimInviteView(onClaimed: {})
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
        }
    }
}
