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
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("START A\nLEAGUE")
                                .font(.display(38))
                                .padding(.top, 8)
                            Text("Name it, share one join code, and your players add themselves. That's the whole setup.")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)

                            SectionHeaderText("League name")
                            BrandTextField(placeholder: "e.g. Tuesday Night Hoops", text: $name)

                            Toggle(isOn: $isPublic) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Public league")
                                        .font(.system(size: 15, weight: .bold))
                                    Text("Discoverable by players near you")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .tint(Brand.orange)
                            .brandCard()

                            if let errorMessage {
                                ErrorBanner(message: errorMessage)
                            }

                            Button {
                                Task { await create(ownerId: profile.id) }
                            } label: {
                                if isSubmitting {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Create League")
                                }
                            }
                            .buttonStyle(BrandPrimaryButtonStyle())
                            .disabled(name.isEmpty || isSubmitting)
                            .opacity(name.isEmpty ? 0.5 : 1)
                        }
                        .padding(.horizontal, 18)
                    }
                } else {
                    SignInPromptView(message: "Sign in to create and run your own league.")
                }
            }
            .toolbar(.hidden, for: .navigationBar)
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
