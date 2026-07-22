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
    /// Creates the league, its first season, and any teams the organizer added
    /// during setup — one call so a brand-new league is ready to share.
    /// Edits a league's name, visibility, and format in one update.
    func updateLeague(id: UUID, name: String, isPublic: Bool, format: LeagueFormat) async throws -> League {
        struct Update: Encodable {
            let name: String
            let is_public: Bool
            let format: String
        }
        return try await client
            .from("leagues")
            .update(Update(name: name, is_public: isPublic, format: format.rawValue))
            .eq("id", value: id)
            .select()
            .single()
            .execute()
            .value
    }

    func deleteLeague(id: UUID) async throws {
        try await client.from("leagues").delete().eq("id", value: id).execute()
    }

    func createLeague(
        name: String,
        isPublic: Bool,
        format: LeagueFormat,
        ownerId: UUID,
        seasonName: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        teamNames: [String] = []
    ) async throws -> League {
        struct NewLeague: Encodable {
            let name: String
            let owner_id: String
            let is_public: Bool
            let format: String
        }
        let league: League = try await client
            .from("leagues")
            .insert(NewLeague(name: name, owner_id: ownerId.uuidString, is_public: isPublic, format: format.rawValue))
            .select()
            .single()
            .execute()
            .value

        let year = Calendar.current.component(.year, from: Date())
        let season = try await createSeason(
            name: seasonName?.isEmpty == false ? seasonName! : "\(year) Season",
            leagueId: league.id,
            startDate: startDate,
            endDate: endDate
        )

        for teamName in teamNames where !teamName.trimmingCharacters(in: .whitespaces).isEmpty {
            _ = try await createTeam(name: teamName, seasonId: season.id)
        }

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

    func updateSeason(id: UUID, name: String, startDate: Date?, endDate: Date?) async throws -> Season {
        struct Update: Encodable {
            let name: String
            let start_date: Date?
            let end_date: Date?
        }
        return try await client
            .from("seasons")
            .update(Update(name: name, start_date: startDate, end_date: endDate))
            .eq("id", value: id)
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

    /// Number of roster spots on a team, without pulling the rows.
    func fetchRosterCount(teamId: UUID) async throws -> Int {
        let response = try await client
            .from("roster_spots")
            .select("id", head: true, count: .exact)
            .eq("team_id", value: teamId)
            .execute()
        return response.count ?? 0
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

    func renameTeam(id: UUID, name: String) async throws {
        try await client.from("teams").update(["name": name]).eq("id", value: id).execute()
    }

    func deleteTeam(id: UUID) async throws {
        try await client.from("teams").delete().eq("id", value: id).execute()
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

    func rescheduleGame(id: UUID, date: Date) async throws {
        struct Reschedule: Encodable { let scheduled_at: Date }
        try await client.from("games").update(Reschedule(scheduled_at: date)).eq("id", value: id).execute()
    }

    func deleteGame(id: UUID) async throws {
        try await client.from("games").delete().eq("id", value: id).execute()
    }

    /// Records the final score and flips the game to final in one call.
    func setGameResult(gameId: UUID, homeScore: Int, awayScore: Int) async throws -> Game {
        try await client
            .rpc("set_game_result", params: [
                "p_game_id": gameId.uuidString,
                "p_home_score": String(homeScore),
                "p_away_score": String(awayScore)
            ])
            .single()
            .execute()
            .value
    }

    /// Derives each team's W-L record and current streak from the final games'
    /// manually-entered scores. Pure client-side — no extra round trips.
    static func standings(teams: [Team], games: [Game]) -> [TeamStanding] {
        var wins: [UUID: Int] = [:]
        var losses: [UUID: Int] = [:]
        // Results per team in chronological order, for streak calculation.
        var history: [UUID: [(date: Date, won: Bool)]] = [:]

        let finals = games
            .filter { $0.status == .final && $0.hasResult }
            .sorted { $0.scheduledAt < $1.scheduledAt }

        for game in finals {
            guard let hs = game.homeScore, let as_ = game.awayScore, hs != as_ else { continue }
            let homeWon = hs > as_
            let winner = homeWon ? game.homeTeamId : game.awayTeamId
            let loser = homeWon ? game.awayTeamId : game.homeTeamId
            wins[winner, default: 0] += 1
            losses[loser, default: 0] += 1
            history[winner, default: []].append((game.scheduledAt, true))
            history[loser, default: []].append((game.scheduledAt, false))
        }

        return teams.map { team in
            let results = (history[team.id] ?? []).sorted { $0.date < $1.date }
            return TeamStanding(
                team: team,
                wins: wins[team.id] ?? 0,
                losses: losses[team.id] ?? 0,
                streak: streakString(results.map(\.won))
            )
        }
        .sorted {
            if $0.wins != $1.wins { return $0.wins > $1.wins }
            if $0.losses != $1.losses { return $0.losses < $1.losses }
            return $0.team.name < $1.team.name
        }
    }

    private static func streakString(_ results: [Bool]) -> String {
        guard let last = results.last else { return "—" }
        var count = 0
        for won in results.reversed() {
            if won == last { count += 1 } else { break }
        }
        return "\(last ? "W" : "L")\(count)"
    }
}
