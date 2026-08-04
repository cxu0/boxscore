import SwiftUI

/// The app's permanent shell — browsable without an account. Individual tabs
/// decide for themselves whether a guest needs a sign-in prompt.
struct MainTabView: View {
    let profile: Profile?

    @EnvironmentObject private var router: AppRouter
    @State private var selection = 0  // Home

    var body: some View {
        TabView(selection: $selection) {
            HomeTabView(profile: profile)
                .tabItem { Label("Home", systemImage: "house") }
                .tag(0)

            LeaguesTabView(profile: profile)
                .tabItem { Label("Leagues", systemImage: "trophy") }
                .tag(1)

            CreateTabView(profile: profile)
                .tabItem { Label("Create", systemImage: "plus.circle") }
                .tag(2)

            MeTabView(profile: profile)
                .tabItem { Label("Me", systemImage: "person.crop.circle") }
                .tag(3)
        }
        .tint(Brand.orange)
        // A deep link resolves inside the Leagues tab — switch to it.
        .onChange(of: router.pending) { _, pending in
            if pending != nil { selection = 1 }
        }
    }
}
