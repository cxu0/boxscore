import Testing
@testable import Boxscore

@MainActor
struct RosterImportParserTests {
    @Test func tabSeparatedPasteWithFirstLastHeader() {
        let text = "Team\tFirst Name\tLast Name\tEmail\nBallers\tJordan\tLee\tJLee@Gmail.com\nBallers\tSam\tKim\t\n"
        let out = RosterImportParser.parse(text)
        #expect(out.rows == [
            RosterImportRow(team: "Ballers", name: "Jordan Lee", email: "jlee@gmail.com"),
            RosterImportRow(team: "Ballers", name: "Sam Kim", email: nil),
        ])
        #expect(out.badLines.isEmpty)
    }

    @Test func csvWithoutHeaderHandlesQuotesAndBadLines() {
        let text = "Ballers, Jordan Lee, jordan@x.com\nBuckets, \"Smith, Jr.\", al@x.com\nbadline"
        let out = RosterImportParser.parse(text)
        #expect(out.rows.map(\.name) == ["Jordan Lee", "Smith, Jr."])
        #expect(out.badLines == [3])
    }

    @Test func headerColumnsInAnyOrder() {
        let out = RosterImportParser.parse("Player Name,Team Name,E-mail Address\nJordan,Ballers,j@x.com\n,Ballers,\n")
        #expect(out.rows == [RosterImportRow(team: "Ballers", name: "Jordan", email: "j@x.com")])
        #expect(out.badLines == [3])
    }

    @Test func positionalFindsEmailAnywhere() {
        let out = RosterImportParser.parse("jordan@x.com,Ballers,Jordan Lee\r\n\r\n")
        #expect(out.rows == [RosterImportRow(team: "Ballers", name: "Jordan Lee", email: "jordan@x.com")])
    }

    @Test func invalidEmailUnderHeaderIsDropped() {
        let out = RosterImportParser.parse("Team,Name,Email\nBallers,Jordan,not-an-email")
        #expect(out.rows.first?.email == nil)
    }

    @Test func emptyInput() {
        #expect(RosterImportParser.parse("  \n\n").rows.isEmpty)
    }
}
