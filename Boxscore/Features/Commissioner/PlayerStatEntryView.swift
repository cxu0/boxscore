import SwiftUI

/// Fast tap-based entry for one player's box score line in one game.
/// Every tap updates local state immediately; changes are auto-saved to
/// Supabase in the background with a short debounce.
struct PlayerStatEntryView: View {
    let game: Game
    let rosterSpot: RosterSpot

    @StateObject private var statService = StatService()
    @State private var stat: BoxScoreStat
    @State private var isLoading = true
    @State private var saveTask: Task<Void, Never>?
    @State private var errorMessage: String?

    init(game: Game, rosterSpot: RosterSpot) {
        self.game = game
        self.rosterSpot = rosterSpot
        _stat = State(initialValue: .empty(gameId: game.id, rosterSpotId: rosterSpot.id))
    }

    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 12)]

    var body: some View {
        ScrollView {
            // Running header: player name + live point total.
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(rosterSpot.displayName.uppercased())
                        .font(.display(26))
                    Text("Auto-saves as you tap")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(stat.pts)")
                        .font(.display(40))
                        .monospacedDigit()
                        .foregroundStyle(Brand.orange)
                        .contentTransition(.numericText())
                    Text("PTS")
                        .font(.system(size: 12, weight: .black).width(.condensed))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)

            if let errorMessage {
                ErrorBanner(message: errorMessage)
            }
            LazyVGrid(columns: columns, spacing: 10) {
                StatStepper(label: "PTS", value: $stat.pts)
                StatStepper(label: "REB", value: $stat.reb)
                StatStepper(label: "AST", value: $stat.ast)
                StatStepper(label: "STL", value: $stat.stl)
                StatStepper(label: "BLK", value: $stat.blk)
                StatStepper(label: "TO", value: $stat.turnovers)
                StatStepper(label: "FGM", value: $stat.fgm)
                StatStepper(label: "FGA", value: $stat.fga)
                StatStepper(label: "3PM", value: $stat.tpm)
                StatStepper(label: "3PA", value: $stat.tpa)
                StatStepper(label: "FTM", value: $stat.ftm)
                StatStepper(label: "FTA", value: $stat.fta)
                StatStepper(label: "PF", value: $stat.pf)
            }
            .padding()
        }
        .navigationTitle("Box Score")
        .navigationBarTitleDisplayMode(.inline)
        .brandBackground()
        .overlay { if isLoading { LoadingView() } }
        .task { await loadExisting() }
        .onChange(of: stat) { _, newValue in scheduleSave(newValue) }
        .onDisappear { saveTask?.cancel(); Task { await save(stat) } }
    }

    private func loadExisting() async {
        isLoading = true
        do {
            if let existing = try await statService.fetchBoxScores(gameId: game.id)
                .first(where: { $0.rosterSpotId == rosterSpot.id }) {
                stat = existing
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func scheduleSave(_ newValue: BoxScoreStat) {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await save(newValue)
        }
    }

    private func save(_ value: BoxScoreStat) async {
        do {
            try await statService.saveBoxScore(value)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
