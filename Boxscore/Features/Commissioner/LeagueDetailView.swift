import SwiftUI

struct LeagueDetailView: View {
    let league: League

    @EnvironmentObject private var auth: AuthService
    @StateObject private var leagueService = LeagueService()
    @StateObject private var rosterService = RosterService()

    @State private var season: Season?
    @State private var teams: [Team] = []
    @State private var games: [Game] = []
    @State private var myTeam: Team?
    @State private var rosterCount = 0
    @State private var tab: Tab = .standings
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isShowingNewTeam = false
    @State private var isShowingNewGame = false

    enum Tab: String, CaseIterable { case standings, schedule, rosters }

    private var isOwner: Bool { auth.profile?.id == league.ownerId }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                LeagueHero(league: league, season: season, teamCount: teams.count, gameCount: games.count, playerCount: rosterCount)

                VStack(spacing: 16) {
                    if let myTeam {
                        YourTeamCard(
                            team: myTeam,
                            record: LeagueService.standings(teams: teams, games: games).first { $0.team.id == myTeam.id }?.record,
                            nextGame: nextGame(for: myTeam.id),
                            teams: teams
                        )
                    }

                    if let next = nextGame(for: nil), myTeam == nil {
                        NextGameCard(game: next, teams: teams)
                    }

                    if isOwner {
                        JoinCodeCard(league: league)
                    }

                    Picker("View", selection: $tab) {
                        Text("Standings").tag(Tab.standings)
                        Text("Schedule").tag(Tab.schedule)
                        Text("Rosters").tag(Tab.rosters)
                    }
                    .pickerStyle(.segmented)

                    if isLoading {
                        LoadingView().padding(.top, 20)
                    } else {
                        switch tab {
                        case .standings: standingsView
                        case .schedule: scheduleView
                        case .rosters: rostersView
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(isPresented: $isShowingNewTeam) {
            NewTeamSheet { name in await createTeam(name: name) }
        }
        .sheet(isPresented: $isShowingNewGame) {
            NewGameSheet(teams: teams) { home, away, date in
                await createGame(homeTeamId: home, awayTeamId: away, date: date)
            }
        }
        .task { await loadAll() }
        .refreshable { await loadAll() }
    }

    // MARK: Standings

    private var standingsView: some View {
        let standings = LeagueService.standings(teams: teams, games: games)
        let played = games.contains { $0.status == .final && $0.hasResult }
        return VStack(spacing: 0) {
            HStack {
                Text("#").frame(width: 24, alignment: .leading)
                Text("TEAM").frame(maxWidth: .infinity, alignment: .leading)
                Text("W–L").frame(width: 52, alignment: .trailing)
                Text("STRK").frame(width: 48, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .black).width(.condensed))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if standings.isEmpty {
                Text("No teams yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            } else {
                ForEach(Array(standings.enumerated()), id: \.element.id) { index, standing in
                    if index > 0 { Divider().padding(.leading, 14) }
                    StandingRow(rank: index + 1, standing: standing, showRecord: played)
                }
            }
        }
        .background(Brand.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Brand.border, lineWidth: 1))
    }

    // MARK: Schedule

    private var scheduleView: some View {
        VStack(spacing: 10) {
            if isOwner {
                Button {
                    isShowingNewGame = true
                } label: {
                    Label("Schedule a Game", systemImage: "calendar.badge.plus")
                }
                .buttonStyle(BrandSecondaryButtonStyle())
                .disabled(teams.count < 2)
            }
            if games.isEmpty {
                Text("No games scheduled yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .brandCard()
            } else {
                ForEach(games) { game in
                    NavigationLink {
                        GameDetailView(game: game, teams: teams, isOwner: isOwner, seasonGames: games) { await loadAll() }
                    } label: {
                        GameRow(game: game, teams: teams)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Rosters

    private var rostersView: some View {
        VStack(spacing: 10) {
            if isOwner {
                Button {
                    isShowingNewTeam = true
                } label: {
                    Label("Add a Team", systemImage: "plus")
                }
                .buttonStyle(BrandSecondaryButtonStyle())
            }
            if teams.isEmpty {
                Text("No teams yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .brandCard()
            } else {
                ForEach(teams) { team in
                    NavigationLink {
                        TeamDetailView(team: team, isOwner: isOwner)
                    } label: {
                        HStack(spacing: 12) {
                            TeamCrest(name: team.name)
                            Text(team.name)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.tertiary)
                        }
                        .brandCard(padding: 12)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Soonest not-yet-final game, optionally filtered to a team the viewer
    /// cares about. Falls back to the most recent game if none are upcoming.
    private func nextGame(for teamId: UUID?) -> Game? {
        let pool = games.filter { g in
            teamId == nil || g.homeTeamId == teamId || g.awayTeamId == teamId
        }
        let upcoming = pool.filter { $0.status == .scheduled }.sorted { $0.scheduledAt < $1.scheduledAt }
        return upcoming.first
    }

    // MARK: Data

    private func loadAll() async {
        isLoading = true
        do {
            let seasons = try await leagueService.fetchSeasons(leagueId: league.id)
            guard let current = seasons.first else {
                season = nil; teams = []; games = []; rosterCount = 0; myTeam = nil
                isLoading = false
                return
            }
            season = current
            async let t = leagueService.fetchTeams(seasonId: current.id)
            async let g = leagueService.fetchGames(seasonId: current.id)
            teams = try await t
            games = try await g
            rosterCount = try await countPlayers(teams: teams)
            await resolveMyTeam()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // A viewer is a "player" in this league if they hold a roster spot on one of
    // its teams — independent of whether they also own the league.
    private func resolveMyTeam() async {
        guard let userId = auth.profile?.id else { myTeam = nil; return }
        do {
            let spots = try await rosterService.fetchLinkedRosterSpots(playerId: userId)
            let teamIds = Set(spots.map(\.teamId))
            myTeam = teams.first { teamIds.contains($0.id) }
        } catch {
            myTeam = nil
        }
    }

    private func countPlayers(teams: [Team]) async throws -> Int {
        var total = 0
        for team in teams {
            total += try await leagueService.fetchRosterCount(teamId: team.id)
        }
        return total
    }

    private func createTeam(name: String) async {
        guard let season else { return }
        do {
            let team = try await leagueService.createTeam(name: name, seasonId: season.id)
            teams.append(team)
            teams.sort { $0.name < $1.name }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createGame(homeTeamId: UUID, awayTeamId: UUID, date: Date) async {
        guard let season else { return }
        do {
            let game = try await leagueService.createGame(seasonId: season.id, homeTeamId: homeTeamId, awayTeamId: awayTeamId, scheduledAt: date)
            games.insert(game, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Hero

private struct LeagueHero: View {
    let league: League
    let season: Season?
    let teamCount: Int
    let gameCount: Int
    let playerCount: Int

    private var inSeason: Bool {
        guard let season else { return true }
        let now = Date()
        if let start = season.startDate, now < start { return false }
        if let end = season.endDate, now > end { return false }
        return true
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Color(white: 0.16), Color(white: 0.04)], startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Spacer()
                    HStack(spacing: 5) {
                        Circle().fill(inSeason ? Brand.orange : .gray).frame(width: 7, height: 7)
                        Text(inSeason ? "IN SEASON" : "OFFSEASON")
                            .font(.system(size: 11, weight: .black).width(.condensed))
                            .kerning(1)
                            .foregroundStyle(inSeason ? Brand.orange : .gray)
                    }
                }
                Spacer()
                Text([season?.name, league.format.label].compactMap { $0 }.joined(separator: " · ").uppercased())
                    .font(.system(size: 12, weight: .black).width(.condensed))
                    .kerning(1.5)
                    .foregroundStyle(.white.opacity(0.6))
                Text(league.name)
                    .font(.display(38))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                HStack(spacing: 22) {
                    HeroStat(value: teamCount, label: "TEAMS")
                    HeroStat(value: gameCount, label: "GAMES")
                    HeroStat(value: playerCount, label: "PLAYERS")
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
            .padding(.top, 56)
        }
        .frame(minHeight: 240)
        .clipped()
    }
}

private struct HeroStat: View {
    let value: Int
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(value)")
                .font(.display(26))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 10, weight: .black).width(.condensed))
                .kerning(0.5)
                .foregroundStyle(.white.opacity(0.55))
        }
    }
}

// MARK: - Rows & cards

private struct StandingRow: View {
    let rank: Int
    let standing: TeamStanding
    let showRecord: Bool

    var body: some View {
        HStack {
            Text("\(rank)")
                .font(.display(18))
                .foregroundStyle(rank == 1 ? Brand.orange : .secondary)
                .frame(width: 24, alignment: .leading)
            Text(standing.team.name)
                .font(.system(size: 15, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(showRecord ? standing.record : "—")
                .font(.display(16))
                .frame(width: 52, alignment: .trailing)
            Text(showRecord ? standing.streak : "—")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct GameRow: View {
    let game: Game
    let teams: [Team]

    private func teamName(_ id: UUID) -> String {
        teams.first { $0.id == id }?.name ?? "TBD"
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(teamName(game.awayTeamId)) @ \(teamName(game.homeTeamId))")
                    .font(.system(size: 15, weight: .bold))
                Text(game.scheduledAt, style: .date)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if game.status == .final, let hs = game.homeScore, let as_ = game.awayScore {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(as_)–\(hs)")
                        .font(.display(18))
                    Text("FINAL")
                        .font(.system(size: 9, weight: .black).width(.condensed))
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .brandCard()
    }
}

/// Monogram crest for a team (first letters), a lightweight stand-in for logos.
struct TeamCrest: View {
    let name: String
    private var mono: String {
        let parts = name.split(separator: " ")
        return String(parts.prefix(2).compactMap { $0.first }).uppercased()
    }
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Brand.orange.opacity(0.15))
                .frame(width: 40, height: 40)
            Text(mono.isEmpty ? "T" : mono)
                .font(.display(16))
                .foregroundStyle(Brand.orange)
        }
    }
}

// MARK: - Viewer-personal cards

/// Shown only when the viewer holds a roster spot in this league — their own
/// team, record, and next game. A pure commissioner (no roster spot) never
/// sees this; they see the league-wide next game instead.
private struct YourTeamCard: View {
    let team: Team
    let record: String?
    let nextGame: Game?
    let teams: [Team]

    private func name(_ id: UUID) -> String { teams.first { $0.id == id }?.name ?? "TBD" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                TeamCrest(name: team.name)
                VStack(alignment: .leading, spacing: 2) {
                    SectionHeaderText("Your team")
                    Text(team.name).font(.display(22))
                }
                Spacer()
                if let record {
                    VStack(spacing: 0) {
                        Text(record).font(.display(22)).foregroundStyle(Brand.orange)
                        Text("W–L").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                    }
                }
            }
            if let nextGame {
                Divider()
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Text("Next: ")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                    + Text(nextGame.scheduledAt, format: .dateTime.month().day())
                        .font(.system(size: 13, weight: .bold))
                    + Text(" vs \(nextGame.homeTeamId == team.id ? name(nextGame.awayTeamId) : name(nextGame.homeTeamId))")
                        .font(.system(size: 13, weight: .bold))
                }
            }
        }
        .brandCard(padding: 16)
    }
}

private struct NextGameCard: View {
    let game: Game
    let teams: [Team]
    private func name(_ id: UUID) -> String { teams.first { $0.id == id }?.name ?? "TBD" }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 16)).foregroundStyle(Brand.orange)
            VStack(alignment: .leading, spacing: 2) {
                SectionHeaderText("Next game")
                Text("\(name(game.awayTeamId)) @ \(name(game.homeTeamId))")
                    .font(.system(size: 15, weight: .bold))
            }
            Spacer()
            Text(game.scheduledAt, format: .dateTime.month().day())
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .brandCard(padding: 16)
    }
}

// MARK: - Join code

private struct JoinCodeCard: View {
    let league: League

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderText("Join code")
            HStack {
                Text(league.joinCode)
                    .font(.display(34))
                    .kerning(4)
                    .foregroundStyle(Brand.orange)
                Spacer()
                ShareLink(item: "Join my Boxscore league \"\(league.name)\"! Open the app, tap Join a League, and enter code \(league.joinCode).") {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Brand.orange, in: Capsule())
                }
            }
            Text("Share this once — anyone with the code can pick a team and add themselves.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .brandCard(padding: 16)
    }
}

// MARK: - Sheets

private struct NewTeamSheet: View {
    let onCreate: (String) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form { TextField("Team Name", text: $name) }
                .navigationTitle("New Team")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") { Task { await onCreate(name); dismiss() } }
                            .disabled(name.isEmpty)
                    }
                }
        }
    }
}

private struct NewGameSheet: View {
    let teams: [Team]
    let onCreate: (UUID, UUID, Date) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var homeTeamId: UUID?
    @State private var awayTeamId: UUID?
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Picker("Home Team", selection: $homeTeamId) {
                    Text("Select").tag(UUID?.none)
                    ForEach(teams) { Text($0.name).tag(Optional($0.id)) }
                }
                Picker("Away Team", selection: $awayTeamId) {
                    Text("Select").tag(UUID?.none)
                    ForEach(teams) { Text($0.name).tag(Optional($0.id)) }
                }
                DatePicker("Date", selection: $date)
            }
            .navigationTitle("Schedule Game")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Schedule") {
                        guard let homeTeamId, let awayTeamId else { return }
                        Task { await onCreate(homeTeamId, awayTeamId, date); dismiss() }
                    }
                    .disabled(homeTeamId == nil || awayTeamId == nil || homeTeamId == awayTeamId)
                }
            }
        }
    }
}
