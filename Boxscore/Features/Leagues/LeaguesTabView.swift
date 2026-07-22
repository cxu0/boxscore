import SwiftUI

struct LeaguesTabView: View {
    let profile: Profile?

    @StateObject private var leagueService = LeagueService()
    @State private var myLeagues: [MyLeague] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isShowingJoin = false
    @State private var isShowingSignIn = false
    @State private var searchText = ""
    // True while the guest opened the sign-in sheet specifically to join, so we
    // can bounce them straight into the join flow once they're signed in.
    @State private var joinAfterSignIn = false

    private var filteredLeagues: [MyLeague] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return myLeagues }
        return myLeagues.filter { $0.league.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("LEAGUES")
                            .font(.display(38))
                        Spacer()
                        Button {
                            startJoin()
                        } label: {
                            Label("Join", systemImage: "person.badge.plus")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Brand.orange)
                        }
                    }
                    .padding(.top, 8)

                    if profile == nil {
                        guestState
                    } else if isLoading {
                        LoadingView().padding(.top, 40)
                    } else if myLeagues.isEmpty {
                        emptyState
                    } else {
                        SearchField(text: $searchText, placeholder: "Search leagues...")
                        SectionHeaderText("My leagues")
                        if filteredLeagues.isEmpty {
                            Text("No leagues match \u{201c}\(searchText)\u{201d}.")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .brandCard()
                        } else {
                            ForEach(filteredLeagues) { entry in
                                NavigationLink {
                                    LeagueDetailView(league: entry.league)
                                } label: {
                                    LeagueCard(entry: entry)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if let errorMessage {
                        ErrorBanner(message: errorMessage)
                    }
                }
                .padding(.horizontal, 18)
            }
            .refreshable { if profile != nil { await loadLeagues() } }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isShowingJoin) {
                if let profile {
                    NavigationStack {
                        JoinLeagueView(profile: profile) { await loadLeagues() }
                    }
                }
            }
            .sheet(isPresented: $isShowingSignIn) {
                NavigationStack {
                    SignInPromptView(message: "Sign in to join a league and start tracking your stats.")
                }
            }
            // When the guest signs in, `profile` flips non-nil — close the
            // sign-in sheet and drop them into the join flow they were after.
            .onChange(of: profile) { _, newProfile in
                guard newProfile != nil else { return }
                if isShowingSignIn {
                    isShowingSignIn = false
                    if joinAfterSignIn {
                        joinAfterSignIn = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            isShowingJoin = true
                        }
                    }
                }
                Task { await loadLeagues() }
            }
            .task { if profile != nil { await loadLeagues() } }
        }
    }

    // Guests can browse the tab; joining is the identity moment.
    private var guestState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Find your league")
                .font(.system(size: 16, weight: .bold))
            Text("Got a join code from your organizer? Join a league to add yourself to a team and start your career stats.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Button {
                startJoin()
            } label: {
                Text("Join a League")
            }
            .buttonStyle(BrandPrimaryButtonStyle())
            .padding(.top, 6)
        }
        .brandCard(padding: 18)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No leagues yet")
                .font(.system(size: 16, weight: .bold))
            Text("Create a league from the Create tab, or join one with a code from your organizer.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Button {
                startJoin()
            } label: {
                Text("Join a League")
            }
            .buttonStyle(BrandPrimaryButtonStyle())
            .padding(.top, 6)
        }
        .brandCard(padding: 18)
    }

    private func startJoin() {
        if profile == nil {
            joinAfterSignIn = true
            isShowingSignIn = true
        } else {
            isShowingJoin = true
        }
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
                Text(entry.league.format.label)
                    .font(.system(size: 10, weight: .black).width(.condensed))
                    .foregroundStyle(.secondary)
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
