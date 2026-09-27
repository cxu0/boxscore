import SwiftUI

/// Opens the right profile for a roster spot: a claimed player gets their full
/// read-only cross-league profile; a placeholder gets an in-league summary.
struct PlayerProfileLoader: View {
    let rosterSpot: RosterSpot

    @EnvironmentObject private var auth: AuthService
    @State private var profile: Profile?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let profile {
                ProfileView(profile: profile, isSelf: false)
            } else if isLoading {
                LoadingView()
            } else if rosterSpot.playerId == nil {
                PlaceholderProfileView(rosterSpot: rosterSpot)
            } else {
                // Claimed spot but the profile couldn't load.
                VStack(spacing: 8) {
                    Text(rosterSpot.displayName).font(.display(28))
                    if let errorMessage { ErrorBanner(message: errorMessage) }
                }
                .padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .brandBackground()
        .task { await load() }
    }

    private func load() async {
        guard let playerId = rosterSpot.playerId else { isLoading = false; return }
        do {
            profile = try await auth.fetchProfile(id: playerId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

/// A player added by name who hasn't joined the app. Their record is just this
/// league; once they claim the spot this becomes a full cross-league profile.
struct PlaceholderProfileView: View {
    let rosterSpot: RosterSpot

    @EnvironmentObject private var auth: AuthService
    @StateObject private var statService = StatService()
    @StateObject private var rosterService = RosterService()
    @State private var totals = BoxScoreStat.Totals()
    @State private var gamesPlayed = 0
    @State private var isLoading = true
    @State private var claimState: ClaimState = .idle

    enum ClaimState { case idle, sending, sent, failed }

    private var initials: String {
        let parts = rosterSpot.displayName.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "BX" : String(letters).uppercased()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                VStack(alignment: .leading, spacing: 18) {
                    if isLoading {
                        LoadingView().padding(.top, 20)
                    } else if gamesPlayed == 0 {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No stats yet")
                                .font(.system(size: 16, weight: .bold))
                            Text("This player hasn't logged any games in this league.")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .brandCard(padding: 18)
                    } else {
                        statsSection
                    }
                    unclaimedNote
                    if auth.profile != nil {
                        claimButton
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
        }
        .ignoresSafeArea(edges: .top)
        .task { await load() }
        .brandBackground()
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Color(white: 0.18), Color(white: 0.04)], startPoint: .top, endPoint: .bottom)
            Text(initials)
                .font(.display(150))
                .foregroundStyle(Brand.orange.opacity(0.16))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 8)
                .offset(y: -16)
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    Circle().fill(.white.opacity(0.1)).frame(width: 76, height: 76)
                    Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1).frame(width: 76, height: 76)
                    Text(initials).font(.display(28)).foregroundStyle(.white.opacity(0.85))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("NOT ON THE APP YET")
                        .font(.system(size: 9, weight: .black).width(.condensed))
                        .kerning(1.5)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                    Text(rosterSpot.displayName)
                        .font(.display(38))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
            .padding(.top, 60)
        }
        .frame(minHeight: 300)
        .clipped()
    }

    private var statsSection: some View {
        let gp = max(gamesPlayed, 1)
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeaderText("This league")
            HStack(spacing: 8) {
                BigStatTile(value: "\(totals.pts)", label: "POINTS")
                BigStatTile(value: "\(totals.reb)", label: "REBOUNDS")
            }
            HStack(spacing: 8) {
                BigStatTile(value: "\(totals.ast)", label: "ASSISTS")
                BigStatTile(value: "\(gamesPlayed)", label: "GAMES")
            }
            HStack(spacing: 0) {
                avg("PPG", totals.pts, gp)
                avg("RPG", totals.reb, gp)
                avg("APG", totals.ast, gp)
                avg("SPG", totals.stl, gp)
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func avg(_ label: String, _ total: Int, _ gp: Int) -> some View {
        VStack(spacing: 3) {
            Text(String(format: "%.1f", Double(total) / Double(gp)))
                .font(.display(22)).foregroundStyle(.white)
            Text(label).font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
    }

    private var unclaimedNote: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 18)).foregroundStyle(Brand.orange)
            Text("When this player joins the app and claims their spot, this becomes their full career profile across every league.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .brandCard(padding: 14)
    }

    @ViewBuilder
    private var claimButton: some View {
        switch claimState {
        case .sent:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Request sent — the organizer will confirm it's you.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            .brandCard(padding: 14)
        default:
            Button {
                Task { await claim() }
            } label: {
                if claimState == .sending {
                    ProgressView().tint(.white)
                } else {
                    Text("That's me — claim this spot")
                }
            }
            .buttonStyle(BrandPrimaryButtonStyle())
            .disabled(claimState == .sending)
            if claimState == .failed {
                Text("Couldn't send the request. It may already be claimed.")
                    .font(.system(size: 12)).foregroundStyle(.red)
            }
        }
    }

    private func claim() async {
        claimState = .sending
        do {
            _ = try await rosterService.requestClaim(rosterSpotId: rosterSpot.id)
            claimState = .sent
        } catch {
            claimState = .failed
        }
    }

    private func load() async {
        do {
            let result = try await statService.fetchRosterSpotStats(rosterSpotId: rosterSpot.id)
            totals = result.totals
            gamesPlayed = result.gamesPlayed
        } catch {
            // Leave zeros on failure.
        }
        isLoading = false
    }
}
