import SwiftUI

/// Self-serve join: enter the league's one shareable code, pick a team, and
/// add yourself — no organizer involvement or approval needed.
struct JoinLeagueView: View {
    let profile: Profile
    let onJoined: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var leagueService = LeagueService()
    @StateObject private var rosterService = RosterService()

    @State private var code = ""
    @State private var isLookingUp = false
    @State private var foundLeague: League?
    @State private var teams: [Team] = []
    @State private var selectedTeamId: UUID?
    @State private var displayName = ""
    @State private var isJoining = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                TextField("Join Code", text: $code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .disabled(foundLeague != nil)
                if foundLeague == nil {
                    Button {
                        Task { await findLeague() }
                    } label: {
                        if isLookingUp {
                            ProgressView()
                        } else {
                            Text("Find League")
                        }
                    }
                    .disabled(code.isEmpty || isLookingUp)
                }
            }

            if let foundLeague {
                Section(foundLeague.name) {
                    if teams.isEmpty {
                        Text("This league hasn't added teams yet — check back soon.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Team", selection: $selectedTeamId) {
                            Text("Select a team").tag(UUID?.none)
                            ForEach(teams) { Text($0.name).tag(Optional($0.id)) }
                        }
                        TextField("Your Name", text: $displayName)
                    }
                }
            }

            if let errorMessage {
                ErrorBanner(message: errorMessage)
            }

            if foundLeague != nil && !teams.isEmpty {
                Section {
                    Button {
                        Task { await join() }
                    } label: {
                        if isJoining {
                            ProgressView()
                        } else {
                            Text("Join Team").frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(selectedTeamId == nil || displayName.isEmpty || isJoining)
                }
            }
        }
        .navigationTitle("Join a League")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .onAppear { displayName = profile.displayName }
    }

    private func findLeague() async {
        isLookingUp = true
        errorMessage = nil
        do {
            let league = try await leagueService.findLeague(byJoinCode: code.uppercased())
            let seasons = try await leagueService.fetchSeasons(leagueId: league.id)
            if let currentSeason = seasons.first {
                teams = try await leagueService.fetchTeams(seasonId: currentSeason.id)
            }
            foundLeague = league
        } catch {
            errorMessage = "No league found with that code."
        }
        isLookingUp = false
    }

    private func join() async {
        guard let teamId = selectedTeamId else { return }
        isJoining = true
        errorMessage = nil
        do {
            _ = try await rosterService.joinLeagueSelf(joinCode: code.uppercased(), teamId: teamId, displayName: displayName)
            await onJoined()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isJoining = false
    }
}
