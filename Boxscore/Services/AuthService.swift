import Foundation
import Combine
import Supabase

@MainActor
final class AuthService: ObservableObject {
    @Published private(set) var profile: Profile?
    @Published private(set) var isLoading = true

    private let client = SupabaseService.client

    func start() async {
        for await state in client.auth.authStateChanges {
            if let user = state.session?.user {
                await loadProfile(userId: user.id)
            } else {
                profile = nil
            }
            isLoading = false
        }
    }

    func loadProfile(userId: UUID) async {
        do {
            profile = try await client
                .from("profiles")
                .select()
                .eq("id", value: userId)
                .single()
                .execute()
                .value
        } catch {
            profile = nil
        }
    }

    func signUp(email: String, password: String, displayName: String) async throws {
        try await client.auth.signUp(
            email: email,
            password: password,
            data: ["display_name": .string(displayName)]
        )
        if let userId = try? await client.auth.session.user.id {
            await loadProfile(userId: userId)
        }
    }

    func signIn(email: String, password: String) async throws {
        try await client.auth.signIn(email: email, password: password)
        let userId = try await client.auth.session.user.id
        await loadProfile(userId: userId)
    }

    /// Reads any user's public profile by id — used to open another player's
    /// read-only profile from a roster.
    func fetchProfile(id: UUID) async throws -> Profile {
        try await client
            .from("profiles")
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value
    }

    func updateDisplayName(_ name: String) async throws {
        let userId = try await client.auth.session.user.id
        try await client
            .from("profiles")
            .update(["display_name": name])
            .eq("id", value: userId)
            .execute()
        await loadProfile(userId: userId)
    }

    func signOut() async throws {
        try await client.auth.signOut()
        profile = nil
    }

    /// Uploads a headshot to the user's own folder in the public `avatars`
    /// bucket, saves its URL on the profile, and refreshes local state. A
    /// cache-busting query param forces the UI to reload the new image.
    func updateAvatar(imageData: Data) async throws {
        let userId = try await client.auth.session.user.id
        // Lowercased: Swift's uuidString is UPPERCASE, but the storage RLS
        // policy compares the folder to auth.uid()::text, which is lowercase.
        let path = "\(userId.uuidString.lowercased())/headshot.jpg"

        try await client.storage
            .from("avatars")
            .upload(
                path,
                data: imageData,
                options: FileOptions(cacheControl: "3600", contentType: "image/jpeg", upsert: true)
            )

        let publicURL = try client.storage.from("avatars").getPublicURL(path: path)
        let bustedURL = "\(publicURL.absoluteString)?v=\(Int(Date().timeIntervalSince1970))"

        try await client
            .from("profiles")
            .update(["avatar_url": bustedURL])
            .eq("id", value: userId)
            .execute()

        await loadProfile(userId: userId)
    }
}
