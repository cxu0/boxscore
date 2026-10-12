import Foundation
import Testing
@testable import Boxscore

/// Decodes JSON shaped like real PostgREST responses with the app's own
/// decoder, so schema/model drift fails here instead of silently on device.
@MainActor
struct ModelDecodingTests {
    func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try SupabaseService.decoder.decode(T.self, from: Data(json.utf8))
    }

    @Test func rosterSpotWithOwnerVisibleEmail() throws {
        let spot = try decode(RosterSpot.self, """
        {"id":"7d6c1a62-0000-4000-8000-000000000001","team_id":"7d6c1a62-0000-4000-8000-000000000002",
         "display_name":"Jordan Lee","player_id":null,"invite_code":null,
         "created_at":"2026-10-01T18:30:00.123456+00:00",
         "roster_spot_emails":{"email":"jordan@x.com"}}
        """)
        #expect(spot.inviteEmail == "jordan@x.com")
        #expect(spot.playerId == nil)
    }

    @Test func rosterSpotEmailHiddenByRLS() throws {
        let spot = try decode(RosterSpot.self, """
        {"id":"7d6c1a62-0000-4000-8000-000000000001","team_id":"7d6c1a62-0000-4000-8000-000000000002",
         "display_name":"Jordan Lee","player_id":null,"created_at":"2026-10-01T18:30:00+00:00",
         "roster_spot_emails":null}
        """)
        #expect(spot.inviteEmail == nil)
    }

    @Test func importResultFromRPC() throws {
        let result = try decode(RosterImportResult.self,
            #"{"teams_created":2,"players_added":8,"already_joined":1,"skipped":0}"#)
        #expect(result == RosterImportResult(teamsCreated: 2, playersAdded: 8, alreadyJoined: 1, skipped: 0))
    }

    @Test func importRowsEncodeToRPCKeys() throws {
        let data = try SupabaseService.encoder.encode([RosterImportRow(team: "Ballers", name: "Jordan", email: nil)])
        let obj = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        #expect(obj?.first?["team"] as? String == "Ballers")
        #expect(obj?.first?["name"] as? String == "Jordan")
    }

    @Test func seasonDateOnlyColumnsDecode() throws {
        #expect(PostgresDate.parse("2026-10-01") != nil)
        #expect(PostgresDate.parse("2026-10-01T18:30:00Z") != nil)
        #expect(PostgresDate.parse("2026-10-01T18:30:00.123456+00:00") != nil)
    }

    @Test func myLeagueBadgeLabels() throws {
        let league = try decode(League.self, """
        {"id":"7d6c1a62-0000-4000-8000-000000000003","name":"Tuesday Night","owner_id":"7d6c1a62-0000-4000-8000-000000000004",
         "is_public":false,"join_code":"ABC123","format":"5v5","staff_code":"XYZ789",
         "allow_player_teams":true,"max_teams":null,"max_roster_size":null,"join_policy":"open",
         "created_at":"2026-10-01T18:30:00+00:00"}
        """)
        #expect(MyLeague(league: league, roles: [.owner, .player]).label == "ORGANIZER")
        #expect(MyLeague(league: league, roles: [.staff]).label == "STAT KEEPER")
        #expect(MyLeague(league: league, roles: [.staff, .player]).label == "PLAYER · STAT KEEPER")
        #expect(MyLeague(league: league, roles: [.player]).label == "PLAYER")
    }
}
