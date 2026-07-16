import SwiftUI

struct LeagueDetailView: View {
    let league: League

    @StateObject private var leagueService = LeagueService()
    @State private var seasons: [Season] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isShowingNewSeason = false

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
                List(seasons) { season in
                    NavigationLink(season.name) {
                        SeasonDetailView(season: season)
                    }
                }
            }
        }
        .navigationTitle(league.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingNewSeason = true
                } label: {
                    Image(systemName: "plus")
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
