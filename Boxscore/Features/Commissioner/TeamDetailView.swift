import SwiftUI

struct TeamDetailView: View {
    let team: Team
    let isOwner: Bool

    @StateObject private var rosterService = RosterService()
    @State private var roster: [RosterSpot] = []
    @State private var pendingRequests: [ClaimRequest] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isShowingAddPlayer = false
    @State private var claimedSpotIds: Set<UUID> = []

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
                        }
                    }
                    if let errorMessage {
                        ErrorBanner(message: errorMessage)
                    }
                }
            }
        }
        .navigationTitle(team.name)
        .toolbar {
            if isOwner {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingAddPlayer = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingAddPlayer) {
            NewRosterSpotSheet { name in await addPlayer(name: name) }
        }
        .task { await loadAll() }
        .refreshable { await loadAll() }
    }

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
