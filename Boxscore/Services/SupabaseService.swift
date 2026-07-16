import Foundation
import Supabase

/// Fill these in with your Supabase project's URL and anon (public) key,
/// found under Project Settings → API. The anon key is safe to ship in a
/// client app — Row Level Security on the database is what enforces access.
enum SupabaseConfig {
    static let url = URL(string: "https://nwkgbfdcbilxriyfmeuj.supabase.co")!
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im53a2diZmRjYmlseHJpeWZtZXVqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxNTg5NzQsImV4cCI6MjA5OTczNDk3NH0.k0P-4TIVj5GyFlfTMiG4U7dy1wCAcDVDdjq77-KnvwM"
}

enum SupabaseService {
    static let client: SupabaseClient = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        // Postgres hands back several date shapes through PostgREST: `timestamptz`
        // columns as ISO-8601 with or without fractional seconds, and `date`
        // columns (seasons.start_date/end_date) as bare `yyyy-MM-dd`. The stock
        // `.iso8601` strategy only parses the first, so date-only values fail to
        // decode and whole rows silently drop. Parse all shapes here.
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            if let date = PostgresDate.parse(string) { return date }
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Unrecognized date format: \(string)"
            )
        }

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        // Encode every Date as a full ISO-8601 timestamp. Postgres truncates it
        // when the target column is `date`, so this is safe for both `date` and
        // `timestamptz` columns.
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(PostgresDate.iso8601WithFractional.string(from: date))
        }

        return SupabaseClient(
            supabaseURL: SupabaseConfig.url,
            supabaseKey: SupabaseConfig.anonKey,
            options: SupabaseClientOptions(
                db: .init(encoder: encoder, decoder: decoder)
            )
        )
    }()
}

/// Date parsing/formatting for the shapes PostgREST returns.
private enum PostgresDate {
    static let iso8601WithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// `date` columns come back as `yyyy-MM-dd` with no time or zone.
    static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func parse(_ string: String) -> Date? {
        iso8601WithFractional.date(from: string)
            ?? iso8601.date(from: string)
            ?? dateOnly.date(from: string)
    }
}
