import SwiftUI

struct ProfileView: View {
    let profile: Profile

    @StateObject private var statService = StatService()
    @StateObject private var rosterService = RosterService()
    @State private var seasonStats: [PlayerSeasonStats] = []
    @State private var teams: [PlayerTeam] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                LoadingView()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ProfileHero(name: profile.displayName, subtitle: heroSubtitle)

                        VStack(alignment: .leading, spacing: 16) {
                            if teams.isEmpty && seasonStats.isEmpty {
                                emptyState
                            } else {
                                careerSection
                                if !seasonStats.isEmpty {
                                    seasonBreakdownSection
                                }
                                if !teams.isEmpty {
                                    teamsSection
                                }
                            }
                            if let errorMessage {
                                ErrorBanner(message: errorMessage)
                            }
                        }
                        .padding(.horizontal, 18)
                    }
                }
                .ignoresSafeArea(edges: .top)
            }
        }
        .onAppear { Task { await load() } }
        .refreshable { await load() }
    }

    // MARK: Sections

    private var heroSubtitle: String {
        guard let first = teams.first else { return "Free agent — join a league to get started" }
        if teams.count == 1 {
            return "\(first.teamName) · \(first.leagueName)"
        }
        return "\(first.teamName) · \(first.leagueName)  +\(teams.count - 1) more"
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No teams yet")
                .font(.system(size: 16, weight: .bold))
            Text("Join a team with your league's code from the Leagues tab, and your career starts here.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .brandCard(padding: 18)
    }

    private var careerSection: some View {
        let t = seasonStats.careerTotals
        let gp = max(t.gamesPlayed, 1)
        let fgPct = t.fga > 0 ? Int(round(Double(t.fgm) / Double(t.fga) * 100)) : 0
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeaderText("Career stats")
            if t.gamesPlayed == 0 {
                Text("No games played yet. Your stats will appear the moment a box score goes final.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .brandCard()
            } else {
                HStack(spacing: 8) {
                    BigStatTile(value: String(format: "%.1f", Double(t.pts) / Double(gp)), label: "PPG")
                    BigStatTile(value: String(format: "%.1f", Double(t.reb) / Double(gp)), label: "RPG")
                    BigStatTile(value: String(format: "%.1f", Double(t.ast) / Double(gp)), label: "APG")
                    BigStatTile(value: "\(fgPct)", label: "FG%")
                }
                Text("\(t.gamesPlayed) career games · \(t.pts) points")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var seasonBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderText("Season breakdown")
            VStack(spacing: 0) {
                HStack {
                    Text("SEASON").frame(maxWidth: .infinity, alignment: .leading)
                    Text("G").frame(width: 32)
                    Text("PPG").frame(width: 40)
                    Text("RPG").frame(width: 40)
                    Text("APG").frame(width: 40)
                }
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                ForEach(Array(seasonStats.enumerated()), id: \.element.id) { index, season in
                    if index > 0 { Divider().padding(.leading, 14) }
                    SeasonStatRow(season: season)
                }
            }
            .background(Brand.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Brand.border, lineWidth: 1)
            )
        }
    }

    private var teamsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderText("Teams & leagues")
            ForEach(teams) { team in
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Brand.orange.opacity(0.18))
                            .frame(width: 36, height: 36)
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Brand.orange)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(team.teamName)
                            .font(.system(size: 15, weight: .bold))
                        Text("\(team.leagueName) · \(team.seasonName)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .brandCard(padding: 12)
            }
        }
    }

    private func load() async {
        isLoading = true
        do {
            async let stats = statService.fetchSeasonStats(playerId: profile.id)
            async let joined = rosterService.fetchPlayerTeams(playerId: profile.id)
            seasonStats = try await stats
            teams = try await joined
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

/// Pro-athlete-card hero: dark gradient, giant faded watermark initials,
/// name in condensed black type.
private struct ProfileHero: View {
    let name: String
    let subtitle: String

    private var initials: String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "BX" : String(letters).uppercased()
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color(white: 0.18), Color(white: 0.04)],
                startPoint: .top, endPoint: .bottom
            )

            Text(initials)
                .font(.display(150))
                .foregroundStyle(.white.opacity(0.07))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 8)
                .offset(y: -20)

            VStack(alignment: .leading, spacing: 6) {
                Text("PLAYER")
                    .font(.system(size: 9, weight: .black).width(.condensed))
                    .kerning(2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Brand.orange, in: RoundedRectangle(cornerRadius: 4))
                Text(name)
                    .font(.display(38))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
        .frame(height: 240)
        .clipped()
    }
}

private struct SeasonStatRow: View {
    let season: PlayerSeasonStats

    private var gp: Int { max(season.gamesPlayed, 1) }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(season.seasonName)
                    .font(.system(size: 13, weight: .bold))
                Text(season.leagueName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(season.gamesPlayed)")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 32)
            Text(String(format: "%.1f", Double(season.pts) / Double(gp)))
                .font(.display(16))
                .foregroundStyle(Brand.orange)
                .frame(width: 40)
            Text(String(format: "%.1f", Double(season.reb) / Double(gp)))
                .font(.system(size: 13))
                .frame(width: 40)
            Text(String(format: "%.1f", Double(season.ast) / Double(gp)))
                .font(.system(size: 13))
                .frame(width: 40)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
