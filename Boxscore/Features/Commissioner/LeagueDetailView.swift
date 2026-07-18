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
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(league.name.uppercased())
                            .font(.display(32))
                            .padding(.top, 4)

                        if isOwner {
                            JoinCodeCard(league: league)
                        }

                        HStack {
                            SectionHeaderText("Seasons")
                            Spacer()
                            if isOwner {
                                Button {
                                    isShowingNewSeason = true
                                } label: {
                                    Label("Add", systemImage: "plus")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(Brand.orange)
                                }
                            }
                        }

                        if seasons.isEmpty {
                            Text("No seasons yet. Add one to start adding teams and games.")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .brandCard()
                        } else {
                            ForEach(seasons) { season in
                                NavigationLink {
                                    SeasonDetailView(season: season, isOwner: isOwner)
                                } label: {
                                    HStack {
                                        Text(season.name)
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .brandCard()
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if let errorMessage {
                            ErrorBanner(message: errorMessage)
                        }
                    }
                    .padding(.horizontal, 18)
                }
            }
        }
        .navigationTitle(league.name)
        .navigationBarTitleDisplayMode(.inline)
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
            errorMessage = nil
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

/// Bold, shareable join code — the league's front door.
private struct JoinCodeCard: View {
    let league: League

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderText("Join code")
            HStack {
                Text(league.joinCode)
                    .font(.display(34))
                    .kerning(4)
                    .foregroundStyle(Brand.orange)
                Spacer()
                ShareLink(item: "Join my Boxscore league \"\(league.name)\"! Open the app, tap Join a League, and enter code \(league.joinCode).") {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Brand.orange, in: Capsule())
                }
            }
            Text("Share this once — anyone with the code can pick a team and add themselves.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .brandCard(padding: 16)
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
