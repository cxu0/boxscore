import SwiftUI

struct CommissionerHomeView: View {
    let profile: Profile

    @EnvironmentObject private var auth: AuthService
    @StateObject private var leagueService = LeagueService()

    @State private var leagues: [League] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isShowingNewLeague = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    LoadingView()
                } else if leagues.isEmpty {
                    EmptyStateView(
                        systemImage: "trophy",
                        title: "No Leagues Yet",
                        message: "Create a league to start scheduling seasons and games."
                    )
                } else {
                    List(leagues) { league in
                        NavigationLink(league.name) {
                            LeagueDetailView(league: league)
                        }
                    }
                }
            }
            .navigationTitle("My Leagues")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingNewLeague = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Sign Out") {
                        Task { try? await auth.signOut() }
                    }
                }
            }
            .sheet(isPresented: $isShowingNewLeague) {
                NewLeagueSheet { name in
                    await createLeague(name: name)
                }
            }
            .task { await loadLeagues() }
            .refreshable { await loadLeagues() }
        }
    }

    private func loadLeagues() async {
        isLoading = true
        do {
            leagues = try await leagueService.fetchLeagues(ownerId: profile.id)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func createLeague(name: String) async {
        do {
            let league = try await leagueService.createLeague(name: name, ownerId: profile.id)
            leagues.insert(league, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct NewLeagueSheet: View {
    let onCreate: (String) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("League Name", text: $name)
            }
            .navigationTitle("New League")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        isSubmitting = true
                        Task {
                            await onCreate(name)
                            dismiss()
                        }
                    }
                    .disabled(name.isEmpty || isSubmitting)
                }
            }
        }
    }
}
