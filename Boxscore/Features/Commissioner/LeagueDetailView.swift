import SwiftUI

struct LeagueDetailView: View {
    let league: League

    @EnvironmentObject private var auth: AuthService
    @StateObject private var leagueService = LeagueService()
    @State private var seasons: [Season] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isShowingNewSeason = false

    private var isOwner: Bool { auth.profile?.id == league.ownerId }

    var body: some View {
        Group {
            if isLoading {
                LoadingView()
            } else if seasons.isEmpty {
                EmptyStateView(
                    systemImage: "calendar",
                    title: "No Seasons Yet",
                    message: "Add a season to start adding teams and games."
                )
            } else {
                List {
                    if isOwner {
                        Section {
                            JoinCodeCard(league: league)
                        }
                    }
                    ForEach(seasons) { season in
                        NavigationLink(season.name) {
                            SeasonDetailView(season: season, isOwner: isOwner)
                        }
                    }
                }
            }
        }
        .navigationTitle(league.name)
        .toolbar {
            if isOwner {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingNewSeason = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingNewSeason) {
            NewSeasonSheet { name, start, end in
                await createSeason(name: name, start: start, end: end)
            }
        }
        .task { await loadSeasons() }
        .refreshable { await loadSeasons() }
    }

    private func loadSeasons() async {
        isLoading = true
        do {
            seasons = try await leagueService.fetchSeasons(leagueId: league.id)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func createSeason(name: String, start: Date, end: Date) async {
        do {
            let season = try await leagueService.createSeason(name: name, leagueId: league.id, startDate: start, endDate: end)
            seasons.insert(season, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct JoinCodeCard: View {
    let league: League

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Join Code")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text(league.joinCode)
                    .font(.title2.monospaced().bold())
                Spacer()
                ShareLink(item: "Join my Boxscore league \"\(league.name)\"! Open the app, tap Join a League, and enter code \(league.joinCode).") {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
            Text("Share this once — anyone with the code can pick a team and add themselves.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct NewSeasonSheet: View {
    let onCreate: (String, Date, Date) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var start = Date()
    @State private var end = Date().addingTimeInterval(60 * 60 * 24 * 90)

    var body: some View {
        NavigationStack {
            Form {
                TextField("Season Name", text: $name)
                DatePicker("Start Date", selection: $start, displayedComponents: .date)
                DatePicker("End Date", selection: $end, displayedComponents: .date)
            }
            .navigationTitle("New Season")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            await onCreate(name, start, end)
                            dismiss()
                        }
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}
