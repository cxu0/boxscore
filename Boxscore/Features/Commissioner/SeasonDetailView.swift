import SwiftUI

struct SeasonDetailView: View {
    let season: Season

    @StateObject private var leagueService = LeagueService()
    @State private var teams: [Team] = []
    @State private var games: [Game] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isShowingNewTeam = false
    @State private var isShowingNewGame = false

    var body: some View {
        List {
            Section("Teams") {
                if teams.isEmpty {
                    Text("No teams yet").foregroundStyle(.secondary)
                }
                ForEach(teams) { team in
                    NavigationLink(team.name) {
                        TeamDetailView(team: team)
                    }
                }
                Button {
                    isShowingNewTeam = true
                } label: {
                    Label("Add Team", systemImage: "plus")
                }
            }

            Section("Games") {
                if games.isEmpty {
                    Text("No games scheduled").foregroundStyle(.secondary)
                }
                ForEach(games) { game in
                    NavigationLink {
                        GameDetailView(game: game, teams: teams)
                    } label: {
                        GameRow(game: game, teams: teams)
                    }
                }
                Button {
                    isShowingNewGame = true
                } label: {
                    Label("Schedule Game", systemImage: "plus")
                }
                .disabled(teams.count < 2)
            }

            if let errorMessage {
                ErrorBanner(message: errorMessage)
            }
        }
        .navigationTitle(season.name)
        .overlay { if isLoading { LoadingView() } }
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

    private func loadAll() async {
        isLoading = true
        do {
            async let t = leagueService.fetchTeams(seasonId: season.id)
            async let g = leagueService.fetchGames(seasonId: season.id)
            teams = try await t
            games = try await g
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func createTeam(name: String) async {
        do {
            let team = try await leagueService.createTeam(name: name, seasonId: season.id)
            teams.append(team)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createGame(homeTeamId: UUID, awayTeamId: UUID, date: Date) async {
        do {
            let game = try await leagueService.createGame(seasonId: season.id, homeTeamId: homeTeamId, awayTeamId: awayTeamId, scheduledAt: date)
            games.insert(game, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct GameRow: View {
    let game: Game
    let teams: [Team]

    private func teamName(_ id: UUID) -> String {
        teams.first { $0.id == id }?.name ?? "Unknown"
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("\(teamName(game.awayTeamId)) @ \(teamName(game.homeTeamId))")
                Text(game.scheduledAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if game.status == .final {
                Text("Final").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct NewTeamSheet: View {
    let onCreate: (String) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form { TextField("Team Name", text: $name) }
                .navigationTitle("New Team")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") {
                            Task { await onCreate(name); dismiss() }
                        }
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
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
