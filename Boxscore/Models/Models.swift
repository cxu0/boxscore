import Foundation

enum UserRole: String, Codable {
    case commissioner
    case player
}

struct Profile: Codable, Identifiable, Equatable {
    let id: UUID
    var role: UserRole
    var displayName: String
    var email: String
    var createdAt: Date?
}

struct League: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var ownerId: UUID
    var createdAt: Date?
}

struct Season: Codable, Identifiable, Equatable {
    let id: UUID
    var leagueId: UUID
    var name: String
    var startDate: Date?
    var endDate: Date?
    var createdAt: Date?
}

struct Team: Codable, Identifiable, Equatable {
    let id: UUID
    var seasonId: UUID
    var name: String
    var createdAt: Date?
}

struct RosterSpot: Codable, Identifiable, Equatable {
    let id: UUID
    var teamId: UUID
    var displayName: String
    var playerId: UUID?
    var inviteCode: String?
    var createdAt: Date?
}

enum GameStatus: String, Codable {
    case scheduled
    case final
}

struct Game: Codable, Identifiable, Equatable {
    let id: UUID
    var seasonId: UUID
    var homeTeamId: UUID
    var awayTeamId: UUID
    var scheduledAt: Date
    var status: GameStatus
    var createdAt: Date?
}

/// Mirrors `box_scores`. Every count defaults to 0 so a fresh row can be
/// upserted before the stat-keeper has entered anything for that player.
struct BoxScoreStat: Codable, Identifiable, Equatable {
    let id: UUID
    var gameId: UUID
    var rosterSpotId: UUID
    var pts: Int
    var reb: Int
    var ast: Int
    var stl: Int
    var blk: Int
    var turnovers: Int
    var fgm: Int
    var fga: Int
    var tpm: Int
    var tpa: Int
    var ftm: Int
    var fta: Int
    var pf: Int

    static func empty(gameId: UUID, rosterSpotId: UUID) -> BoxScoreStat {
        BoxScoreStat(
            id: UUID(), gameId: gameId, rosterSpotId: rosterSpotId,
            pts: 0, reb: 0, ast: 0, stl: 0, blk: 0, turnovers: 0,
            fgm: 0, fga: 0, tpm: 0, tpa: 0, ftm: 0, fta: 0, pf: 0
        )
    }
}

/// Mirrors the `player_season_stats` view — one row per player/league/season.
struct PlayerSeasonStats: Codable, Identifiable, Equatable {
    var id: String { "\(leagueId)-\(seasonId)" }
    var playerId: UUID
    var leagueId: UUID
    var leagueName: String
    var seasonId: UUID
    var seasonName: String
    var gamesPlayed: Int
    var pts: Int
    var reb: Int
    var ast: Int
    var stl: Int
    var blk: Int
    var turnovers: Int
    var fgm: Int
    var fga: Int
    var tpm: Int
    var tpa: Int
    var ftm: Int
    var fta: Int
    var pf: Int
}
