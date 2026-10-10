import Foundation

/// Turns pasted spreadsheet text or a CSV file into roster rows.
///
/// Accepts tab-separated (what you get copying cells from Google Sheets /
/// Excel / Numbers) or comma-separated text. If the first row looks like a
/// header ("Team", "Name", "Email", "First Name", "Last Name"…) columns are
/// matched by name; otherwise the column containing "@" is the email and the
/// rest are read as Team, then Name.
enum RosterImportParser {
    struct Output: Equatable {
        var rows: [RosterImportRow] = []
        /// Lines that couldn't be read (missing team or name), 1-based.
        var badLines: [Int] = []
    }

    static func parse(_ text: String) -> Output {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        guard let firstNonEmpty = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            return Output()
        }

        let delimiter: Character = lines.contains { $0.contains("\t") } ? "\t" : ","
        let table = lines.map { split($0, by: delimiter) }

        var columns = Columns.positional
        var start = firstNonEmpty
        if let header = Columns(header: table[firstNonEmpty]) {
            columns = header
            start = firstNonEmpty + 1
        }

        var output = Output()
        for index in start..<table.count {
            let fields = table[index]
            if fields.allSatisfy({ $0.isEmpty }) { continue }
            if let row = columns.row(from: fields) {
                output.rows.append(row)
            } else {
                output.badLines.append(index + 1)
            }
        }
        return output
    }

    /// Splits one line, honoring double-quoted fields ("Smith, Jr.").
    private static func split(_ line: String, by delimiter: Character) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\"" {
                if inQuotes && i + 1 < chars.count && chars[i + 1] == "\"" {
                    current.append("\"")
                    i += 1
                } else {
                    inQuotes.toggle()
                }
            } else if c == delimiter && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(c)
            }
            i += 1
        }
        fields.append(current)
        return fields.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private struct Columns {
        var team: Int?
        var name: Int?
        var first: Int?
        var last: Int?
        var email: Int?
        /// No header: find the email by "@", then Team, Name in order.
        var isPositional = false

        static let positional = Columns(isPositional: true)

        init(team: Int? = nil, name: Int? = nil, first: Int? = nil, last: Int? = nil, email: Int? = nil, isPositional: Bool = false) {
            self.team = team; self.name = name; self.first = first; self.last = last
            self.email = email; self.isPositional = isPositional
        }

        /// nil when the row doesn't look like a header.
        init?(header fields: [String]) {
            let keys = fields.map { $0.lowercased() }
            guard !keys.contains(where: { $0.contains("@") }) else { return nil }
            for (i, key) in keys.enumerated() {
                if key.contains("email") || key.contains("e-mail") { email = email ?? i }
                else if key.contains("team") { team = team ?? i }
                else if key.contains("first") { first = first ?? i }
                else if key.contains("last") { last = last ?? i }
                else if key.contains("name") || key == "player" { name = name ?? i }
            }
            guard team != nil, name != nil || first != nil else { return nil }
        }

        func row(from fields: [String]) -> RosterImportRow? {
            func at(_ i: Int?) -> String? {
                guard let i, i < fields.count, !fields[i].isEmpty else { return nil }
                return fields[i]
            }

            if isPositional {
                let emailIndex = fields.firstIndex { $0.contains("@") }
                let rest = fields.enumerated().filter { $0.offset != emailIndex && !$0.element.isEmpty }.map(\.element)
                guard rest.count >= 2 else { return nil }
                return RosterImportRow(team: rest[0], name: rest[1], email: emailIndex.map { fields[$0].lowercased() })
            }

            let fullName = at(name) ?? [at(first), at(last)].compactMap { $0 }.joined(separator: " ")
            guard let teamName = at(team), !fullName.isEmpty else { return nil }
            let mail = at(email).flatMap { $0.contains("@") ? $0.lowercased() : nil }
            return RosterImportRow(team: teamName, name: fullName, email: mail)
        }
    }
}
