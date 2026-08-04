import SwiftUI

/// Owner-only: share the league's stat-keeper code, rotate it, and remove
/// people who currently have stat-keeping rights.
struct StatKeepersView: View {
    let league: League

    @Environment(\.dismiss) private var dismiss
    @StateObject private var leagueService = LeagueService()
    @State private var code: String
    @State private var staff: [LeagueStaff] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    init(league: League) {
        self.league = league
        _code = State(initialValue: league.staffCode)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("STAT KEEPERS")
                        .font(.display(34))
                        .padding(.top, 8)
                    Text("Anyone with this code can enter box scores and final scores for your league — but not edit teams, games, or settings. Share it only with people you trust to keep stats.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)

                    codeCard

                    SectionHeaderText("Current stat keepers")
                    if isLoading {
                        LoadingView().padding(.top, 12)
                    } else if staff.isEmpty {
                        Text("No stat keepers yet.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .brandCard()
                    } else {
                        ForEach(staff) { member in
                            HStack {
                                Text(member.name).font(.system(size: 15, weight: .bold))
                                Spacer()
                                Button {
                                    Task { await remove(member) }
                                } label: {
                                    Text("Remove")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            .brandCard(padding: 14)
                        }
                    }

                    if let errorMessage { ErrorBanner(message: errorMessage) }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
            .navigationTitle("Stat Keepers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { await load() }
        }
    }

    private var codeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeaderText("Stat-keeper code")
            HStack {
                Text(code)
                    .font(.display(34))
                    .kerning(4)
                    .foregroundStyle(Brand.orange)
                Spacer()
                ShareLink(item: AppConfig.staffURL(code: code),
                          message: Text("Keep stats for my Boxscore league \"\(league.name)\": tap the link, or enter code \(code) in the app.")) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 36)
                        .background(Brand.orange, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            Button {
                Task { await regenerate() }
            } label: {
                Label("Regenerate code", systemImage: "arrow.clockwise")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Brand.orange)
            }
            .buttonStyle(.plain)
            Text("Regenerating invalidates the old code. People already added keep their access.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .brandCard(padding: 16)
    }

    private func load() async {
        do {
            staff = try await leagueService.fetchStaff(leagueId: league.id)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func regenerate() async {
        do {
            code = try await leagueService.regenerateStaffCode(leagueId: league.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func remove(_ member: LeagueStaff) async {
        do {
            try await leagueService.removeStaff(id: member.id)
            staff.removeAll { $0.id == member.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
