import SwiftUI

struct GameDetailView: View {
    let game: Game
    let teams: [Team]
    let isOwner: Bool

    @StateObject private var rosterService = RosterService()
    @StateObject private var leagueService = LeagueService()
    @State private var homeRoster: [RosterSpot] = []
    @State private var awayRoster: [RosterSpot] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var homeTeam: Team? { teams.first { $0.id == game.homeTeamId } }
    private var awayTeam: Team? { teams.first { $0.id == game.awayTeamId } }

    var body: some View {
        List {
            if let errorMessage {
                ErrorBanner(message: errorMessage)
            }
            Section(awayTeam?.name ?? "Away") {
                ForEach(awayRoster) { spot in
                    rosterRow(spot)
                }
            }
            Section(homeTeam?.name ?? "Home") {
                ForEach(homeRoster) { spot in
                    rosterRow(spot)
                }
            }
            if isOwner && game.status == .scheduled {
                Section {
                    Button("Mark Game Final") {
                        Task { try? await leagueService.markGameFinal(gameId: game.id) }
                    }
                }
            }
        }
        .navigationTitle("\(awayTeam?.name ?? "") @ \(homeTeam?.name ?? "")")
        .overlay { if isLoading { LoadingView() } }
        .task { await loadRosters() }
    }

    @ViewBuilder
    private func rosterRow(_ spot: RosterSpot) -> some View {
        if isOwner {
            NavigationLink(spot.displayName) {
                PlayerStatEntryView(game: game, rosterSpot: spot)
            }
        } else {
            Text(spot.displayName)
        }
    }

    private func loadRosters() async {
        isLoading = true
        do {
            if let homeTeam {
                homeRoster = try await rosterService.fetchRoster(teamId: homeTeam.id)
            }
            if let awayTeam {
                awayRoster = try await rosterService.fetchRoster(teamId: awayTeam.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
