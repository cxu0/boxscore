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

    func signUp(email: String, password: String, displayName: String, role: UserRole) async throws {
        try await client.auth.signUp(
            email: email,
            password: password,
            data: [
                "display_name": .string(displayName),
                "role": .string(role.rawValue)
            ]
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

    func signOut() async throws {
        try await client.auth.signOut()
        profile = nil
    }
}
