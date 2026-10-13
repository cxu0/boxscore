import Foundation
import Testing
@testable import Boxscore

@MainActor
struct LocationTests {
    @Test func haversineMiles() {
        // Downtown Austin → downtown Round Rock is ~17 miles as the crow flies.
        let miles = LeagueService.miles(fromLat: 30.2672, lng: -97.7431, toLat: 30.5083, lng: -97.6789)
        #expect(abs(miles - 17.0) < 1.0)
        #expect(LeagueService.miles(fromLat: 40, lng: -74, toLat: 40, lng: -74) == 0)
    }

    @Test func leagueDetailsEncodeSnakeCaseWithExplicitNulls() throws {
        let details = LeagueService.LeagueDetails(
            venue: Venue(name: "Downtown YMCA", address: "1 Main St", city: "Austin", latitude: 30.1, longitude: -97.2),
            gameNight: "  Tuesdays  ",
            signupUrl: ""
        )
        let data = try SupabaseService.encoder.encode(details)
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(obj["venue_name"] as? String == "Downtown YMCA")
        #expect(obj["city"] as? String == "Austin")
        #expect(obj["latitude"] as? Double == 30.1)
        #expect(obj["game_night"] as? String == "Tuesdays")
        // Cleared fields must be sent as null (so editing can remove them),
        // not left out.
        #expect(obj.keys.contains("signup_url"))
        #expect(obj["signup_url"] is NSNull)
    }

    @Test func signupURLNormalization() {
        typealias D = LeagueService.LeagueDetails
        #expect(D.normalizedURL("tuesdayhoops.com/register") == "https://tuesdayhoops.com/register")
        #expect(D.normalizedURL("http://x.com") == "http://x.com")
        #expect(D.normalizedURL("   ") == nil)
    }

    @Test func leagueWithLocationDecodes() throws {
        let league = try SupabaseService.decoder.decode(League.self, from: Data("""
        {"id":"7d6c1a62-0000-4000-8000-000000000003","name":"Tuesday Night","owner_id":"7d6c1a62-0000-4000-8000-000000000004",
         "is_public":true,"join_code":"ABC123","format":"5v5","staff_code":"XYZ789",
         "allow_player_teams":true,"max_teams":null,"max_roster_size":null,"join_policy":"open",
         "created_at":"2026-10-01T18:30:00+00:00",
         "venue_name":"Downtown YMCA","venue_address":"1 Main St","city":"Austin",
         "latitude":30.1,"longitude":-97.2,"game_night":"Tuesdays","signup_url":"https://x.com"}
        """.utf8))
        #expect(league.venue?.name == "Downtown YMCA")
        #expect(league.locationLine == "Downtown YMCA · Austin")
        #expect(league.signupUrl == "https://x.com")
    }

    @Test func leagueWithoutLocationStillDecodes() throws {
        // Leagues created before 0008 (or with no gym picked).
        let league = try SupabaseService.decoder.decode(League.self, from: Data("""
        {"id":"7d6c1a62-0000-4000-8000-000000000003","name":"Old League","owner_id":"7d6c1a62-0000-4000-8000-000000000004",
         "is_public":false,"join_code":"ABC123","format":"rec","staff_code":"XYZ789",
         "allow_player_teams":true,"max_teams":null,"max_roster_size":null,"join_policy":"open"}
        """.utf8))
        #expect(league.venue == nil)
        #expect(league.locationLine == nil)
    }
}
