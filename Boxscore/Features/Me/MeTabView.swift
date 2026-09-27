import SwiftUI

struct MeTabView: View {
    let profile: Profile?

    @EnvironmentObject private var auth: AuthService
    @State private var isEditingName = false
    @State private var nameText = ""

    var body: some View {
        NavigationStack {
            Group {
                if let profile {
                    ProfileView(profile: profile)
                        .toolbar(.hidden, for: .navigationBar)
                        .brandBackground()
                        .overlay(alignment: .topTrailing) {
                            Menu {
                                Button {
                                    nameText = auth.profile?.displayName ?? profile.displayName
                                    isEditingName = true
                                } label: { Label("Edit Name", systemImage: "pencil") }
                                Button(role: .destructive) {
                                    Task { try? await auth.signOut() }
                                } label: { Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right") }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .padding(10)
                                    .background(.white.opacity(0.12), in: Circle())
                            }
                            .padding(.trailing, 16)
                            .padding(.top, 8)
                        }
                        .alert("Edit name", isPresented: $isEditingName) {
                            TextField("Your name", text: $nameText)
                            Button("Save") {
                                let name = nameText.trimmingCharacters(in: .whitespaces)
                                if !name.isEmpty { Task { try? await auth.updateDisplayName(name) } }
                            }
                            Button("Cancel", role: .cancel) {}
                        }
                } else {
                    SignInPromptView(message: "Sign in to see your career stats and teams.")
                        .toolbar(.hidden, for: .navigationBar)
                        .brandBackground()
                }
            }
        }
    }
}
