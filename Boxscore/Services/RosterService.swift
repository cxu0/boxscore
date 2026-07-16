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

    /// Adds a placeholder roster spot with a fresh invite code the commissioner
    /// can hand to the real player, who redeems it via `claimInvite`.
    func addRosterSpot(teamId: UUID, displayName: String) async throws -> RosterSpot {
        let inviteCode = Self.generateInviteCode()
        return try await client
            .from("roster_spots")
            .insert([
                "team_id": teamId.uuidString,
                "display_name": displayName,
                "invite_code": inviteCode
            ])
            .select()
            .single()
            .execute()
            .value
    }

    /// Links the signed-in player's account to the roster spot matching
    /// `inviteCode` via the `claim_invite` RPC, which atomically checks the
    /// code is unclaimed. Every box score already recorded against that spot
    /// becomes part of the player's aggregated stats immediately.
    func claimInvite(code: String) async throws -> RosterSpot {
        try await client
            .rpc("claim_invite", params: ["p_invite_code": code])
            .single()
            .execute()
            .value
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

    private static func generateInviteCode(length: Int = 6) -> String {
        let alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // no O/0/I/1 ambiguity
        return String((0..<length).map { _ in alphabet.randomElement()! })
    }
}
