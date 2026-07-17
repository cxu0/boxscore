import SwiftUI

struct LeaguesTabView: View {
    let profile: Profile?

    @StateObject private var leagueService = LeagueService()
    @State private var myLeagues: [MyLeague] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isShowingJoin = false

    var body: some View {
        NavigationStack {
            Group {
                if profile == nil {
                    SignInPromptView(message: "Sign in to see the leagues you run or play in.")
                } else if isLoading {
                    LoadingView()
                } else if myLeagues.isEmpty {
                    EmptyStateView(
                        systemImage: "trophy",
                        title: "No Leagues Yet",
                        message: "Create a league, or join one with a code from your organizer."
                    )
                } else {
                    List(myLeagues) { entry in
                        NavigationLink {
                            LeagueDetailView(league: entry.league)
                        } label: {
                            LeagueRow(entry: entry)
                        }
                    }
                }
            }
            .navigationTitle("Leagues")
            .toolbar {
                if profile != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            isShowingJoin = true
                        } label: {
                            Label("Join a League", systemImage: "person.badge.plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $isShowingJoin) {
                if let profile {
                    NavigationStack {
                        JoinLeagueView(profile: profile) { await loadLeagues() }
                    }
                }
            }
            .task { if profile != nil { await loadLeagues() } }
            .refreshable { await loadLeagues() }
        }
    }

    private func loadLeagues() async {
        guard let profile else { return }
        isLoading = true
        do {
            myLeagues = try await leagueService.fetchMyLeagues(userId: profile.id)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct LeagueRow: View {
    let entry: MyLeague

    var body: some View {
        HStack {
            Text(entry.league.name)
            Spacer()
            Text(entry.relationship == .owner ? "Organizer" : "Player")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
