import SwiftUI
import PhotosUI
import UIKit

struct ProfileView: View {
    let profile: Profile

    @EnvironmentObject private var auth: AuthService
    @StateObject private var statService = StatService()
    @StateObject private var rosterService = RosterService()

    @State private var seasonStats: [PlayerSeasonStats] = []
    @State private var teams: [PlayerTeam] = []
    @State private var recentGames: [RecentGame] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    @State private var pickerItem: PhotosPickerItem?
    @State private var isUploading = false

    // Prefer the live auth profile so a freshly uploaded headshot appears at once.
    private var current: Profile { auth.profile ?? profile }

    var body: some View {
        Group {
            if isLoading {
                LoadingView()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ProfileHero(
                            profile: current,
                            subtitle: heroSubtitle,
                            pickerItem: $pickerItem,
                            isUploading: isUploading
                        )

                        VStack(alignment: .leading, spacing: 18) {
                            careerSection
                            if !seasonStats.isEmpty { seasonBreakdownSection }
                            if !teams.isEmpty { teamsSection }
                            if !recentGames.isEmpty { recentGamesSection }
                            if teams.isEmpty && seasonStats.isEmpty { emptyHint }
                            if let errorMessage { ErrorBanner(message: errorMessage) }
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 24)
                    }
                }
                .ignoresSafeArea(edges: .top)
            }
        }
        .onAppear { Task { await load() } }
        .refreshable { await load() }
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task { await uploadHeadshot(newItem) }
        }
    }

    // MARK: Derived

    private var heroSubtitle: String {
        guard let first = teams.first else { return "Free agent · no team yet" }
        if teams.count == 1 { return "\(first.teamName) · \(first.leagueName)" }
        return "\(first.teamName) · \(first.leagueName)  +\(teams.count - 1) more"
    }

    // MARK: Sections

    private var careerSection: some View {
        let t = seasonStats.careerTotals
        let gp = max(t.gamesPlayed, 1)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                BigStatTile(value: "\(t.pts)", label: "POINTS")
                BigStatTile(value: "\(t.reb)", label: "REBOUNDS")
            }
            HStack(spacing: 8) {
                BigStatTile(value: "\(t.ast)", label: "ASSISTS")
                BigStatTile(value: "\(t.gamesPlayed)", label: "GAMES")
            }
            // Per-game averages bar.
            HStack(spacing: 0) {
                perGame("PPG", t.pts, gp)
                perGame("RPG", t.reb, gp)
                perGame("APG", t.ast, gp)
                perGame("SPG", t.stl, gp)
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 14))

            if t.gamesPlayed == 0 {
                Text("These fill in the moment a box score goes final for a game you played.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func perGame(_ label: String, _ total: Int, _ gp: Int) -> some View {
        VStack(spacing: 3) {
            Text(String(format: "%.1f", Double(total) / Double(gp)))
                .font(.display(22))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
    }

    private var seasonBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderText("By season")
            VStack(spacing: 0) {
                HStack {
                    Text("SEASON").frame(maxWidth: .infinity, alignment: .leading)
                    Text("GP").frame(width: 32)
                    Text("PPG").frame(width: 44)
                    Text("RPG").frame(width: 44)
                    Text("APG").frame(width: 44)
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
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Brand.border, lineWidth: 1))
        }
    }

    private var teamsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderText("Teams & leagues")
            ForEach(teams) { team in
                HStack(spacing: 12) {
                    TeamCrest(name: team.teamName)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(team.teamName).font(.system(size: 15, weight: .bold))
                        Text("\(team.leagueName) · \(team.seasonName)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .brandCard(padding: 12)
            }
        }
    }

    private var recentGamesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderText("Recent games")
            ForEach(recentGames) { game in
                RecentGameRow(game: game)
            }
        }
    }

    private var emptyHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No teams yet")
                .font(.system(size: 16, weight: .bold))
            Text("Join a team with your league's code from the Leagues tab, and your career starts here.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .brandCard(padding: 18)
    }

    // MARK: Data

    private func load() async {
        isLoading = true
        do {
            async let stats = statService.fetchSeasonStats(playerId: profile.id)
            async let joined = rosterService.fetchPlayerTeams(playerId: profile.id)
            async let recent = statService.fetchRecentGames(playerId: profile.id)
            seasonStats = try await stats
            teams = try await joined
            recentGames = try await recent
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func uploadHeadshot(_ item: PhotosPickerItem) async {
        isUploading = true
        defer { isUploading = false; pickerItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let jpeg = ProfileImage.downscaledJPEG(from: data) else { return }
            try await auth.updateAvatar(imageData: jpeg)
        } catch {
            errorMessage = "Couldn't upload photo: \(error.localizedDescription)"
        }
    }
}

// MARK: - Hero

private struct ProfileHero: View {
    let profile: Profile
    let subtitle: String
    @Binding var pickerItem: PhotosPickerItem?
    let isUploading: Bool

    private var initials: String {
        let parts = profile.displayName.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "BX" : String(letters).uppercased()
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Color(white: 0.18), Color(white: 0.04)], startPoint: .top, endPoint: .bottom)

            Text(initials)
                .font(.display(150))
                .foregroundStyle(Brand.orange.opacity(0.16))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 8)
                .offset(y: -16)

            VStack(alignment: .leading, spacing: 12) {
                headshot
                VStack(alignment: .leading, spacing: 6) {
                    Text("PLAYER")
                        .font(.system(size: 9, weight: .black).width(.condensed))
                        .kerning(2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Brand.orange, in: RoundedRectangle(cornerRadius: 4))
                    Text(profile.displayName)
                        .font(.display(38))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
            .padding(.top, 60)
        }
        .frame(minHeight: 300)
        .clipped()
    }

    private var headshot: some View {
        PhotosPicker(selection: $pickerItem, matching: .images) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.1))
                    .frame(width: 76, height: 76)
                Circle()
                    .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                    .frame(width: 76, height: 76)

                if let urlString = profile.avatarUrl, let url = URL(string: urlString) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        ProgressView().tint(.white)
                    }
                    .frame(width: 76, height: 76)
                    .clipShape(Circle())
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.8))
                        Text("ADD")
                            .font(.system(size: 8, weight: .black).width(.condensed))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

                if isUploading {
                    Circle().fill(.black.opacity(0.4)).frame(width: 76, height: 76)
                    ProgressView().tint(.white)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Brand.orange)
                    .background(Circle().fill(.black))
            }
        }
    }
}

// MARK: - Rows

private struct SeasonStatRow: View {
    let season: PlayerSeasonStats
    private var gp: Int { max(season.gamesPlayed, 1) }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(season.seasonName).font(.system(size: 13, weight: .bold))
                Text(season.leagueName).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(season.gamesPlayed)").font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 32)
            Text(String(format: "%.1f", Double(season.pts) / Double(gp))).font(.display(16)).foregroundStyle(Brand.orange).frame(width: 44)
            Text(String(format: "%.1f", Double(season.reb) / Double(gp))).font(.system(size: 13)).frame(width: 44)
            Text(String(format: "%.1f", Double(season.ast) / Double(gp))).font(.system(size: 13)).frame(width: 44)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct RecentGameRow: View {
    let game: RecentGame

    private var resultLabel: String {
        switch game.result {
        case .win: return "W"
        case .loss: return "L"
        case .pending: return "·"
        }
    }
    private var resultColor: Color {
        switch game.result {
        case .win: return Brand.orange
        case .loss: return .gray
        case .pending: return .gray
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(resultColor.opacity(0.2)).frame(width: 34, height: 34)
                Text(resultLabel).font(.display(16)).foregroundStyle(resultColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(game.isHome ? "vs" : "@") \(game.opponentName)")
                    .font(.system(size: 15, weight: .bold))
                Text(game.scoreLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 4) {
                Text("\(game.pts)").font(.display(18)).foregroundStyle(.primary)
                Text("pts").font(.system(size: 11)).foregroundStyle(.secondary)
                Text("· \(game.reb)r · \(game.ast)a")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .brandCard(padding: 12)
    }
}

// MARK: - Image helper

enum ProfileImage {
    /// Downscales to a reasonable headshot size and re-encodes as JPEG to keep
    /// uploads small.
    static func downscaledJPEG(from data: Data, maxDimension: CGFloat = 800, quality: CGFloat = 0.8) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height))
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        return resized.jpegData(compressionQuality: quality)
    }
}
