import SwiftUI

struct RootView: View {
    @EnvironmentObject private var auth: AuthService

    var body: some View {
        Group {
            if auth.isLoading {
                LoadingView()
            } else {
                MainTabView(profile: auth.profile)
            }
        }
    }
}
