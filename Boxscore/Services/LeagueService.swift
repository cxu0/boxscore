import Foundation
import Combine
import Supabase

@MainActor
final class LeagueService: ObservableObject {
    private let client = SupabaseService.client

    // MARK: Leagues

    /// Leagues the user owns, merged with leagues they have a roster spot in —
    /// the "My Leagues" list doesn't distinguish organizer vs player accounts,
    /// just relationships to individual leagues.
    func fetchMyLeagues(userId: UUID) async throws -> [MyLeague] {
        async let ownedTask: [League] = client
            .from("leagues")
            .select()
            .eq("owner_id", value: userId)
            .order("created_at", ascending: false)
            .execute()
            .value

        struct PlayedLeagueRow: Decodable {
            struct TeamWrap: Decodable { let seasons: SeasonWrap }
            struct SeasonWrap: Decodable { let leagues: League }
            let teams: TeamWrap
        }
        async let playedTask: [PlayedLeagueRow] = client
            .from("roster_spots")
            .select("teams!inner(seasons!inner(leagues!inner(*)))")
            .eq("player_id", value: userId)
            .execute()
            .value

        let owned = try await ownedTask
        let played = try await playedTask

        var seen = Set<UUID>()
        var result: [MyLeague] = []
        for league in owned {
            seen.insert(league.id)
            result.append(MyLeague(league: league, relationship: .owner))
        }
        for row in played {
            let league = row.teams.seasons.leagues
            if seen.insert(league.id).inserted {
                result.append(MyLeague(league: league, relationship: .player))
            }
        }
        return result.sorted { ($0.league.createdAt ?? .distantPast) > ($1.league.createdAt ?? .distantPast) }
    }

    func findLeague(byJoinCode code: String) async throws -> League {
        try await client
            .from("leagues")
            .select()
            .eq("join_code", value: code)
            .single()
            .execute()
            .value
    }

    /// Creates the league and its first season in one call — a fresh league
    /// always has somewhere for teams to live, without the organizer ever
    /// having to think about "seasons" on day one.
    func createLeague(name: String, isPublic: Bool, ownerId: UUID) async throws -> League {
        struct NewLeague: Encodable {
            let name: String
            let owner_id: String
            let is_public: Bool
        }
        let league: League = try await client
            .from("leagues")
            .insert(NewLeague(name: name, owner_id: ownerId.uuidString, is_public: isPublic))
            .select()
            .single()
            .execute()
            .value

        let year = Calendar.current.component(.year, from: Date())
        _ = try await createSeason(name: "\(year) Season", leagueId: league.id, startDate: nil, endDate: nil)

        return league
    }

    // MARK: Seasons

    func fetchSeasons(leagueId: UUID) async throws -> [Season] {
        try await client
            .from("seasons")
            .select()
            .eq("league_id", value: leagueId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func createSeason(name: String, leagueId: UUID, startDate: Date?, endDate: Date?) async throws -> Season {
        struct NewSeason: Encodable {
            let league_id: String
            let name: String
            let start_date: Date?
            let end_date: Date?
        }
        return try await client
            .from("seasons")
            .insert(NewSeason(league_id: leagueId.uuidString, name: name, start_date: startDate, end_date: endDate))
            .select()
            .single()
            .execute()
            .value
    }

    // MARK: Teams

    func fetchTeams(seasonId: UUID) async throws -> [Team] {
        try await client
            .from("teams")
            .select()
            .eq("season_id", value: seasonId)
            .order("name")
            .execute()
            .value
    }

    func createTeam(name: String, seasonId: UUID) async throws -> Team {
        try await client
            .from("teams")
            .insert(["season_id": seasonId.uuidString, "name": name])
            .select()
            .single()
            .execute()
            .value
    }

    // MARK: Games

    func fetchGames(seasonId: UUID) async throws -> [Game] {
        try await client
            .from("games")
            .select()
            .eq("season_id", value: seasonId)
            .order("scheduled_at", ascending: false)
            .execute()
            .value
    }

    func createGame(seasonId: UUID, homeTeamId: UUID, awayTeamId: UUID, scheduledAt: Date) async throws -> Game {
        struct NewGame: Encodable {
            let season_id: String
            let home_team_id: String
            let away_team_id: String
            let scheduled_at: Date
        }
        return try await client
            .from("games")
            .insert(NewGame(
                season_id: seasonId.uuidString,
                home_team_id: homeTeamId.uuidString,
                away_team_id: awayTeamId.uuidString,
                scheduled_at: scheduledAt
            ))
            .select()
            .single()
            .execute()
            .value
    }

    func markGameFinal(gameId: UUID) async throws {
        try await client
            .from("games")
            .update(["status": GameStatus.final.rawValue])
            .eq("id", value: gameId)
            .execute()
    }
}
