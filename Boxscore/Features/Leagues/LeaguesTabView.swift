import SwiftUI

struct LeaguesTabView: View {
    let profile: Profile?

    @EnvironmentObject private var router: AppRouter
    @StateObject private var leagueService = LeagueService()
    @State private var myLeagues: [MyLeague] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isShowingJoin = false
    @State private var isShowingSignIn = false
    @State private var openLeague: League?
    @State private var openViaCode: String?
    @State private var searchText = ""
    @State private var discovered: [League] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    // True while the guest opened the sign-in sheet specifically to join, so we
    // can bounce them straight into the join flow once they're signed in.
    @State private var joinAfterSignIn = false

    private var trimmedQuery: String { searchText.trimmingCharacters(in: .whitespaces) }

    private var filteredLeagues: [MyLeague] {
        guard !trimmedQuery.isEmpty else { return myLeagues }
        return myLeagues.filter { $0.league.name.localizedCaseInsensitiveContains(trimmedQuery) }
    }

    // Public search results, minus leagues the user is already in (shown above).
    private var discoveredResults: [League] {
        let mine = Set(myLeagues.map(\.id))
        return discovered.filter { !mine.contains($0.id) }
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
                    } else {
                        signedInContent
                    }

                    if let errorMessage {
                        ErrorBanner(message: errorMessage)
                    }
                }
                .padding(.horizontal, 18)
            }
            .refreshable { if profile != nil { await loadLeagues() } }
            .toolbar(.hidden, for: .navigationBar)
            .brandBackground()
            .navigationDestination(item: $openLeague) { league in
                LeagueDetailView(league: league, viaJoinCode: openViaCode, onChange: { await loadLeagues() })
            }
            .sheet(isPresented: $isShowingJoin) {
                JoinCodeSheet { league, code in
                    openViaCode = code
                    openLeague = league
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
            .onChange(of: searchText) { _, _ in scheduleSearch() }
            .onChange(of: router.pending) { _, _ in resolvePending() }
            .onChange(of: profile) { _, _ in resolvePending() }
            .task {
                if profile != nil { await loadLeagues() }
                resolvePending()
            }
        }
    }

    // Resolve a deep link into an opened league. Requires sign-in (RLS is
    // authenticated-only); if the viewer is a guest, prompt sign-in and the
    // profile onChange re-runs this once they're in.
    private func resolvePending() {
        guard let dest = router.pending else { return }
        guard profile != nil else { isShowingSignIn = true; return }
        Task {
            switch dest {
            case .joinCode(let code):
                if let league = try? await leagueService.findLeague(byJoinCode: code) {
                    openViaCode = code; openLeague = league
                }
            case .staffCode(let code):
                if let league = try? await leagueService.redeemStaffCode(code) {
                    openViaCode = nil; openLeague = league
                }
            case .publicLeague(let id):
                if let league = try? await leagueService.fetchLeague(id: id) {
                    openViaCode = nil; openLeague = league
                }
            }
            router.pending = nil
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let query = trimmedQuery
        guard !query.isEmpty else {
            discovered = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            do {
                let results = try await leagueService.searchPublicLeagues(query: query)
                guard !Task.isCancelled else { return }
                discovered = results
            } catch {
                discovered = []
            }
            isSearching = false
        }
    }

    @ViewBuilder
    private var signedInContent: some View {
        SearchField(text: $searchText, placeholder: "Search leagues...")

        // My leagues (or a prompt when there are none and no active search).
        if !filteredLeagues.isEmpty {
            SectionHeaderText("My leagues")
            ForEach(filteredLeagues) { entry in
                NavigationLink {
                    LeagueDetailView(league: entry.league, onChange: { await loadLeagues() })
                } label: {
                    LeagueCard(entry: entry)
                }
                .buttonStyle(.plain)
            }
        } else if trimmedQuery.isEmpty {
            emptyState
        }

        // Discover public leagues — browse anyone's league read-only, no code needed.
        if !trimmedQuery.isEmpty {
            SectionHeaderText("Discover public leagues")
            if isSearching {
                HStack { Spacer(); ProgressView(); Spacer() }.padding(.vertical, 12)
            } else if discoveredResults.isEmpty {
                Text("No public leagues match \u{201c}\(trimmedQuery)\u{201d}. Private leagues stay code-only.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .brandCard()
            } else {
                ForEach(discoveredResults) { league in
                    NavigationLink {
                        LeagueDetailView(league: league)
                    } label: {
                        DiscoverCard(league: league)
                    }
                    .buttonStyle(.plain)
                }
            }
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

/// A public league found via search — browse-only, so it's badged "public"
/// rather than showing a personal relationship.
private struct DiscoverCard: View {
    let league: League

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                Text("PUBLIC")
                    .font(.system(size: 10, weight: .black).width(.condensed))
                    .kerning(1.2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(league.format.label)
                    .font(.system(size: 10, weight: .black).width(.condensed))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            Text(league.name)
                .font(.display(24))
                .foregroundStyle(.primary)
        }
        .brandCard()
    }
}
