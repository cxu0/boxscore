import SwiftUI

struct TeamDetailView: View {
    let team: Team

    @StateObject private var rosterService = RosterService()
    @State private var roster: [RosterSpot] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isShowingAddPlayer = false

    var body: some View {
        Group {
            if isLoading {
                LoadingView()
            } else if roster.isEmpty {
                EmptyStateView(
                    systemImage: "person.3",
                    title: "No Players Yet",
                    message: "Add a roster spot, then share its invite code with the player."
                )
            } else {
                List(roster) { spot in
                    RosterRow(spot: spot)
                }
            }
        }
        .navigationTitle(team.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingAddPlayer = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isShowingAddPlayer) {
            NewRosterSpotSheet { name in await addPlayer(name: name) }
        }
        .task { await loadRoster() }
        .refreshable { await loadRoster() }
    }

    private func loadRoster() async {
        isLoading = true
        do {
            roster = try await rosterService.fetchRoster(teamId: team.id)
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
}

private struct RosterRow: View {
    let spot: RosterSpot

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(spot.displayName)
                if let code = spot.inviteCode {
                    Text("Invite code: \(code)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if spot.playerId != nil {
                Label("Claimed", systemImage: "checkmark.seal.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.green)
            }
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
