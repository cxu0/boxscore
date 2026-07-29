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

    /// Totals + games played for a single roster spot — used for a placeholder
    /// player's profile, since their stats aren't aggregated by player id.
    func fetchRosterSpotStats(rosterSpotId: UUID) async throws -> (totals: BoxScoreStat.Totals, gamesPlayed: Int) {
        let lines: [BoxScoreStat] = try await client
            .from("box_scores")
            .select()
            .eq("roster_spot_id", value: rosterSpotId)
            .execute()
            .value
        var totals = BoxScoreStat.Totals()
        for line in lines { totals.add(line) }
        return (totals, lines.count)
    }

    /// All box scores for a set of games — used to build the league leaderboard.
    func fetchBoxScores(gameIds: [UUID]) async throws -> [BoxScoreStat] {
        guard !gameIds.isEmpty else { return [] }
        return try await client
            .from("box_scores")
            .select()
            .in("game_id", values: gameIds.map(\.uuidString))
            .execute()
            .value
    }

    /// The player's most recent games with their line and the result, built
    /// from box scores joined to their game and the player's team. Opponent
    /// team names are resolved in a second lookup.
    func fetchRecentGames(playerId: UUID, limit: Int = 5) async throws -> [RecentGame] {
        struct Row: Decodable {
            let pts: Int
            let reb: Int
            let ast: Int
            let games: GameRow
            let rosterSpots: SpotRow

            struct GameRow: Decodable {
                let id: UUID
                let homeTeamId: UUID
                let awayTeamId: UUID
                let homeScore: Int?
                let awayScore: Int?
                let status: String
                let scheduledAt: Date
            }
            struct SpotRow: Decodable { let teamId: UUID }
        }

        let rows: [Row] = try await client
            .from("box_scores")
            .select("pts, reb, ast, games!inner(id, home_team_id, away_team_id, home_score, away_score, status, scheduled_at), roster_spots!inner(team_id, player_id)")
            .eq("roster_spots.player_id", value: playerId)
            .order("scheduled_at", ascending: false, referencedTable: "games")
            .limit(limit)
            .execute()
            .value

        // Resolve opponent team names in one lookup.
        let opponentIds = Set(rows.map { $0.games.homeTeamId == $0.rosterSpots.teamId ? $0.games.awayTeamId : $0.games.homeTeamId })
        var names: [UUID: String] = [:]
        if !opponentIds.isEmpty {
            let teams: [Team] = try await client
                .from("teams")
                .select()
                .in("id", values: opponentIds.map(\.uuidString))
                .execute()
                .value
            for team in teams { names[team.id] = team.name }
        }

        return rows.map { row in
            let isHome = row.games.homeTeamId == row.rosterSpots.teamId
            let oppId = isHome ? row.games.awayTeamId : row.games.homeTeamId
            let result: RecentGame.GameResult
            var scoreLine = "—"
            if row.games.status == "final", let hs = row.games.homeScore, let as_ = row.games.awayScore {
                let myScore = isHome ? hs : as_
                let oppScore = isHome ? as_ : hs
                result = myScore > oppScore ? .win : .loss
                scoreLine = "\(myScore)–\(oppScore)"
            } else {
                result = .pending
            }
            return RecentGame(
                id: row.games.id,
                opponentName: names[oppId] ?? "TBD",
                isHome: isHome,
                result: result,
                scoreLine: scoreLine,
                pts: row.pts, reb: row.reb, ast: row.ast,
                date: row.games.scheduledAt
            )
        }
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
