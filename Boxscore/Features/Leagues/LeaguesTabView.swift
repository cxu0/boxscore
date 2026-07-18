import SwiftUI

struct LeaguesTabView: View {
    let profile: Profile?

    @StateObject private var leagueService = LeagueService()
    @State private var myLeagues: [MyLeague] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isShowingJoin = false

    var body: some View {
        NavigationStack {
            Group {
                if profile == nil {
                    SignInPromptView(message: "Sign in to see the leagues you run or play in.")
                } else if isLoading {
                    LoadingView()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("LEAGUES")
                                    .font(.display(38))
                                Spacer()
                                Button {
                                    isShowingJoin = true
                                } label: {
                                    Label("Join", systemImage: "person.badge.plus")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(Brand.orange)
                                }
                            }
                            .padding(.top, 8)

                            if myLeagues.isEmpty {
                                emptyState
                            } else {
                                SectionHeaderText("My leagues")
                                ForEach(myLeagues) { entry in
                                    NavigationLink {
                                        LeagueDetailView(league: entry.league)
                                    } label: {
                                        LeagueCard(entry: entry)
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
                    .refreshable { await loadLeagues() }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isShowingJoin) {
                if let profile {
                    NavigationStack {
                        JoinLeagueView(profile: profile) { await loadLeagues() }
                    }
                }
            }
            .task { if profile != nil { await loadLeagues() } }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No leagues yet")
                .font(.system(size: 16, weight: .bold))
            Text("Create a league from the Create tab, or join one with a code from your organizer.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Button {
                isShowingJoin = true
            } label: {
                Text("Join a League")
            }
            .buttonStyle(BrandPrimaryButtonStyle())
            .padding(.top, 6)
        }
        .brandCard(padding: 18)
    }

    private func loadLeagues() async {
        guard let profile else { return }
        isLoading = true
        do {
            myLeagues = try await leagueService.fetchMyLeagues(userId: profile.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct LeagueCard: View {
    let entry: MyLeague

    private var isOwner: Bool { entry.relationship == .owner }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(isOwner ? Brand.orange : .blue)
                    .frame(width: 8, height: 8)
                Text(isOwner ? "ORGANIZER" : "PLAYER")
                    .font(.system(size: 10, weight: .black).width(.condensed))
                    .kerning(1.2)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            Text(entry.league.name)
                .font(.display(24))
                .foregroundStyle(.primary)
        }
        .brandCard()
    }
}
