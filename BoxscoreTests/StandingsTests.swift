import Foundation
import Testing
@testable import Boxscore

@MainActor
struct StandingsTests {
    let season = UUID()
    lazy var a = Team(id: UUID(), seasonId: season, name: "Alpha")
    lazy var b = Team(id: UUID(), seasonId: season, name: "Bravo")
    lazy var c = Team(id: UUID(), seasonId: season, name: "Charlie")

    func game(_ home: Team, _ away: Team, _ hs: Int?, _ aws: Int?, day: Int, status: GameStatus = .final) -> Game {
        Game(id: UUID(), seasonId: season, homeTeamId: home.id, awayTeamId: away.id,
             scheduledAt: Date(timeIntervalSince1970: TimeInterval(day * 86_400)),
             status: status, homeScore: hs, awayScore: aws)
    }

    @Test mutating func recordsAndOrdering() {
        let games = [
            game(a, b, 50, 40, day: 1),   // A beats B
            game(c, a, 45, 44, day: 2),   // C beats A
            game(b, c, 30, 60, day: 3),   // C beats B
        ]
        let table = LeagueService.standings(teams: [a, b, c], games: games)
        #expect(table.map(\.team.name) == ["Charlie", "Alpha", "Bravo"])
        #expect(table.map(\.record) == ["2-0", "1-1", "0-2"])
    }

    @Test mutating func streakUsesMostRecentResults() {
        let games = [
            game(a, b, 10, 20, day: 1),   // A loses
            game(a, b, 30, 20, day: 2),   // A wins
            game(a, b, 30, 20, day: 3),   // A wins
        ]
        let table = LeagueService.standings(teams: [a, b], games: games)
        #expect(table.first { $0.team.id == a.id }?.streak == "W2")
        #expect(table.first { $0.team.id == b.id }?.streak == "L2")
    }

    @Test mutating func ignoresScheduledTiedAndScorelessGames() {
        let games = [
            game(a, b, 50, 40, day: 1, status: .scheduled),
            game(a, b, 40, 40, day: 2),
            game(a, b, nil, nil, day: 3),
        ]
        let table = LeagueService.standings(teams: [a, b], games: games)
        #expect(table.allSatisfy { $0.record == "0-0" && $0.streak == "—" })
        // Ties on record break alphabetically.
        #expect(table.map(\.team.name) == ["Alpha", "Bravo"])
    }
}
