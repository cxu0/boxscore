import SwiftUI

struct RootView: View {
    @EnvironmentObject private var auth: AuthService

    var body: some View {
        Group {
            if auth.isLoading {
                LoadingView()
            } else if let profile = auth.profile {
                switch profile.role {
                case .commissioner:
                    CommissionerHomeView(profile: profile)
                case .player:
                    PlayerHomeView(profile: profile)
                }
            } else {
                WelcomeView()
            }
        }
    }
}
