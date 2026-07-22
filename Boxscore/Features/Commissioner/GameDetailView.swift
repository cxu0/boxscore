import SwiftUI

struct GameDetailView: View {
    let game: Game
    let teams: [Team]
    let isOwner: Bool
    var seasonGames: [Game] = []
    var onResult: (() async -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @StateObject private var rosterService = RosterService()
    @StateObject private var statService = StatService()
    @StateObject private var leagueService = LeagueService()

    @State private var currentGame: Game
    @State private var homeRoster: [RosterSpot] = []
    @State private var awayRoster: [RosterSpot] = []
    @State private var boxScores: [UUID: BoxScoreStat] = [:]   // rosterSpotId -> line
    @State private var tab: Tab = .boxScore
    @State private var boxTeam: Side = .away
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isShowingScoreEntry = false
    @State private var isShowingReschedule = false
    @State private var isConfirmingDelete = false
    @State private var rescheduleDate = Date()

    enum Tab: String, CaseIterable { case news, boxScore, teamStats, video }
    enum Side { case away, home }

    init(game: Game, teams: [Team], isOwner: Bool, seasonGames: [Game] = [], onResult: (() async -> Void)? = nil) {
        self.game = game
        self.teams = teams
        self.isOwner = isOwner
        self.seasonGames = seasonGames
        self.onResult = onResult
        _currentGame = State(initialValue: game)
    }

    private var homeTeam: Team? { teams.first { $0.id == currentGame.homeTeamId } }
    private var awayTeam: Team? { teams.first { $0.id == currentGame.awayTeamId } }

    private func record(_ teamId: UUID?) -> String {
        guard let teamId, !seasonGames.isEmpty else { return "" }
        let standings = LeagueService.standings(teams: teams, games: seasonGames)
        return standings.first { $0.team.id == teamId }?.record ?? ""
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header

                Picker("View", selection: $tab) {
                    Text("News").tag(Tab.news)
                    Text("Box Score").tag(Tab.boxScore)
                    Text("Team Stats").tag(Tab.teamStats)
                    Text("Video").tag(Tab.video)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                if isLoading {
                    LoadingView().padding(.top, 30)
                } else {
                    switch tab {
                    case .news: newsView
                    case .boxScore: boxScoreView
                    case .teamStats: teamStatsView
                    case .video: videoView
                    }
                }

                if let errorMessage {
                    ErrorBanner(message: errorMessage)
                }

                if isOwner {
                    Button(currentGame.hasResult ? "Edit Final Score" : "Enter Final Score") {
                        isShowingScoreEntry = true
                    }
                    .buttonStyle(BrandSecondaryButtonStyle())
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            }
            .padding(.top, 8)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isOwner {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            rescheduleDate = currentGame.scheduledAt
                            isShowingReschedule = true
                        } label: { Label("Reschedule", systemImage: "calendar") }
                        Button(role: .destructive) {
                            isConfirmingDelete = true
                        } label: { Label("Delete Game", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingScoreEntry) {
            ScoreEntrySheet(
                homeName: homeTeam?.name ?? "Home",
                awayName: awayTeam?.name ?? "Away",
                initialHome: currentGame.homeScore,
                initialAway: currentGame.awayScore
            ) { home, away in await saveResult(home: home, away: away) }
        }
        .sheet(isPresented: $isShowingReschedule) {
            RescheduleSheet(date: $rescheduleDate) { newDate in await reschedule(to: newDate) }
        }
        .confirmationDialog("Delete this game?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete Game", role: .destructive) { Task { await deleteGame() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the game and every box score entered for it.")
        }
        .task { await loadData() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            teamBlock(team: awayTeam, score: currentGame.awayScore, isWinner: isWinner(.away))
            VStack(spacing: 4) {
                if currentGame.hasResult {
                    Text("FINAL")
                        .font(.system(size: 12, weight: .black).width(.condensed))
                        .foregroundStyle(.secondary)
                } else {
                    Text(currentGame.scheduledAt, format: .dateTime.month().day())
                        .font(.system(size: 13, weight: .bold))
                    Text(currentGame.scheduledAt, format: .dateTime.hour().minute())
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 60)
            teamBlock(team: homeTeam, score: currentGame.homeScore, isWinner: isWinner(.home))
        }
        .padding(.horizontal, 16)
    }

    private func teamBlock(team: Team?, score: Int?, isWinner: Bool) -> some View {
        VStack(spacing: 6) {
            TeamCrest(name: team?.name ?? "")
            Text(team?.name ?? "TBD")
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            let rec = record(team?.id)
            if !rec.isEmpty {
                Text(rec).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if let score {
                Text("\(score)")
                    .font(.display(40))
                    .foregroundStyle(isWinner ? Brand.orange : .primary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func isWinner(_ side: Side) -> Bool {
        guard let hs = currentGame.homeScore, let as_ = currentGame.awayScore else { return false }
        return side == .home ? hs > as_ : as_ > hs
    }

    // MARK: News

    private var newsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RECAP")
                .font(.system(size: 10, weight: .black).width(.condensed))
                .kerning(1.5)
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Brand.orange, in: Capsule())
            Text(currentGame.hasResult ? "Recap coming soon." : "Tip-off coming up.")
                .font(.display(24))
            Text(currentGame.hasResult
                 ? "Once AI recaps are live, every final posts a full write-up here — headline, key performers, and the story of the game."
                 : "This matchup hasn't been played yet. Check back after the final for the recap.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Brand.card, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
    }

    // MARK: Box Score

    private var boxScoreView: some View {
        let roster = boxTeam == .away ? awayRoster : homeRoster
        return VStack(spacing: 12) {
            Picker("Team", selection: $boxTeam) {
                Text(awayTeam?.name ?? "Away").tag(Side.away)
                Text(homeTeam?.name ?? "Home").tag(Side.home)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)

            if roster.isEmpty {
                Text("No players on this team yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
            } else {
                BoxScoreTable(
                    roster: roster,
                    lineFor: { boxScores[$0.id] ?? .empty(gameId: currentGame.id, rosterSpotId: $0.id) },
                    isOwner: isOwner,
                    game: currentGame
                )
            }
        }
    }

    // MARK: Team Stats

    private var teamStatsView: some View {
        let away = teamTotals(awayRoster)
        let home = teamTotals(homeRoster)
        return VStack(spacing: 0) {
            teamStatHeader
            teamStatRow("Points", away.pts, home.pts)
            Divider().padding(.leading, 16)
            teamStatRow("Field Goals", "\(away.fgm)-\(away.fga)", "\(home.fgm)-\(home.fga)")
            Divider().padding(.leading, 16)
            teamStatRow("3-Pointers", "\(away.tpm)-\(away.tpa)", "\(home.tpm)-\(home.tpa)")
            Divider().padding(.leading, 16)
            teamStatRow("Rebounds", away.reb, home.reb)
            Divider().padding(.leading, 16)
            teamStatRow("Assists", away.ast, home.ast)
            Divider().padding(.leading, 16)
            teamStatRow("Steals", away.stl, home.stl)
            Divider().padding(.leading, 16)
            teamStatRow("Blocks", away.blk, home.blk)
            Divider().padding(.leading, 16)
            teamStatRow("Turnovers", away.turnovers, home.turnovers)
        }
        .background(Brand.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Brand.border, lineWidth: 1))
        .padding(.horizontal, 16)
    }

    private var teamStatHeader: some View {
        HStack {
            Text(awayTeam?.name ?? "Away")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("")
                .frame(width: 90)
            Text(homeTeam?.name ?? "Home")
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .black).width(.condensed))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func teamStatRow(_ label: String, _ away: Any, _ home: Any) -> some View {
        HStack {
            Text("\(away)")
                .font(.display(18))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 90)
            Text("\(home)")
                .font(.display(18))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private func teamTotals(_ roster: [RosterSpot]) -> BoxScoreStat.Totals {
        roster.reduce(into: BoxScoreStat.Totals()) { acc, spot in
            if let line = boxScores[spot.id] { acc.add(line) }
        }
    }

    // MARK: Video

    private var videoView: some View {
        VStack(spacing: 10) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("Highlights coming soon")
                .font(.system(size: 15, weight: .bold))
            Text("Game video and highlight clips will live here in a future update.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(30)
        .padding(.horizontal, 16)
    }

    // MARK: Data

    private func loadData() async {
        isLoading = true
        do {
            if let homeTeam {
                homeRoster = try await rosterService.fetchRoster(teamId: homeTeam.id)
            }
            if let awayTeam {
                awayRoster = try await rosterService.fetchRoster(teamId: awayTeam.id)
            }
            let lines = try await statService.fetchBoxScores(gameId: currentGame.id)
            boxScores = Dictionary(uniqueKeysWithValues: lines.map { ($0.rosterSpotId, $0) })
            errorMessage = nil
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

    private func reschedule(to date: Date) async {
        do {
            try await leagueService.rescheduleGame(id: currentGame.id, date: date)
            currentGame.scheduledAt = date
            await onResult?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteGame() async {
        do {
            try await leagueService.deleteGame(id: currentGame.id)
            await onResult?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct RescheduleSheet: View {
    @Binding var date: Date
    let onSave: (Date) async -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date & time", selection: $date)
                    .datePickerStyle(.graphical)
            }
            .navigationTitle("Reschedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await onSave(date); dismiss() } }.fontWeight(.bold)
                }
            }
        }
    }
}

// MARK: - Box score table

/// Player names pinned on the left, stat columns in a horizontal scroll so the
/// full line fits any screen. Rows use a fixed height so both halves stay aligned.
private struct BoxScoreTable: View {
    let roster: [RosterSpot]
    let lineFor: (RosterSpot) -> BoxScoreStat
    let isOwner: Bool
    let game: Game

    private let rowHeight: CGFloat = 44
    private let columns: [(String, (BoxScoreStat) -> String)] = [
        ("PTS", { "\($0.pts)" }),
        ("FG", { "\($0.fgm)-\($0.fga)" }),
        ("3PT", { "\($0.tpm)-\($0.tpa)" }),
        ("REB", { "\($0.reb)" }),
        ("AST", { "\($0.ast)" }),
        ("STL", { "\($0.stl)" }),
        ("BLK", { "\($0.blk)" }),
        ("TO", { "\($0.turnovers)" }),
        ("PF", { "\($0.pf)" }),
    ]

    var body: some View {
        HStack(spacing: 0) {
            // Pinned name column
            VStack(spacing: 0) {
                cell(alignment: .leading) {
                    Text("PLAYER")
                        .font(.system(size: 10, weight: .black).width(.condensed))
                        .foregroundStyle(.secondary)
                }
                ForEach(roster) { spot in
                    rowLink(spot) {
                        cell(alignment: .leading) {
                            HStack(spacing: 4) {
                                Text(spot.displayName)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)
                                    .foregroundStyle(.primary)
                                if isOwner {
                                    Image(systemName: "square.and.pencil")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Brand.orange)
                                }
                            }
                        }
                    }
                }
            }
            .frame(width: 140)
            .background(Brand.card, in: RoundedRectangle(cornerRadius: 12))

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach(columns, id: \.0) { col in
                            Text(col.0)
                                .font(.system(size: 10, weight: .black).width(.condensed))
                                .foregroundStyle(.secondary)
                                .frame(width: 48, height: rowHeight)
                        }
                    }
                    ForEach(roster) { spot in
                        let line = lineFor(spot)
                        HStack(spacing: 0) {
                            ForEach(columns, id: \.0) { col in
                                Text(col.1(line))
                                    .font(.system(size: 13, weight: col.0 == "PTS" ? .bold : .regular))
                                    .monospacedDigit()
                                    .foregroundStyle(col.0 == "PTS" ? .primary : .secondary)
                                    .frame(width: 48, height: rowHeight)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func rowLink<Content: View>(_ spot: RosterSpot, @ViewBuilder content: () -> Content) -> some View {
        if isOwner {
            NavigationLink { PlayerStatEntryView(game: game, rosterSpot: spot) } label: { content() }
                .buttonStyle(.plain)
        } else {
            content()
        }
    }

    private func cell<Content: View>(alignment: Alignment, @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: alignment)
            .frame(height: rowHeight)
            .padding(.horizontal, 12)
    }
}

// MARK: - Score entry

private struct ScoreEntrySheet: View {
    let homeName: String
    let awayName: String
    let initialHome: Int?
    let initialAway: Int?
    let onSave: (Int, Int) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var homeText: String
    @State private var awayText: String
    @State private var editing: GameDetailView.Side = .away

    init(homeName: String, awayName: String, initialHome: Int?, initialAway: Int?, onSave: @escaping (Int, Int) async -> Void) {
        self.homeName = homeName
        self.awayName = awayName
        self.initialHome = initialHome
        self.initialAway = initialAway
        self.onSave = onSave
        _homeText = State(initialValue: initialHome.map(String.init) ?? "")
        _awayText = State(initialValue: initialAway.map(String.init) ?? "")
    }

    private var awayVal: Int { Int(awayText) ?? 0 }
    private var homeVal: Int { Int(homeText) ?? 0 }
    private var canSave: Bool { !homeText.isEmpty && !awayText.isEmpty }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                scoreboard
                Text("Tap a team, then type its score")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                keypad
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .navigationTitle("Final Score")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await onSave(homeVal, awayVal); dismiss() }
                    }
                    .fontWeight(.bold)
                    .disabled(!canSave)
                }
            }
        }
    }

    // MARK: Scoreboard

    private var scoreboard: some View {
        HStack(alignment: .center, spacing: 8) {
            teamColumn(side: .away, name: awayName, text: awayText, value: awayVal, opponent: homeVal)
            Text("FINAL")
                .font(.system(size: 11, weight: .black).width(.condensed))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 48)
            teamColumn(side: .home, name: homeName, text: homeText, value: homeVal, opponent: awayVal)
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 18))
    }

    private func teamColumn(side: GameDetailView.Side, name: String, text: String, value: Int, opponent: Int) -> some View {
        let isEditing = editing == side
        let isLeading = value > opponent && !text.isEmpty
        return Button {
            editing = side
        } label: {
            VStack(spacing: 8) {
                TeamCrest(name: name)
                Text(name)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(text.isEmpty ? "0" : text)
                    .font(.display(52))
                    .monospacedDigit()
                    .foregroundStyle(isLeading ? Brand.orange : .white.opacity(text.isEmpty ? 0.35 : 0.9))
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(isEditing ? Brand.orange : .clear)
                            .frame(height: 3)
                            .offset(y: 6)
                    }
                Text(isEditing ? "EDITING" : " ")
                    .font(.system(size: 9, weight: .black).width(.condensed))
                    .kerning(1.5)
                    .foregroundStyle(Brand.orange)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: Keypad

    private let keys: [String] = ["1","2","3","4","5","6","7","8","9","clear","0","⌫"]

    private var keypad: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(keys, id: \.self) { key in
                Button {
                    press(key)
                } label: {
                    Group {
                        if key == "⌫" {
                            Image(systemName: "delete.left")
                        } else if key == "clear" {
                            Text("clear").font(.system(size: 15, weight: .medium))
                        } else {
                            Text(key).font(.display(26))
                        }
                    }
                    .foregroundStyle(key == "clear" || key == "⌫" ? Color.secondary : .primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(Brand.card, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func press(_ key: String) {
        switch key {
        case "clear": setEditing("")
        case "⌫": setEditing(String(currentText().dropLast()))
        default:
            var cur = currentText()
            guard cur.count < 3 else { return }
            if cur == "0" { cur = "" }
            setEditing(cur + key)
        }
    }

    private func currentText() -> String { editing == .away ? awayText : homeText }
    private func setEditing(_ value: String) {
        if editing == .away { awayText = value } else { homeText = value }
    }
}
