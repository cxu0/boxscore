import Foundation

struct Profile: Codable, Identifiable, Equatable {
    let id: UUID
    var displayName: String
    var email: String
    var avatarUrl: String?
    var createdAt: Date?
}

enum LeagueFormat: String, Codable, CaseIterable {
    case fiveOnFive = "5v5"
    case threeOnThree = "3v3"
    case rec

    var label: String {
        switch self {
        case .fiveOnFive: return "5v5"
        case .threeOnThree: return "3v3"
        case .rec: return "Rec"
        }
    }
}

enum JoinPolicy: String, Codable {
    case open
    case approval
}

struct League: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var ownerId: UUID
    var isPublic: Bool
    var joinCode: String
    var format: LeagueFormat
    var staffCode: String
    var allowPlayerTeams: Bool
    var maxTeams: Int?
    var maxRosterSize: Int?
    var joinPolicy: JoinPolicy
    var createdAt: Date?
}

/// A stat keeper on a league, with their name embedded via PostgREST select.
struct LeagueStaff: Codable, Identifiable, Equatable {
    let id: UUID
    var leagueId: UUID
    var profileId: UUID
    var profiles: Ref?
    struct Ref: Codable, Equatable { let displayName: String }
    var name: String { profiles?.displayName ?? "Stat keeper" }
}

/// A request to join a public (approval-gated) league, with requester + team
/// names embedded for the owner's review UI.
struct JoinRequest: Codable, Identifiable, Equatable {
    let id: UUID
    var leagueId: UUID
    var requestedBy: UUID
    var teamId: UUID?
    var newTeamName: String?
    var displayName: String
    var status: ClaimRequestStatus
    var createdAt: Date?
    var profiles: RequesterRef?
    var teams: TeamRef?

    struct RequesterRef: Codable, Equatable { let displayName: String }
    struct TeamRef: Codable, Equatable { let name: String }

    var requesterName: String { profiles?.displayName ?? displayName }
    var teamLabel: String { teams?.name ?? newTeamName ?? "a team" }
}

/// A league tagged with how the current user relates to it — used by the
/// "My Leagues" list, which merges owned and joined leagues into one feed.
struct MyLeague: Identifiable, Equatable {
    enum Role {
        case owner
        case staff
        case player
    }
    let league: League
    /// A user can hold more than one role in a league (e.g. player + stat keeper).
    var roles: Set<Role>

    var id: UUID { league.id }

    /// Badge text, most-privileged role first.
    var label: String {
        if roles.contains(.owner) { return "ORGANIZER" }
        if roles.contains(.staff) && roles.contains(.player) { return "PLAYER · STAT KEEPER" }
        if roles.contains(.staff) { return "STAT KEEPER" }
        return "PLAYER"
    }
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
    var createdAt: Date?
    /// The email the organizer attached to this spot. RLS only returns it to
    /// the league owner; everyone else sees nil.
    var rosterSpotEmails: EmailRef?
    struct EmailRef: Codable, Equatable { let email: String }

    var inviteEmail: String? { rosterSpotEmails?.email }
}

/// One row of a roster import: team, player name, and (optional) email.
struct RosterImportRow: Codable, Equatable, Identifiable {
    var team: String
    var name: String
    var email: String?
    var id: String { "\(team)|\(name)|\(email ?? "")" }
}

struct RosterImportResult: Decodable, Equatable {
    let teamsCreated: Int
    let playersAdded: Int
    let alreadyJoined: Int
    let skipped: Int
}

enum ClaimRequestStatus: String, Codable {
    case pending
    case approved
    case denied
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
    var homeScore: Int?
    var awayScore: Int?
    var createdAt: Date?

    var hasResult: Bool { homeScore != nil && awayScore != nil }
}

/// One team's computed standing, derived client-side from final game scores.
struct TeamStanding: Identifiable, Equatable {
    let team: Team
    var wins: Int
    var losses: Int
    /// e.g. "W5", "L1" — most recent result streak.
    var streak: String

    var id: UUID { team.id }
    var record: String { "\(wins)-\(losses)" }
    var winPct: Double {
        let total = wins + losses
        return total == 0 ? 0 : Double(wins) / Double(total)
    }
}

/// One entry in a player's recent-games list on their profile.
struct RecentGame: Identifiable, Equatable {
    let id: UUID
    var opponentName: String
    var isHome: Bool
    var result: GameResult
    var scoreLine: String
    var pts: Int
    var reb: Int
    var ast: Int
    var date: Date

    enum GameResult { case win, loss, pending }
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

    /// Running team totals, summed across a roster's box score lines.
    struct Totals {
        var pts = 0, reb = 0, ast = 0, stl = 0, blk = 0, turnovers = 0
        var fgm = 0, fga = 0, tpm = 0, tpa = 0, ftm = 0, fta = 0, pf = 0

        mutating func add(_ l: BoxScoreStat) {
            pts += l.pts; reb += l.reb; ast += l.ast; stl += l.stl; blk += l.blk
            turnovers += l.turnovers; fgm += l.fgm; fga += l.fga; tpm += l.tpm
            tpa += l.tpa; ftm += l.ftm; fta += l.fta; pf += l.pf
        }
    }
}

/// A team a player belongs to, with season/league names, decoded from a
/// PostgREST embedded-resource query over roster_spots' foreign keys.
struct PlayerTeam: Codable, Identifiable, Equatable {
    let id: UUID
    let displayName: String
    let teams: TeamRef

    struct TeamRef: Codable, Equatable {
        let name: String
        let seasons: SeasonRef
    }
    struct SeasonRef: Codable, Equatable {
        let name: String
        let leagues: LeagueRef
    }
    struct LeagueRef: Codable, Equatable {
        let name: String
    }

    var teamName: String { teams.name }
    var seasonName: String { teams.seasons.name }
    var leagueName: String { teams.seasons.leagues.name }
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
