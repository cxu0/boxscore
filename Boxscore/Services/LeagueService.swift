import Foundation
import Combine
import Supabase

@MainActor
final class LeagueService: ObservableObject {
    private let client = SupabaseService.client

    // MARK: Leagues

    func fetchLeagues(ownerId: UUID) async throws -> [League] {
        try await client
            .from("leagues")
            .select()
            .eq("owner_id", value: ownerId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func createLeague(name: String, ownerId: UUID) async throws -> League {
        try await client
            .from("leagues")
            .insert(["name": name, "owner_id": ownerId.uuidString])
            .select()
            .single()
            .execute()
            .value
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
