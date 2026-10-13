import Foundation
import Combine
import Supabase

@MainActor
final class LeagueService: ObservableObject {
    private let client = SupabaseService.client

    // MARK: Leagues

    /// Leagues the user owns, keeps stats for, or has a roster spot in —
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

        struct StaffLeagueRow: Decodable { let leagues: League }
        async let staffTask: [StaffLeagueRow] = client
            .from("league_staff")
            .select("leagues!inner(*)")
            .eq("profile_id", value: userId)
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
        let staffed = try await staffTask.map(\.leagues)
        let played = try await playedTask.map(\.teams.seasons.leagues)

        var byId: [UUID: MyLeague] = [:]
        func add(_ league: League, _ role: MyLeague.Role) {
            byId[league.id, default: MyLeague(league: league, roles: [])].roles.insert(role)
        }
        owned.forEach { add($0, .owner) }
        staffed.forEach { add($0, .staff) }
        played.forEach { add($0, .player) }
        return byId.values.sorted { ($0.league.createdAt ?? .distantPast) > ($1.league.createdAt ?? .distantPast) }
    }

    /// Public leagues matching a name search — the browse/discover path. Private
    /// leagues stay code-only, so only `is_public` leagues surface here.
    func searchPublicLeagues(query: String) async throws -> [League] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        // PostgREST `or` syntax: commas/parens separate filters, so strip them
        // from user input; `*` is the wildcard inside or().
        let safe = trimmed.filter { !",()*".contains($0) }
        let pattern = "*\(safe)*"
        return try await client
            .from("leagues")
            .select()
            .eq("is_public", value: true)
            .or("name.ilike.\(pattern),city.ilike.\(pattern),venue_name.ilike.\(pattern)")
            .order("name")
            .limit(25)
            .execute()
            .value
    }

    /// Public leagues within roughly `radiusMiles`, nearest first. Filters by
    /// a lat/lng box in the database, then sorts by straight-line distance.
    func fetchNearbyPublicLeagues(latitude: Double, longitude: Double, radiusMiles: Double = 40) async throws -> [(league: League, miles: Double)] {
        let latDelta = radiusMiles / 69.0
        let lngDelta = radiusMiles / max(69.0 * cos(latitude * .pi / 180), 1)
        let leagues: [League] = try await client
            .from("leagues")
            .select()
            .eq("is_public", value: true)
            .gte("latitude", value: latitude - latDelta)
            .lte("latitude", value: latitude + latDelta)
            .gte("longitude", value: longitude - lngDelta)
            .lte("longitude", value: longitude + lngDelta)
            .limit(100)
            .execute()
            .value
        return leagues
            .compactMap { league in
                guard let lat = league.latitude, let lng = league.longitude else { return nil }
                let miles = Self.miles(fromLat: latitude, lng: longitude, toLat: lat, lng: lng)
                return miles <= radiusMiles ? (league, miles) : nil
            }
            .sorted { $0.miles < $1.miles }
    }

    /// Great-circle distance in miles (haversine).
    static func miles(fromLat lat1: Double, lng lng1: Double, toLat lat2: Double, lng lng2: Double) -> Double {
        let r = 3958.8
        let dLat = (lat2 - lat1) * .pi / 180
        let dLng = (lng2 - lng1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLng / 2) * sin(dLng / 2)
        return 2 * r * asin(min(1, sqrt(a)))
    }

    /// Creates the league and its first season in one call — a fresh league
    /// always has somewhere for teams to live, without the organizer ever
    /// having to think about "seasons" on day one.
    /// Creates the league, its first season, and any teams the organizer added
    /// during setup — one call so a brand-new league is ready to share.
    /// Edits a league's settings in one update.
    /// Where/when a league plays — shared by create and edit.
    struct LeagueDetails: Encodable {
        var venueName: String?
        var venueAddress: String?
        var city: String?
        var latitude: Double?
        var longitude: Double?
        var gameNight: String?
        var signupUrl: String?

        init(venue: Venue?, gameNight: String, signupUrl: String) {
            venueName = venue?.name
            venueAddress = venue?.address
            city = venue?.city
            latitude = venue?.latitude
            longitude = venue?.longitude
            let night = gameNight.trimmingCharacters(in: .whitespaces)
            self.gameNight = night.isEmpty ? nil : night
            self.signupUrl = Self.normalizedURL(signupUrl)
        }

        /// "leaguesite.com/register" → "https://leaguesite.com/register"; blank → nil.
        static func normalizedURL(_ raw: String) -> String? {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            return trimmed.lowercased().hasPrefix("http") ? trimmed : "https://\(trimmed)"
        }

        // Encode nils as JSON null so clearing a field actually clears it.
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(venueName, forKey: .venueName)
            try c.encode(venueAddress, forKey: .venueAddress)
            try c.encode(city, forKey: .city)
            try c.encode(latitude, forKey: .latitude)
            try c.encode(longitude, forKey: .longitude)
            try c.encode(gameNight, forKey: .gameNight)
            try c.encode(signupUrl, forKey: .signupUrl)
        }
        enum CodingKeys: String, CodingKey {
            case venueName, venueAddress, city, latitude, longitude, gameNight, signupUrl
        }
    }

    func updateLeague(
        id: UUID,
        name: String,
        isPublic: Bool,
        format: LeagueFormat,
        joinPolicy: JoinPolicy,
        allowPlayerTeams: Bool,
        maxTeams: Int?,
        maxRosterSize: Int?,
        details: LeagueDetails
    ) async throws -> League {
        struct Update: Encodable {
            let name: String
            let isPublic: Bool
            let format: String
            let joinPolicy: String
            let allowPlayerTeams: Bool
            let maxTeams: Int?
            let maxRosterSize: Int?
            let details: LeagueDetails

            enum CodingKeys: String, CodingKey {
                case name, isPublic, format, joinPolicy, allowPlayerTeams, maxTeams, maxRosterSize
            }
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(name, forKey: .name)
                try c.encode(isPublic, forKey: .isPublic)
                try c.encode(format, forKey: .format)
                try c.encode(joinPolicy, forKey: .joinPolicy)
                try c.encode(allowPlayerTeams, forKey: .allowPlayerTeams)
                try c.encode(maxTeams, forKey: .maxTeams)
                try c.encode(maxRosterSize, forKey: .maxRosterSize)
                try details.encode(to: encoder)
            }
        }
        return try await client
            .from("leagues")
            .update(Update(
                name: name, isPublic: isPublic, format: format.rawValue,
                joinPolicy: joinPolicy.rawValue, allowPlayerTeams: allowPlayerTeams,
                maxTeams: maxTeams, maxRosterSize: maxRosterSize, details: details
            ))
            .eq("id", value: id)
            .select()
            .single()
            .execute()
            .value
    }

    func fetchLeague(id: UUID) async throws -> League {
        try await client.from("leagues").select().eq("id", value: id).single().execute().value
    }

    // MARK: Stat keepers

    func redeemStaffCode(_ code: String) async throws -> League {
        try await client
            .rpc("redeem_staff_code", params: ["p_code": code])
            .single()
            .execute()
            .value
    }

    func regenerateStaffCode(leagueId: UUID) async throws -> String {
        try await client
            .rpc("regenerate_staff_code", params: ["p_league_id": leagueId.uuidString])
            .execute()
            .value
    }

    func fetchStaff(leagueId: UUID) async throws -> [LeagueStaff] {
        try await client
            .from("league_staff")
            .select("*, profiles(display_name)")
            .eq("league_id", value: leagueId)
            .execute()
            .value
    }

    func removeStaff(id: UUID) async throws {
        try await client.from("league_staff").delete().eq("id", value: id).execute()
    }

    /// Whether the given user may keep stats for the league (owner or staff).
    func isStaff(leagueId: UUID, userId: UUID) async throws -> Bool {
        let rows: [LeagueStaff] = try await client
            .from("league_staff")
            .select()
            .eq("league_id", value: leagueId)
            .eq("profile_id", value: userId)
            .execute()
            .value
        return !rows.isEmpty
    }

    // MARK: Join requests (public approval leagues)

    func fetchJoinRequests(leagueId: UUID) async throws -> [JoinRequest] {
        try await client
            .from("join_requests")
            .select("*, profiles(display_name), teams(name)")
            .eq("league_id", value: leagueId)
            .eq("status", value: ClaimRequestStatus.pending.rawValue)
            .execute()
            .value
    }

    func approveJoinRequest(id: UUID) async throws {
        try await client.rpc("approve_join_request", params: ["p_request_id": id.uuidString]).execute()
    }

    func denyJoinRequest(id: UUID) async throws {
        try await client.rpc("deny_join_request", params: ["p_request_id": id.uuidString]).execute()
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
        teamNames: [String] = [],
        details: LeagueDetails
    ) async throws -> League {
        struct NewLeague: Encodable {
            let name: String
            let ownerId: UUID
            let isPublic: Bool
            let format: String
            let details: LeagueDetails

            enum CodingKeys: String, CodingKey { case name, ownerId, isPublic, format }
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(name, forKey: .name)
                try c.encode(ownerId, forKey: .ownerId)
                try c.encode(isPublic, forKey: .isPublic)
                try c.encode(format, forKey: .format)
                try details.encode(to: encoder)
            }
        }
        let league: League = try await client
            .from("leagues")
            .insert(NewLeague(name: name, ownerId: ownerId, isPublic: isPublic, format: format.rawValue, details: details))
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
