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
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Join a league.")
                    .font(.display(34))
                    .padding(.top, 8)

                if foundLeague == nil {
                    Text("Enter the code your organizer shared.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)

                    BrandTextField(placeholder: "Join code", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.display(22))

                    Button {
                        Task { await findLeague() }
                    } label: {
                        if isLookingUp {
                            ProgressView().tint(.white)
                        } else {
                            Text("Find League")
                        }
                    }
                    .buttonStyle(BrandPrimaryButtonStyle())
                    .disabled(code.isEmpty || isLookingUp)
                    .opacity(code.isEmpty ? 0.5 : 1)
                }

                if let foundLeague {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeaderText("League found")
                        Text(foundLeague.name)
                            .font(.display(26))
                    }
                    .brandCard()

                    if teams.isEmpty {
                        Text("This league hasn't added teams yet — check back soon.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .brandCard()
                    } else {
                        SectionHeaderText("Pick your team")
                        VStack(spacing: 8) {
                            ForEach(teams) { team in
                                Button {
                                    selectedTeamId = team.id
                                } label: {
                                    HStack {
                                        Text(team.name)
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        if selectedTeamId == team.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(Brand.orange)
                                        }
                                    }
                                    .brandCard()
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .strokeBorder(
                                                selectedTeamId == team.id ? Brand.orange : .clear,
                                                lineWidth: 2
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        SectionHeaderText("Your name")
                        BrandTextField(placeholder: "Your name", text: $displayName)

                        Button {
                            Task { await join() }
                        } label: {
                            if isJoining {
                                ProgressView().tint(.white)
                            } else {
                                Text("Join Team")
                            }
                        }
                        .buttonStyle(BrandPrimaryButtonStyle())
                        .disabled(selectedTeamId == nil || displayName.isEmpty || isJoining)
                        .opacity(selectedTeamId == nil || displayName.isEmpty ? 0.5 : 1)
                    }
                }

                if let errorMessage {
                    ErrorBanner(message: errorMessage)
                }
            }
            .padding(.horizontal, 20)
        }
        .navigationTitle("Join a League")
        .navigationBarTitleDisplayMode(.inline)
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
