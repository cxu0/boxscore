import SwiftUI

struct CreateTabView: View {
    let profile: Profile?

    @StateObject private var leagueService = LeagueService()
    @State private var name = ""
    @State private var format: LeagueFormat = .fiveOnFive
    @State private var isPublic = false
    @State private var startDate = Date()
    @State private var endDate = Date().addingTimeInterval(60 * 60 * 24 * 90)
    @State private var teamNames: [String] = []
    @State private var newTeamName = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var createdLeague: League?

    var body: some View {
        NavigationStack {
            Group {
                if let profile {
                    form(ownerId: profile.id)
                } else {
                    SignInPromptView(message: "Sign in to create and run your own league.")
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .brandBackground()
            .navigationDestination(item: $createdLeague) { league in
                LeagueDetailView(league: league)
            }
        }
    }

    private func form(ownerId: UUID) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NEW LEAGUE")
                        .font(.display(38))
                    Text("Set the basics. You can add games and stats later.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                field("League name") {
                    BrandTextField(placeholder: "e.g. Tuesday Night Hoops", text: $name)
                }

                field("Format") {
                    HStack(spacing: 8) {
                        ForEach(LeagueFormat.allCases, id: \.self) { option in
                            Button {
                                format = option
                            } label: {
                                Text(option.label)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(format == option ? .white : .primary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(
                                        format == option ? Brand.orange : Brand.card,
                                        in: RoundedRectangle(cornerRadius: 14)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                field("Season dates") {
                    HStack(spacing: 8) {
                        dateBox(label: "START", date: $startDate)
                        dateBox(label: "END", date: $endDate)
                    }
                }

                teamsField

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
                    Task { await create(ownerId: ownerId) }
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
            .padding(.bottom, 24)
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderText(label)
            content()
        }
    }

    private func dateBox(label: String, date: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .black).width(.condensed))
                .foregroundStyle(.secondary)
            DatePicker("", selection: date, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Brand.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private var teamsField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionHeaderText("Teams")
                Spacer()
                if !teamNames.isEmpty {
                    Text("\(teamNames.count) ADDED")
                        .font(.system(size: 11, weight: .black).width(.condensed))
                        .foregroundStyle(Brand.orange)
                }
            }
            FlowChips(items: teamNames, onDelete: { idx in teamNames.remove(at: idx) })
            HStack(spacing: 8) {
                BrandTextField(placeholder: "Add a team", text: $newTeamName)
                Button {
                    addTeam()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(Brand.orange, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(newTeamName.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(newTeamName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
            }
        }
    }

    private func addTeam() {
        let trimmed = newTeamName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        teamNames.append(trimmed)
        newTeamName = ""
    }

    private func create(ownerId: UUID) async {
        isSubmitting = true
        errorMessage = nil
        do {
            let league = try await leagueService.createLeague(
                name: name,
                isPublic: isPublic,
                format: format,
                ownerId: ownerId,
                startDate: startDate,
                endDate: endDate,
                teamNames: teamNames
            )
            resetForm()
            createdLeague = league
        } catch {
            errorMessage = error.localizedDescription
        }
        isSubmitting = false
    }

    private func resetForm() {
        name = ""
        format = .fiveOnFive
        isPublic = false
        teamNames = []
        newTeamName = ""
    }
}

/// Wrapping row of removable chips (added team names).
private struct FlowChips: View {
    let items: [String]
    let onDelete: (Int) -> Void

    var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            FlowLayout(spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, name in
                    HStack(spacing: 6) {
                        Text(name)
                            .font(.system(size: 14, weight: .bold))
                        Button {
                            onDelete(idx)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Brand.card, in: Capsule())
                }
            }
        }
    }
}

/// A simple flow layout: places subviews left-to-right, wrapping to a new row
/// when the current one runs out of width.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth == .infinity ? rowWidth : maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
