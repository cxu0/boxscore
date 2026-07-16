import SwiftUI

struct ProfileView: View {
    let profile: Profile

    @StateObject private var statService = StatService()
    @State private var seasonStats: [PlayerSeasonStats] = []
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
            } else if seasonStats.isEmpty {
                EmptyStateView(
                    systemImage: "person.crop.circle.badge.questionmark",
                    title: "No Stats Yet",
                    message: "Join a team with an invite code to start tracking your career stats."
                )
            } else {
                List {
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
        .navigationTitle(profile.displayName)
        .onAppear { Task { await load() } }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        do {
            seasonStats = try await statService.fetchSeasonStats(playerId: profile.id)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
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
