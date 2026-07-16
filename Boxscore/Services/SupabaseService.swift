import Foundation
import Supabase

/// Fill these in with your Supabase project's URL and anon (public) key,
/// found under Project Settings → API. The anon key is safe to ship in a
/// client app — Row Level Security on the database is what enforces access.
enum SupabaseConfig {
    static let url = URL(string: "https://YOUR_PROJECT_REF.supabase.co")!
    static let anonKey = "YOUR_SUPABASE_ANON_KEY"
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
