import SwiftUI

/// League leaderboard: pick a stat on the left, see players ranked by their
/// per-game average on the right (name · avg · games played). Tapping a player
/// opens their profile.
struct LeagueStatsView: View {
    let teams: [Team]
    let games: [Game]

    @StateObject private var rosterService = RosterService()
    @StateObject private var statService = StatService()

    @State private var entries: [Entry] = []
    @State private var selected: String = StatCategory.all.first!.id
    @State private var isLoading = true

    struct Entry: Identifiable {
        let spot: RosterSpot
        let totals: BoxScoreStat.Totals
        let gamesPlayed: Int
        var id: UUID { spot.id }
        func average(_ value: (BoxScoreStat.Totals) -> Int) -> Double {
            gamesPlayed == 0 ? 0 : Double(value(totals)) / Double(gamesPlayed)
        }
    }

    private var category: StatCategory {
        StatCategory.all.first { $0.id == selected } ?? StatCategory.all[0]
    }

    private var ranked: [Entry] {
        entries
            .filter { $0.gamesPlayed > 0 }
            .sorted { $0.average(category.value) > $1.average(category.value) }
    }

    var body: some View {
        Group {
            if isLoading {
                LoadingView().padding(.top, 20)
            } else if ranked.isEmpty {
                Text("No stats yet. Once box scores are entered, league leaders show up here.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .brandCard()
            } else {
                HStack(alignment: .top, spacing: 12) {
                    categoryColumn
                    leaderboard
                }
            }
        }
        .task { await load() }
    }

    private var categoryColumn: some View {
        VStack(spacing: 6) {
            ForEach(StatCategory.all) { cat in
                Button {
                    selected = cat.id
                } label: {
                    Text(cat.label)
                        .font(.system(size: 13, weight: .black).width(.condensed))
                        .foregroundStyle(selected == cat.id ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            selected == cat.id ? Brand.orange : Brand.card,
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 74)
    }

    private var leaderboard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("#").frame(width: 20, alignment: .leading)
                Text("PLAYER").frame(maxWidth: .infinity, alignment: .leading)
                Text(category.perGameLabel).frame(width: 52, alignment: .trailing)
                Text("GP").frame(width: 34, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .black).width(.condensed))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            ForEach(Array(ranked.enumerated()), id: \.element.id) { index, entry in
                if index > 0 { Divider().padding(.leading, 12) }
                NavigationLink {
                    PlayerProfileLoader(rosterSpot: entry.spot)
                } label: {
                    row(rank: index + 1, entry: entry)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Brand.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Brand.border, lineWidth: 1))
    }

    private func row(rank: Int, entry: Entry) -> some View {
        HStack {
            Text("\(rank)")
                .font(.display(16))
                .foregroundStyle(rank == 1 ? Brand.orange : .secondary)
                .frame(width: 20, alignment: .leading)
            Text(entry.spot.displayName)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(String(format: "%.1f", entry.average(category.value)))
                .font(.display(17))
                .foregroundStyle(rank == 1 ? Brand.orange : .primary)
                .frame(width: 52, alignment: .trailing)
            Text("\(entry.gamesPlayed)")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
    }

    private func load() async {
        isLoading = true
        do {
            // Roster spots across every team in the season.
            var spots: [RosterSpot] = []
            for team in teams {
                spots += try await rosterService.fetchRoster(teamId: team.id)
            }
            // Box scores for every game in the season.
            let lines = try await statService.fetchBoxScores(gameIds: games.map(\.id))

            var totalsBySpot: [UUID: BoxScoreStat.Totals] = [:]
            var gamesBySpot: [UUID: Set<UUID>] = [:]
            for line in lines {
                totalsBySpot[line.rosterSpotId, default: BoxScoreStat.Totals()].add(line)
                gamesBySpot[line.rosterSpotId, default: []].insert(line.gameId)
            }

            entries = spots.map { spot in
                Entry(
                    spot: spot,
                    totals: totalsBySpot[spot.id] ?? BoxScoreStat.Totals(),
                    gamesPlayed: gamesBySpot[spot.id]?.count ?? 0
                )
            }
        } catch {
            entries = []
        }
        isLoading = false
    }
}

/// A stat you can lead the league in, with how to pull it from a totals bucket.
struct StatCategory: Identifiable {
    let id: String
    let label: String          // left column, e.g. "PTS"
    let perGameLabel: String   // leaderboard column, e.g. "PPG"
    let value: (BoxScoreStat.Totals) -> Int

    static let all: [StatCategory] = [
        StatCategory(id: "pts", label: "PTS", perGameLabel: "PPG", value: { $0.pts }),
        StatCategory(id: "reb", label: "REB", perGameLabel: "RPG", value: { $0.reb }),
        StatCategory(id: "ast", label: "AST", perGameLabel: "APG", value: { $0.ast }),
        StatCategory(id: "stl", label: "STL", perGameLabel: "SPG", value: { $0.stl }),
        StatCategory(id: "blk", label: "BLK", perGameLabel: "BPG", value: { $0.blk }),
        StatCategory(id: "to", label: "TO", perGameLabel: "TPG", value: { $0.turnovers }),
        StatCategory(id: "3pm", label: "3PM", perGameLabel: "3PG", value: { $0.tpm }),
        StatCategory(id: "pf", label: "PF", perGameLabel: "PFG", value: { $0.pf }),
    ]
}
