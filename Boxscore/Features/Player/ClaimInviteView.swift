import SwiftUI

struct ClaimInviteView: View {
    let onClaimed: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var rosterService = RosterService()
    @State private var code = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                TextField("Invite Code", text: $code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            } footer: {
                Text("Get this code from your team's commissioner.")
            }
            if let errorMessage {
                ErrorBanner(message: errorMessage)
            }
            Section {
                Button {
                    Task { await claim() }
                } label: {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Text("Join Team").frame(maxWidth: .infinity)
                    }
                }
                .disabled(code.isEmpty || isSubmitting)
            }
        }
        .navigationTitle("Join a Team")
    }

    private func claim() async {
        isSubmitting = true
        errorMessage = nil
        do {
            _ = try await rosterService.claimInvite(code: code.uppercased())
            onClaimed()
            dismiss()
        } catch {
            errorMessage = "That invite code isn't valid or has already been claimed."
        }
        isSubmitting = false
    }
}
