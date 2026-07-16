import SwiftUI

struct ProfileView: View {
    let profile: Profile

    @StateObject private var statService = StatService()
    @StateObject private var rosterService = RosterService()
    @State private var seasonStats: [PlayerSeasonStats] = []
    @State private var teams: [PlayerTeam] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var byLeague: [(league: String, seasons: [PlayerSeasonStats])] {
        Dictionary(grouping: seasonStats, by: \.leagueName)
            .map { (league: $0.key, seasons: $0.value) }
            .sorted { $0.league < $1.league }
    }

    var body: some View {
        Group {
            if isLoading {
                LoadingView()
            } else if teams.isEmpty && seasonStats.isEmpty {
                EmptyStateView(
                    systemImage: "person.crop.circle.badge.questionmark",
                    title: "No Teams Yet",
                    message: "Tap + and enter an invite code from your commissioner to join a team."
                )
            } else {
                List {
                    if !teams.isEmpty {
                        Section("My Teams") {
                            ForEach(teams) { team in
                                TeamMembershipRow(team: team)
                            }
                        }
                    }
                    if seasonStats.isEmpty {
                        Section("Career") {
                            Text("No games played yet. Your stats will appear here once a box score is entered.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Section("Career") {
                            CareerTotalsCard(totals: seasonStats.careerTotals)
                        }
                        ForEach(byLeague, id: \.league) { group in
                            Section(group.league) {
                                ForEach(group.seasons) { season in
                                    SeasonStatRow(season: season)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(profile.displayName)
        .onAppear { Task { await load() } }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        do {
            async let stats = statService.fetchSeasonStats(playerId: profile.id)
            async let joined = rosterService.fetchPlayerTeams(playerId: profile.id)
            seasonStats = try await stats
            teams = try await joined
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct TeamMembershipRow: View {
    let team: PlayerTeam

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(team.teamName).font(.headline)
            Text("\(team.leagueName) · \(team.seasonName)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct CareerTotalsCard: View {
    let totals: PlayerSeasonStats.Totals

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(totals.gamesPlayed) games played")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 70))], spacing: 12) {
                StatTile(label: "PTS", value: totals.pts)
                StatTile(label: "REB", value: totals.reb)
                StatTile(label: "AST", value: totals.ast)
                StatTile(label: "STL", value: totals.stl)
                StatTile(label: "BLK", value: totals.blk)
                StatTile(label: "TO", value: totals.turnovers)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct StatTile: View {
    let label: String
    let value: Int

    var body: some View {
        VStack {
            Text("\(value)").font(.title2.bold())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SeasonStatRow: View {
    let season: PlayerSeasonStats

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(season.seasonName).font(.headline)
            Text("\(season.gamesPlayed) GP · \(season.pts) PTS · \(season.reb) REB · \(season.ast) AST")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
