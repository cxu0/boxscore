import Foundation
import Combine
import Supabase

@MainActor
final class RosterService: ObservableObject {
    private let client = SupabaseService.client

    func fetchRoster(teamId: UUID) async throws -> [RosterSpot] {
        try await client
            .from("roster_spots")
            .select()
            .eq("team_id", value: teamId)
            .order("display_name")
            .execute()
            .value
    }

    /// Adds a placeholder roster spot for a player who isn't on the app yet.
    /// Stats can accrue against it immediately; the real player links their
    /// account to it later via `requestClaim`.
    func addRosterSpot(teamId: UUID, displayName: String) async throws -> RosterSpot {
        try await client
            .from("roster_spots")
            .insert(["team_id": teamId.uuidString, "display_name": displayName])
            .select()
            .single()
            .execute()
            .value
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

    /// A player asking to take over a placeholder roster spot the organizer
    /// already entered stats against. Pending until the organizer approves.
    func requestClaim(rosterSpotId: UUID) async throws -> ClaimRequest {
        try await client
            .rpc("request_claim", params: ["p_roster_spot_id": rosterSpotId.uuidString])
            .single()
            .execute()
            .value
    }

    /// Pending claim requests for every placeholder on this team, with the
    /// requester's name embedded — shown to the organizer for approval.
    func fetchPendingClaimRequests(teamId: UUID) async throws -> [ClaimRequest] {
        try await client
            .from("claim_requests")
            .select("*, profiles(display_name), roster_spots!inner(team_id)")
            .eq("roster_spots.team_id", value: teamId)
            .eq("status", value: ClaimRequestStatus.pending.rawValue)
            .execute()
            .value
    }

    func approveClaimRequest(id: UUID) async throws -> RosterSpot {
        try await client
            .rpc("approve_claim_request", params: ["p_request_id": id.uuidString])
            .single()
            .execute()
            .value
    }

    func denyClaimRequest(id: UUID) async throws {
        try await client
            .rpc("deny_claim_request", params: ["p_request_id": id.uuidString])
            .execute()
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
