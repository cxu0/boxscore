import SwiftUI

struct GameDetailView: View {
    let game: Game
    let teams: [Team]
    let isOwner: Bool
    var onResult: (() async -> Void)? = nil

    @StateObject private var rosterService = RosterService()
    @StateObject private var leagueService = LeagueService()
    @State private var currentGame: Game
    @State private var homeRoster: [RosterSpot] = []
    @State private var awayRoster: [RosterSpot] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isShowingScoreEntry = false

    init(game: Game, teams: [Team], isOwner: Bool, onResult: (() async -> Void)? = nil) {
        self.game = game
        self.teams = teams
        self.isOwner = isOwner
        self.onResult = onResult
        _currentGame = State(initialValue: game)
    }

    private var homeTeam: Team? { teams.first { $0.id == game.homeTeamId } }
    private var awayTeam: Team? { teams.first { $0.id == game.awayTeamId } }

    var body: some View {
        List {
            if let errorMessage {
                ErrorBanner(message: errorMessage)
            }

            if currentGame.status == .final, let hs = currentGame.homeScore, let as_ = currentGame.awayScore {
                Section {
                    HStack {
                        scoreColumn(name: awayTeam?.name ?? "Away", score: as_, won: as_ > hs)
                        Text("FINAL")
                            .font(.system(size: 11, weight: .black).width(.condensed))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                        scoreColumn(name: homeTeam?.name ?? "Home", score: hs, won: hs > as_)
                    }
                    .padding(.vertical, 6)
                }
            }

            Section(awayTeam?.name ?? "Away") {
                ForEach(awayRoster) { spot in rosterRow(spot) }
            }
            Section(homeTeam?.name ?? "Home") {
                ForEach(homeRoster) { spot in rosterRow(spot) }
            }

            if isOwner {
                Section {
                    Button(currentGame.status == .final ? "Edit Final Score" : "Enter Final Score") {
                        isShowingScoreEntry = true
                    }
                }
            }
        }
        .navigationTitle("\(awayTeam?.name ?? "") @ \(homeTeam?.name ?? "")")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isLoading { LoadingView() } }
        .sheet(isPresented: $isShowingScoreEntry) {
            ScoreEntrySheet(
                homeName: homeTeam?.name ?? "Home",
                awayName: awayTeam?.name ?? "Away",
                initialHome: currentGame.homeScore,
                initialAway: currentGame.awayScore
            ) { home, away in
                await saveResult(home: home, away: away)
            }
        }
        .task { await loadRosters() }
    }

    private func scoreColumn(name: String, score: Int, won: Bool) -> some View {
        VStack(spacing: 4) {
            Text(name).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            Text("\(score)")
                .font(.display(34))
                .foregroundStyle(won ? Brand.orange : .primary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func rosterRow(_ spot: RosterSpot) -> some View {
        if isOwner {
            NavigationLink(spot.displayName) {
                PlayerStatEntryView(game: currentGame, rosterSpot: spot)
            }
        } else {
            Text(spot.displayName)
        }
    }

    private func loadRosters() async {
        isLoading = true
        do {
            if let homeTeam { homeRoster = try await rosterService.fetchRoster(teamId: homeTeam.id) }
            if let awayTeam { awayRoster = try await rosterService.fetchRoster(teamId: awayTeam.id) }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func saveResult(home: Int, away: Int) async {
        do {
            currentGame = try await leagueService.setGameResult(gameId: currentGame.id, homeScore: home, awayScore: away)
            await onResult?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ScoreEntrySheet: View {
    let homeName: String
    let awayName: String
    let initialHome: Int?
    let initialAway: Int?
    let onSave: (Int, Int) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var homeText: String
    @State private var awayText: String

    init(homeName: String, awayName: String, initialHome: Int?, initialAway: Int?, onSave: @escaping (Int, Int) async -> Void) {
        self.homeName = homeName
        self.awayName = awayName
        self.initialHome = initialHome
        self.initialAway = initialAway
        self.onSave = onSave
        _homeText = State(initialValue: initialHome.map(String.init) ?? "")
        _awayText = State(initialValue: initialAway.map(String.init) ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Final Score") {
                    HStack {
                        Text(awayName)
                        Spacer()
                        TextField("0", text: $awayText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                    }
                    HStack {
                        Text(homeName)
                        Spacer()
                        TextField("0", text: $homeText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                    }
                }
            }
            .navigationTitle("Final Score")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let home = Int(homeText) ?? 0
                        let away = Int(awayText) ?? 0
                        Task { await onSave(home, away); dismiss() }
                    }
                    .disabled(homeText.isEmpty || awayText.isEmpty)
                }
            }
        }
    }
}
