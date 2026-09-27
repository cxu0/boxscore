import SwiftUI

struct TeamDetailView: View {
    let team: Team
    let isOwner: Bool
    /// Context from the league page, used for the hero (standing, next game,
    /// league/season name) — all data we already loaded one level up.
    var league: League? = nil
    var season: Season? = nil
    var allTeams: [Team] = []
    var seasonGames: [Game] = []
    var onChange: (() async -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @StateObject private var rosterService = RosterService()
    @StateObject private var leagueService = LeagueService()
    @StateObject private var statService = StatService()

    @State private var teamName: String
    @State private var roster: [RosterSpot] = []
    @State private var pendingRequests: [ClaimRequest] = []
    @State private var lines: [UUID: (totals: BoxScoreStat.Totals, gamesPlayed: Int)] = [:]
    @State private var statSort: StatSort = .pts
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isShowingAddPlayer = false

    // Edit / fix state
    @State private var isRenamingTeam = false
    @State private var renameTeamText = ""
    @State private var isConfirmingDeleteTeam = false
    @State private var spotRenaming: RosterSpot?
    @State private var renameSpotText = ""
    @State private var spotPendingDelete: RosterSpot?

    enum StatSort: String, CaseIterable {
        case pts = "PTS", reb = "REB", ast = "AST"
        var label: String { rawValue }
    }

    init(
        team: Team, isOwner: Bool,
        league: League? = nil, season: Season? = nil, allTeams: [Team] = [], seasonGames: [Game] = [],
        onChange: (() async -> Void)? = nil
    ) {
        self.team = team
        self.isOwner = isOwner
        self.league = league
        self.season = season
        self.allTeams = allTeams
        self.seasonGames = seasonGames
        self.onChange = onChange
        _teamName = State(initialValue: team.name)
    }

    // MARK: Derived

    private var teamGames: [Game] {
        seasonGames.filter { $0.homeTeamId == team.id || $0.awayTeamId == team.id }
    }

    private var standing: TeamStanding? {
        LeagueService.standings(teams: allTeams, games: seasonGames).first { $0.team.id == team.id }
    }

    private var rank: Int? {
        let ranked = LeagueService.standings(teams: allTeams, games: seasonGames)
        return ranked.firstIndex { $0.team.id == team.id }.map { $0 + 1 }
    }

    private var teamPPG: Double {
        let finals = teamGames.filter { $0.status == .final && $0.hasResult }
        guard !finals.isEmpty else { return 0 }
        let total = finals.reduce(0) { sum, g in
            sum + (g.homeTeamId == team.id ? (g.homeScore ?? 0) : (g.awayScore ?? 0))
        }
        return Double(total) / Double(finals.count)
    }

    private var nextGame: Game? {
        teamGames.filter { $0.status == .scheduled }.sorted { $0.scheduledAt < $1.scheduledAt }.first
    }

    private func opponent(of game: Game) -> Team? {
        let oppId = game.homeTeamId == team.id ? game.awayTeamId : game.homeTeamId
        return allTeams.first { $0.id == oppId }
    }

    private func average(_ spot: RosterSpot, _ key: (BoxScoreStat.Totals) -> Int) -> Double {
        guard let line = lines[spot.id], line.gamesPlayed > 0 else { return 0 }
        return Double(key(line.totals)) / Double(line.gamesPlayed)
    }

    private var sortedRoster: [RosterSpot] {
        let key: (BoxScoreStat.Totals) -> Int
        switch statSort {
        case .pts: key = { $0.pts }
        case .reb: key = { $0.reb }
        case .ast: key = { $0.ast }
        }
        return roster.sorted { average($0, key) > average($1, key) }
    }

    private var teamLeaders: (ppg: RosterSpot?, rpg: RosterSpot?, apg: RosterSpot?) {
        func leader(_ key: (BoxScoreStat.Totals) -> Int) -> RosterSpot? {
            roster.filter { (lines[$0.id]?.gamesPlayed ?? 0) > 0 }
                .max { average($0, key) < average($1, key) }
        }
        return (leader { $0.pts }, leader { $0.reb }, leader { $0.ast })
    }

    private var hasAnyStats: Bool {
        roster.contains { (lines[$0.id]?.gamesPlayed ?? 0) > 0 }
    }

    var body: some View {
        Group {
            if isLoading {
                LoadingView()
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        hero
                        VStack(spacing: 16) {
                            if let nextGame {
                                nextGameCard(nextGame)
                            }
                            if hasAnyStats {
                                leadersSection
                            }
                            rosterSection
                            if isOwner && !pendingRequests.isEmpty {
                                pendingRequestsSection
                            }
                            if let errorMessage {
                                ErrorBanner(message: errorMessage)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 24)
                    }
                }
                .ignoresSafeArea(edges: .top)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .brandBackground()
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            if isOwner {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            isShowingAddPlayer = true
                        } label: { Label("Add Player", systemImage: "person.badge.plus") }
                        Button {
                            renameTeamText = teamName
                            isRenamingTeam = true
                        } label: { Label("Rename Team", systemImage: "pencil") }
                        Button(role: .destructive) {
                            isConfirmingDeleteTeam = true
                        } label: { Label("Delete Team", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.white.opacity(0.15), in: Circle())
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingAddPlayer) {
            NewRosterSpotSheet { name in await addPlayer(name: name) }
        }
        .alert("Rename team", isPresented: $isRenamingTeam) {
            TextField("Team name", text: $renameTeamText)
            Button("Save") { Task { await renameTeam() } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename player", isPresented: Binding(get: { spotRenaming != nil }, set: { if !$0 { spotRenaming = nil } })) {
            TextField("Player name", text: $renameSpotText)
            Button("Save") { Task { await renameSpot() } }
            Button("Cancel", role: .cancel) { spotRenaming = nil }
        }
        .confirmationDialog("Delete this team?", isPresented: $isConfirmingDeleteTeam, titleVisibility: .visible) {
            Button("Delete Team", role: .destructive) { Task { await deleteTeam() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the team, its roster, and all stats recorded for it.")
        }
        .confirmationDialog(
            "Remove this player?",
            isPresented: Binding(get: { spotPendingDelete != nil }, set: { if !$0 { spotPendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove Player", role: .destructive) { Task { await deleteSpot() } }
            Button("Cancel", role: .cancel) { spotPendingDelete = nil }
        } message: {
            Text("This removes the roster spot and any stats recorded against it.")
        }
        .task { await loadAll() }
        .refreshable { await loadAll() }
    }

    // MARK: Hero

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Color(white: 0.16), Color(white: 0.04)], startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 10) {
                Spacer(minLength: 40)
                HStack(spacing: 10) {
                    TeamCrest(name: teamName)
                    VStack(alignment: .leading, spacing: 2) {
                        Text([league?.name, season?.name].compactMap { $0 }.joined(separator: " · ").uppercased())
                            .font(.system(size: 11, weight: .black).width(.condensed))
                            .kerning(1.2)
                            .foregroundStyle(.white.opacity(0.55))
                        Text(teamName)
                            .font(.display(32))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }

                Divider().background(.white.opacity(0.15)).padding(.top, 4)

                HStack(spacing: 0) {
                    heroStat(standing?.record ?? "—", "RECORD")
                    heroStat(rank.map(ordinal) ?? "—", "STANDING")
                    heroStat(standing?.streak ?? "—", "STREAK", tint: (standing?.streak.hasPrefix("W") ?? false) ? Brand.orange : nil)
                    heroStat(teamPPG > 0 ? String(format: "%.1f", teamPPG) : "—", "PPG")
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
            .padding(.top, 56)
        }
        .frame(minHeight: 220)
        .clipped()
    }

    private func heroStat(_ value: String, _ label: String, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.display(22))
                .foregroundStyle(tint ?? .white)
            Text(label)
                .font(.system(size: 9, weight: .black).width(.condensed))
                .kerning(0.5)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Next game

    private func nextGameCard(_ game: Game) -> some View {
        let opp = opponent(of: game)
        let oppRecord = LeagueService.standings(teams: allTeams, games: seasonGames)
            .first { $0.team.id == opp?.id }?.record
        let cal = Calendar.current
        return NavigationLink {
            GameDetailView(game: game, teams: allTeams, isOwner: isOwner, canKeepStats: isOwner, seasonGames: seasonGames)
        } label: {
            HStack(spacing: 14) {
                VStack(spacing: 2) {
                    Text(game.scheduledAt, format: .dateTime.weekday(.abbreviated))
                        .font(.system(size: 10, weight: .black).width(.condensed))
                        .foregroundStyle(Brand.orange)
                    Text("\(cal.component(.day, from: game.scheduledAt))")
                        .font(.display(26))
                }
                .frame(width: 44)

                Divider()

                VStack(alignment: .leading, spacing: 3) {
                    Text("NEXT GAME · \(game.scheduledAt.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 10, weight: .black).width(.condensed))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Text("vs \(opp?.name ?? "TBD")")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.primary)
                        if let oppRecord {
                            Text("(\(oppRecord))")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .brandCard(padding: 14)
        }
        .buttonStyle(.plain)
    }

    // MARK: Leaders

    private var leadersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderText("Team leaders")
            HStack(spacing: 8) {
                leaderTile("PPG", teamLeaders.ppg, average(teamLeaders.ppg, keyFor: .pts))
                leaderTile("RPG", teamLeaders.rpg, average(teamLeaders.rpg, keyFor: .reb))
                leaderTile("APG", teamLeaders.apg, average(teamLeaders.apg, keyFor: .ast))
            }
        }
    }

    private func average(_ spot: RosterSpot?, keyFor sort: StatSort) -> Double {
        guard let spot else { return 0 }
        switch sort {
        case .pts: return average(spot) { $0.pts }
        case .reb: return average(spot) { $0.reb }
        case .ast: return average(spot) { $0.ast }
        }
    }

    private func leaderTile(_ label: String, _ spot: RosterSpot?, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .black).width(.condensed))
                .foregroundStyle(.secondary)
            Text(value > 0 ? String(format: "%.1f", value) : "—")
                .font(.display(24))
                .foregroundStyle(label == "PPG" ? Brand.orange : .primary)
            Text(spot?.displayName ?? "—")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Brand.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Brand.border, lineWidth: 1))
    }

    // MARK: Roster

    private var rosterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionHeaderText("Roster · \(roster.count)")
                Spacer()
                sortPicker
            }

            if roster.isEmpty {
                Text("No players yet. Add a roster spot, or share the league's join code so players can add themselves.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .brandCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sortedRoster.enumerated()), id: \.element.id) { index, spot in
                        if index > 0 { Divider().padding(.leading, 70) }
                        rosterRow(spot)
                    }
                }
                .background(Brand.card, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Brand.border, lineWidth: 1))
            }
        }
    }

    private var sortPicker: some View {
        HStack(spacing: 6) {
            ForEach(StatSort.allCases, id: \.self) { sort in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { statSort = sort }
                } label: {
                    Text(sort.label)
                        .font(.system(size: 11, weight: .black).width(.condensed))
                        .foregroundStyle(statSort == sort ? .white : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(statSort == sort ? Brand.orange : Brand.card, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func rosterRow(_ spot: RosterSpot) -> some View {
        let claimed = spot.playerId != nil
        let line = lines[spot.id]
        let gp = line?.gamesPlayed ?? 0
        let value: Double
        switch statSort {
        case .pts: value = average(spot) { $0.pts }
        case .reb: value = average(spot) { $0.reb }
        case .ast: value = average(spot) { $0.ast }
        }
        return NavigationLink {
            PlayerProfileLoader(rosterSpot: spot)
        } label: {
            HStack(spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    Circle()
                        .fill(claimed ? Brand.card : .clear)
                        .overlay(Circle().strokeBorder(claimed ? Color.clear : Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Text(initials(spot.displayName))
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.secondary)
                        )
                    if claimed {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Brand.orange)
                            .background(Circle().fill(Brand.card).frame(width: 15, height: 15))
                            .offset(x: 3, y: 3)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(spot.displayName)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.primary)
                        if !claimed {
                            Text("UNCLAIMED")
                                .font(.system(size: 8, weight: .black).width(.condensed))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [2, 2])))
                        }
                    }
                    Text("\(gp) GP")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 0) {
                    Text(gp > 0 ? String(format: "%.1f", value) : "—")
                        .font(.display(18))
                        .foregroundStyle(statSort == .pts ? Brand.orange : .primary)
                    Text(statSort.label + "G")
                        .font(.system(size: 9, weight: .black).width(.condensed))
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if isOwner {
                Button {
                    renameSpotText = spot.displayName
                    spotRenaming = spot
                } label: { Label("Rename", systemImage: "pencil") }
                Button(role: .destructive) {
                    spotPendingDelete = spot
                } label: { Label("Remove", systemImage: "trash") }
            }
        }
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    // MARK: Pending requests

    private var pendingRequestsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderText("Pending requests")
            ForEach(pendingRequests) { request in
                PendingRequestRow(
                    request: request,
                    onApprove: { await approve(request) },
                    onDeny: { await deny(request) }
                )
            }
        }
    }

    // MARK: Data

    private func loadAll() async {
        isLoading = true
        do {
            roster = try await rosterService.fetchRoster(teamId: team.id)
            if isOwner {
                pendingRequests = try await rosterService.fetchPendingClaimRequests(teamId: team.id)
            }
            await loadStats()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadStats() async {
        await withTaskGroup(of: (UUID, (totals: BoxScoreStat.Totals, gamesPlayed: Int)).self) { group in
            for spot in roster {
                group.addTask {
                    let result = (try? await statService.fetchRosterSpotStats(rosterSpotId: spot.id)) ?? (BoxScoreStat.Totals(), 0)
                    return (spot.id, result)
                }
            }
            for await (id, result) in group {
                lines[id] = result
            }
        }
    }

    private func addPlayer(name: String) async {
        do {
            let spot = try await rosterService.addRosterSpot(teamId: team.id, displayName: name)
            roster.append(spot)
            await loadStats()
            await onChange?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func renameTeam() async {
        let name = renameTeamText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            try await leagueService.renameTeam(id: team.id, name: name)
            teamName = name
            await onChange?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteTeam() async {
        do {
            try await leagueService.deleteTeam(id: team.id)
            await onChange?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func renameSpot() async {
        guard let spot = spotRenaming else { return }
        let name = renameSpotText.trimmingCharacters(in: .whitespaces)
        spotRenaming = nil
        guard !name.isEmpty else { return }
        do {
            try await rosterService.renameRosterSpot(id: spot.id, displayName: name)
            await loadAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteSpot() async {
        guard let spot = spotPendingDelete else { return }
        spotPendingDelete = nil
        do {
            try await rosterService.deleteRosterSpot(id: spot.id)
            roster.removeAll { $0.id == spot.id }
            await onChange?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func approve(_ request: ClaimRequest) async {
        do {
            _ = try await rosterService.approveClaimRequest(id: request.id)
            await loadAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deny(_ request: ClaimRequest) async {
        do {
            try await rosterService.denyClaimRequest(id: request.id)
            pendingRequests.removeAll { $0.id == request.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private func ordinal(_ n: Int) -> String {
    let suffix: String
    switch (n % 100, n % 10) {
    case (11, _), (12, _), (13, _): suffix = "th"
    case (_, 1): suffix = "st"
    case (_, 2): suffix = "nd"
    case (_, 3): suffix = "rd"
    default: suffix = "th"
    }
    return "\(n)\(suffix)"
}

private struct PendingRequestRow: View {
    let request: ClaimRequest
    let onApprove: () async -> Void
    let onDeny: () async -> Void

    var body: some View {
        HStack {
            Text(request.requesterName)
            Spacer()
            Button("Approve") { Task { await onApprove() } }
                .buttonStyle(.bordered)
            Button("Deny") { Task { await onDeny() } }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
        }
        .brandCard(padding: 12)
    }
}

private struct NewRosterSpotSheet: View {
    let onCreate: (String) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form { TextField("Player Name", text: $name) }
                .navigationTitle("Add Player")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            Task { await onCreate(name); dismiss() }
                        }
                        .disabled(name.isEmpty)
                    }
                }
        }
    }
}
