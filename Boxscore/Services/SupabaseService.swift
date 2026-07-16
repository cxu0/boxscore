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
        decoder.dateDecodingStrategy = .iso8601

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601

        return SupabaseClient(
            supabaseURL: SupabaseConfig.url,
            supabaseKey: SupabaseConfig.anonKey,
            options: SupabaseClientOptions(
                db: .init(encoder: encoder, decoder: decoder)
            )
        )
    }()
}
