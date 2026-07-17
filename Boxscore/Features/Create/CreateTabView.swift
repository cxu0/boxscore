import SwiftUI

struct CreateTabView: View {
    let profile: Profile?

    @StateObject private var leagueService = LeagueService()
    @State private var name = ""
    @State private var isPublic = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var createdLeague: League?

    var body: some View {
        NavigationStack {
            Group {
                if let profile {
                    Form {
                        Section("New League") {
                            TextField("League Name", text: $name)
                            Toggle("Public — discoverable by nearby players", isOn: $isPublic)
                        }
                        if let errorMessage {
                            ErrorBanner(message: errorMessage)
                        }
                        Section {
                            Button {
                                Task { await create(ownerId: profile.id) }
                            } label: {
                                if isSubmitting {
                                    ProgressView()
                                } else {
                                    Text("Create League").frame(maxWidth: .infinity)
                                }
                            }
                            .disabled(name.isEmpty || isSubmitting)
                        }
                    }
                } else {
                    SignInPromptView(message: "Sign in to create and run your own league.")
                }
            }
            .navigationTitle("Create")
            .navigationDestination(item: $createdLeague) { league in
                LeagueDetailView(league: league)
            }
        }
    }

    private func create(ownerId: UUID) async {
        isSubmitting = true
        errorMessage = nil
        do {
            let league = try await leagueService.createLeague(name: name, isPublic: isPublic, ownerId: ownerId)
            name = ""
            isPublic = false
            createdLeague = league
        } catch {
            errorMessage = error.localizedDescription
        }
        isSubmitting = false
    }
}
