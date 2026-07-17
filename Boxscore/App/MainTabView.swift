import SwiftUI

/// The app's permanent shell — browsable without an account. Individual tabs
/// decide for themselves whether a guest needs a sign-in prompt.
struct MainTabView: View {
    let profile: Profile?

    var body: some View {
        TabView {
            HomeTabView(profile: profile)
                .tabItem { Label("Home", systemImage: "house") }

            LeaguesTabView(profile: profile)
                .tabItem { Label("Leagues", systemImage: "trophy") }

            CreateTabView(profile: profile)
                .tabItem { Label("Create", systemImage: "plus.circle") }

            MeTabView(profile: profile)
                .tabItem { Label("Me", systemImage: "person.crop.circle") }
        }
    }
}
