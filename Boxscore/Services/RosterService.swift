import Foundation
import Combine
import Supabase

@MainActor
final class RosterService: ObservableObject {
    private let client = SupabaseService.client

    func fetchRoster(teamId: UUID) async throws -> [RosterSpot] {
        try await client
            .from("roster_spots")
            .select("*, roster_spot_emails(email)")
            .eq("team_id", value: teamId)
            .order("display_name")
            .execute()
            .value
    }

    /// Adds a roster spot by name. With an email, the player is linked
    /// automatically as soon as they sign up (or right away if they already
    /// have a confirmed account) — see 0005_roster_emails.sql.
    func addRosterSpot(teamId: UUID, displayName: String, email: String?) async throws -> RosterSpot {
        let spot: RosterSpot = try await client
            .from("roster_spots")
            .insert(["team_id": teamId.uuidString, "display_name": displayName])
            .select()
            .single()
            .execute()
            .value
        try await setEmail(rosterSpotId: spot.id, email: email)
        return spot
    }

    /// Game-night sub: stat keepers or the owner add a name-only player so
    /// their stats can be recorded. The organizer can attach an email later.
    func addSub(teamId: UUID, displayName: String) async throws -> RosterSpot {
        try await client
            .rpc("add_sub", params: ["p_team_id": teamId.uuidString, "p_display_name": displayName])
            .single()
            .execute()
            .value
    }

    /// Sets (or clears, when empty) the email attached to a roster spot.
    func setEmail(rosterSpotId: UUID, email: String?) async throws {
        let cleaned = email?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        if cleaned.isEmpty {
            try await client.from("roster_spot_emails").delete().eq("roster_spot_id", value: rosterSpotId).execute()
        } else {
            try await client
                .from("roster_spot_emails")
                .upsert(["roster_spot_id": rosterSpotId.uuidString, "email": cleaned])
                .execute()
        }
    }

    /// Undo a wrong email match: detaches the account and clears the email so
    /// it can't re-link. The organizer then adds the right email.
    func unlinkPlayer(rosterSpotId: UUID) async throws {
        try await client.from("roster_spots").update(["player_id": AnyJSON.null]).eq("id", value: rosterSpotId).execute()
        try await setEmail(rosterSpotId: rosterSpotId, email: nil)
    }

    /// Owner bulk import: creates teams + roster spots (+ emails) in the
    /// league's current season in one transaction.
    func importRoster(leagueId: UUID, rows: [RosterImportRow]) async throws -> RosterImportResult {
        struct Params: Encodable {
            let p_league_id: String
            let p_rows: [RosterImportRow]
        }
        return try await client
            .rpc("import_roster", params: Params(p_league_id: leagueId.uuidString, p_rows: rows))
            .execute()
            .value
    }

    /// Links the signed-in user to any roster spots carrying their confirmed
    /// email. Returns how many were linked.
    @discardableResult
    func claimMyRosterSpots() async throws -> Int {
        try await client.rpc("claim_my_roster_spots").execute().value
    }

    func renameRosterSpot(id: UUID, displayName: String) async throws {
        try await client.from("roster_spots").update(["display_name": displayName]).eq("id", value: id).execute()
    }

    func deleteRosterSpot(id: UUID) async throws {
        try await client.from("roster_spots").delete().eq("id", value: id).execute()
    }

    /// Self-serve join via the league's one shareable code — the signed-in
    /// player adds themselves directly to a roster spot, no organizer
    /// involvement or approval needed.
    func joinLeagueSelf(joinCode: String, teamId: UUID, displayName: String) async throws -> RosterSpot {
        try await client
            .rpc("join_league_self", params: [
                "p_join_code": joinCode,
                "p_team_id": teamId.uuidString,
                "p_display_name": displayName
            ])
            .single()
            .execute()
            .value
    }

    /// Creates a brand-new team in the league and joins it in one step.
    func createTeamAndJoin(leagueId: UUID, teamName: String, displayName: String) async throws -> RosterSpot {
        try await client
            .rpc("create_team_and_join", params: [
                "p_league_id": leagueId.uuidString,
                "p_team_name": teamName,
                "p_display_name": displayName
            ])
            .single()
            .execute()
            .value
    }

    /// Instant join for a public, open-policy league (no code needed).
    func joinLeaguePublic(leagueId: UUID, teamId: UUID, displayName: String) async throws -> RosterSpot {
        try await client
            .rpc("join_league_public", params: [
                "p_league_id": leagueId.uuidString,
                "p_team_id": teamId.uuidString,
                "p_display_name": displayName
            ])
            .single()
            .execute()
            .value
    }

    /// Request to join a public, approval-policy league. `teamId` for an
    /// existing team, or `newTeamName` to propose a new one.
    func requestToJoin(leagueId: UUID, teamId: UUID?, newTeamName: String?, displayName: String) async throws -> JoinRequest {
        struct Params: Encodable {
            let p_league_id: String
            let p_team_id: String?
            let p_new_team_name: String?
            let p_display_name: String
        }
        return try await client
            .rpc("request_to_join", params: Params(
                p_league_id: leagueId.uuidString,
                p_team_id: teamId?.uuidString,
                p_new_team_name: newTeamName,
                p_display_name: displayName
            ))
            .single()
            .execute()
            .value
    }

    /// Whether the signed-in player already holds a roster spot in this league.
    func isMember(leagueId: UUID, userId: UUID) async throws -> Bool {
        struct Row: Decodable { let id: UUID }
        let rows: [Row] = try await client
            .from("roster_spots")
            .select("id, teams!inner(seasons!inner(league_id))")
            .eq("player_id", value: userId)
            .eq("teams.seasons.league_id", value: leagueId)
            .execute()
            .value
        return !rows.isEmpty
    }

    func fetchLinkedRosterSpots(playerId: UUID) async throws -> [RosterSpot] {
        try await client
            .from("roster_spots")
            .select()
            .eq("player_id", value: playerId)
            .execute()
            .value
    }

    /// The teams a player has claimed, with their season/league names pulled in
    /// via PostgREST's embedded-resource selection over the foreign keys. Used
    /// to show team membership on the profile even before any stats exist.
    func fetchPlayerTeams(playerId: UUID) async throws -> [PlayerTeam] {
        try await client
            .from("roster_spots")
            .select("id, display_name, teams(name, seasons(name, leagues(name)))")
            .eq("player_id", value: playerId)
            .execute()
            .value
    }
}
