import Foundation
import Combine
import Supabase

@MainActor
final class StatService: ObservableObject {
    private let client = SupabaseService.client

    func fetchBoxScores(gameId: UUID) async throws -> [BoxScoreStat] {
        try await client
            .from("box_scores")
            .select()
            .eq("game_id", value: gameId)
            .execute()
            .value
    }

    /// Upserts one row per roster spot per game — safe to call repeatedly
    /// as the stat-keeper taps through the box score.
    func saveBoxScore(_ stat: BoxScoreStat) async throws {
        try await client
            .from("box_scores")
            .upsert(stat, onConflict: "game_id,roster_spot_id")
            .execute()
    }

    /// Per-league/season breakdown for a player, pulled from the
    /// `player_season_stats` view. Career totals = sum these rows client-side.
    func fetchSeasonStats(playerId: UUID) async throws -> [PlayerSeasonStats] {
        try await client
            .from("player_season_stats")
            .select()
            .eq("player_id", value: playerId)
            .execute()
            .value
    }
}

extension Array where Element == PlayerSeasonStats {
    var careerTotals: PlayerSeasonStats.Totals {
        reduce(into: PlayerSeasonStats.Totals()) { totals, season in
            totals.gamesPlayed += season.gamesPlayed
            totals.pts += season.pts
            totals.reb += season.reb
            totals.ast += season.ast
            totals.stl += season.stl
            totals.blk += season.blk
            totals.turnovers += season.turnovers
            totals.fgm += season.fgm
            totals.fga += season.fga
            totals.tpm += season.tpm
            totals.tpa += season.tpa
            totals.ftm += season.ftm
            totals.fta += season.fta
            totals.pf += season.pf
        }
    }
}

extension PlayerSeasonStats {
    struct Totals {
        var gamesPlayed = 0
        var pts = 0
        var reb = 0
        var ast = 0
        var stl = 0
        var blk = 0
        var turnovers = 0
        var fgm = 0
        var fga = 0
        var tpm = 0
        var tpa = 0
        var ftm = 0
        var fta = 0
        var pf = 0
    }
}
