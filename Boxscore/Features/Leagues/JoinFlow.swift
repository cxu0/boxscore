import SwiftUI

/// How a visitor joins a public league they're looking at. (Private leagues
/// fill by roster import + email match — there's no player join code.)
enum JoinMode: Equatable {
    case publicOpen         // public + instant
    case publicApproval     // public + request-to-join
}

/// Stat-keeper code entry: redeems the code, then opens the league with
/// box-score rights.
struct StaffCodeSheet: View {
    let onResolved: (League) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var leagueService = LeagueService()
    @State private var code = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var trimmed: String { code.trimmingCharacters(in: .whitespaces).uppercased() }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Stat-keeper code")
                    .font(.display(34))
                    .padding(.top, 8)
                Text("The 6-character code your league organizer sent you.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                BrandTextField(placeholder: "Code", text: $code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.display(22))

                if let errorMessage {
                    ErrorBanner(message: errorMessage)
                }

                Button {
                    Task { await redeem() }
                } label: {
                    if isSubmitting { ProgressView().tint(.white) } else { Text("Continue") }
                }
                .buttonStyle(BrandPrimaryButtonStyle())
                .disabled(trimmed.isEmpty || isSubmitting)
                .opacity(trimmed.isEmpty ? 0.5 : 1)

                Spacer()
            }
            .padding(.horizontal, 20)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func redeem() async {
        isSubmitting = true
        errorMessage = nil
        do {
            let league = try await leagueService.redeemStaffCode(trimmed)
            isSubmitting = false
            dismiss()
            onResolved(league)
        } catch {
            errorMessage = "That code doesn't match any league."
            isSubmitting = false
        }
    }
}

/// Pick an existing team or create a new one, then join (or request to join).
struct JoinTeamSheet: View {
    let league: League
    let mode: JoinMode
    let teams: [Team]
    let onDone: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthService
    @StateObject private var rosterService = RosterService()
    @StateObject private var leagueService = LeagueService()

    @State private var counts: [UUID: Int] = [:]
    @State private var selectedTeamId: UUID?
    @State private var creatingNew = false
    @State private var newTeamName = ""
    @State private var displayName = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var isApproval: Bool { mode == .publicApproval }
    private var canCreateTeam: Bool {
        league.allowPlayerTeams && (league.maxTeams == nil || teams.count < league.maxTeams!)
    }
    private func isFull(_ team: Team) -> Bool {
        guard let max = league.maxRosterSize, let c = counts[team.id] else { return false }
        return c >= max
    }
    private var canSubmit: Bool {
        guard !displayName.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if creatingNew { return !newTeamName.trimmingCharacters(in: .whitespaces).isEmpty }
        return selectedTeamId != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(isApproval ? "Request to join" : "Pick your team")
                        .font(.display(30))
                        .padding(.top, 8)

                    ForEach(teams) { team in
                        teamRow(team)
                    }

                    if canCreateTeam {
                        createRow
                    }

                    SectionHeaderText("Your name")
                    BrandTextField(placeholder: "Your name", text: $displayName)

                    if let errorMessage { ErrorBanner(message: errorMessage) }

                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Text(isApproval ? "Send Request" : "Join Team")
                        }
                    }
                    .buttonStyle(BrandPrimaryButtonStyle())
                    .disabled(!canSubmit || isSubmitting)
                    .opacity(canSubmit ? 1 : 0.5)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .navigationTitle(league.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear { displayName = auth.profile?.displayName ?? "" }
            .task { await loadCounts() }
        }
    }

    private func teamRow(_ team: Team) -> some View {
        let full = isFull(team)
        let selected = selectedTeamId == team.id && !creatingNew
        return Button {
            guard !full else { return }
            creatingNew = false
            selectedTeamId = team.id
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(team.name).font(.system(size: 15, weight: .bold))
                    Text("\(counts[team.id] ?? 0) players\(full ? " · FULL" : "")")
                        .font(.system(size: 12))
                        .foregroundStyle(full ? Color.red : .secondary)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.orange)
                }
            }
            .brandCard()
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? Brand.orange : .clear, lineWidth: 2))
            .opacity(full ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(full)
    }

    private var createRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                creatingNew = true
                selectedTeamId = nil
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill").foregroundStyle(Brand.orange)
                    Text("Create a new team").font(.system(size: 15, weight: .bold)).foregroundStyle(.primary)
                    Spacer()
                    if creatingNew { Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.orange) }
                }
                .brandCard()
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(creatingNew ? Brand.orange : .clear, lineWidth: 2))
            }
            .buttonStyle(.plain)
            if creatingNew {
                BrandTextField(placeholder: "New team name", text: $newTeamName)
            }
        }
    }

    private func loadCounts() async {
        for team in teams {
            if let c = try? await leagueService.fetchRosterCount(teamId: team.id) {
                counts[team.id] = c
            }
        }
    }

    private func submit() async {
        isSubmitting = true
        errorMessage = nil
        let name = displayName.trimmingCharacters(in: .whitespaces)
        do {
            if creatingNew {
                let teamName = newTeamName.trimmingCharacters(in: .whitespaces)
                switch mode {
                case .publicOpen:
                    _ = try await rosterService.createTeamAndJoin(leagueId: league.id, teamName: teamName, displayName: name)
                case .publicApproval:
                    _ = try await rosterService.requestToJoin(leagueId: league.id, teamId: nil, newTeamName: teamName, displayName: name)
                }
            } else if let teamId = selectedTeamId {
                switch mode {
                case .publicOpen:
                    _ = try await rosterService.joinLeaguePublic(leagueId: league.id, teamId: teamId, displayName: name)
                case .publicApproval:
                    _ = try await rosterService.requestToJoin(leagueId: league.id, teamId: teamId, newTeamName: nil, displayName: name)
                }
            }
            await onDone()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSubmitting = false
    }
}
