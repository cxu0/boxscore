import SwiftUI

struct TeamDetailView: View {
    let team: Team
    let isOwner: Bool
    var onChange: (() async -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @StateObject private var rosterService = RosterService()
    @StateObject private var leagueService = LeagueService()

    @State private var teamName: String
    @State private var roster: [RosterSpot] = []
    @State private var pendingRequests: [ClaimRequest] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isShowingAddPlayer = false
    @State private var claimedSpotIds: Set<UUID> = []

    // Edit / fix state
    @State private var isRenamingTeam = false
    @State private var renameTeamText = ""
    @State private var isConfirmingDeleteTeam = false
    @State private var spotRenaming: RosterSpot?
    @State private var renameSpotText = ""
    @State private var spotPendingDelete: RosterSpot?

    init(team: Team, isOwner: Bool, onChange: (() async -> Void)? = nil) {
        self.team = team
        self.isOwner = isOwner
        self.onChange = onChange
        _teamName = State(initialValue: team.name)
    }

    var body: some View {
        Group {
            if isLoading {
                LoadingView()
            } else if roster.isEmpty {
                EmptyStateView(
                    systemImage: "person.3",
                    title: "No Players Yet",
                    message: "Add a roster spot, or share the league's join code so players can add themselves."
                )
            } else {
                List {
                    if isOwner && !pendingRequests.isEmpty {
                        Section("Pending Requests") {
                            ForEach(pendingRequests) { request in
                                PendingRequestRow(
                                    request: request,
                                    onApprove: { await approve(request) },
                                    onDeny: { await deny(request) }
                                )
                            }
                        }
                    }
                    Section {
                        ForEach(roster) { spot in
                            RosterRow(
                                spot: spot,
                                isOwner: isOwner,
                                hasClaimed: claimedSpotIds.contains(spot.id),
                                onClaim: { await claim(spot) }
                            )
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if isOwner {
                                    Button(role: .destructive) {
                                        spotPendingDelete = spot
                                    } label: { Label("Remove", systemImage: "trash") }
                                    Button {
                                        renameSpotText = spot.displayName
                                        spotRenaming = spot
                                    } label: { Label("Rename", systemImage: "pencil") }
                                    .tint(.blue)
                                }
                            }
                        }
                    }
                    if let errorMessage {
                        ErrorBanner(message: errorMessage)
                    }
                }
            }
        }
        .navigationTitle(teamName)
        .toolbar {
            if isOwner {
                ToolbarItem(placement: .primaryAction) {
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

    // MARK: Data

    private func loadAll() async {
        isLoading = true
        do {
            roster = try await rosterService.fetchRoster(teamId: team.id)
            if isOwner {
                pendingRequests = try await rosterService.fetchPendingClaimRequests(teamId: team.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func addPlayer(name: String) async {
        do {
            let spot = try await rosterService.addRosterSpot(teamId: team.id, displayName: name)
            roster.append(spot)
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

    private func claim(_ spot: RosterSpot) async {
        do {
            _ = try await rosterService.requestClaim(rosterSpotId: spot.id)
            claimedSpotIds.insert(spot.id)
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

private struct RosterRow: View {
    let spot: RosterSpot
    let isOwner: Bool
    let hasClaimed: Bool
    let onClaim: () async -> Void

    var body: some View {
        HStack {
            Text(spot.displayName)
            Spacer()
            if spot.playerId != nil {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            } else if !isOwner {
                if hasClaimed {
                    Text("Request sent")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button("That's me") {
                        Task { await onClaim() }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
            }
        }
    }
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
