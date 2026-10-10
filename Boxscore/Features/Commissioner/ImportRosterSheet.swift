import SwiftUI
import UniformTypeIdentifiers

/// Owner-only: bring a whole league's rosters in from the spreadsheet the
/// organizer already has (paste cells or pick a CSV). Players with an email
/// are added to their team automatically when they sign up.
struct ImportRosterSheet: View {
    let league: League
    let onDone: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var rosterService = RosterService()

    @State private var text = ""
    @State private var parsed = RosterImportParser.Output()
    @State private var isPickingFile = false
    @State private var isImporting = false
    @State private var result: RosterImportResult?
    @State private var errorMessage: String?

    private var byTeam: [(team: String, rows: [RosterImportRow])] {
        var order: [String] = []
        var groups: [String: [RosterImportRow]] = [:]
        for row in parsed.rows {
            let key = row.team.lowercased()
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(row)
        }
        return order.map { (groups[$0]![0].team, groups[$0]!) }
    }

    private var missingEmail: Int { parsed.rows.filter { $0.email == nil }.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let result {
                        resultView(result)
                    } else {
                        inputSection
                        if !parsed.rows.isEmpty || !parsed.badLines.isEmpty {
                            previewSection
                        }
                        if let errorMessage {
                            ErrorBanner(message: errorMessage)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
            .brandBackground()
            .navigationTitle("Import Rosters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if result == nil { Button("Cancel") { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if result != nil {
                        Button("Done") { dismiss() }
                    } else {
                        Button {
                            Task { await runImport() }
                        } label: {
                            if isImporting { ProgressView() } else { Text("Import") }
                        }
                        .disabled(parsed.rows.isEmpty || isImporting)
                    }
                }
            }
            .fileImporter(
                isPresented: $isPickingFile,
                allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText]
            ) { picked in
                loadFile(picked)
            }
            .onChange(of: text) { _, newText in
                parsed = RosterImportParser.parse(newText)
            }
        }
    }

    // MARK: Input

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bring in your rosters")
                .font(.display(28))
                .padding(.top, 8)
            Text("Copy the **Team**, **Name** and **Email** columns from your league spreadsheet and paste them here — or pick a CSV export. Players are added to their team automatically when they sign up with that email.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                PasteButton(payloadType: String.self) { strings in
                    if let pasted = strings.first { text = pasted }
                }
                .buttonBorderShape(.capsule)
                .tint(Brand.orange)

                Button {
                    isPickingFile = true
                } label: {
                    Label("Choose CSV", systemImage: "doc")
                        .font(.system(size: 14, weight: .bold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(Brand.orange)
            }

            TextEditor(text: $text)
                .font(.system(size: 13, design: .monospaced))
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(Brand.card, in: RoundedRectangle(cornerRadius: 14))
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Team, Name, Email\nBallers, Jordan Lee, jordan@email.com")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(16)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    // MARK: Preview

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeaderText("Preview")
            HStack(spacing: 8) {
                BigStatTile(value: "\(byTeam.count)", label: "TEAMS")
                BigStatTile(value: "\(parsed.rows.count)", label: "PLAYERS")
            }

            if missingEmail > 0 {
                warning("\(missingEmail) player\(missingEmail == 1 ? "" : "s") without an email won't be matched automatically. You can add emails later from the team page.")
            }
            if !parsed.badLines.isEmpty {
                warning("Skipping \(parsed.badLines.count) line\(parsed.badLines.count == 1 ? "" : "s") missing a team or name (line \(parsed.badLines.prefix(5).map(String.init).joined(separator: ", "))\(parsed.badLines.count > 5 ? "…" : "")).")
            }

            ForEach(byTeam, id: \.team) { group in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        TeamCrest(name: group.team)
                        Text(group.team).font(.display(20))
                        Spacer()
                        Text("\(group.rows.count)")
                            .font(.display(18))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(group.rows) { row in
                        HStack {
                            Text(row.name).font(.system(size: 14, weight: .semibold))
                            Spacer()
                            Text(row.email ?? "no email")
                                .font(.system(size: 12))
                                .foregroundStyle(row.email == nil ? .orange : .secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .brandCard(padding: 14)
            }
        }
    }

    private func warning(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .brandCard(padding: 12)
    }

    // MARK: Result

    private func resultView(_ result: RosterImportResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Brand.orange)
                .padding(.top, 24)
            Text("Rosters imported")
                .font(.display(32))
            HStack(spacing: 8) {
                BigStatTile(value: "\(result.playersAdded)", label: "PLAYERS")
                BigStatTile(value: "\(result.teamsCreated)", label: "NEW TEAMS")
            }
            if result.alreadyJoined > 0 {
                Text("\(result.alreadyJoined) already on Boxscore — they're on their teams now.")
                    .font(.system(size: 14))
            }
            if result.skipped > 0 {
                Text("\(result.skipped) skipped (missing info, or that email is already on a roster this season).")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Text("Everyone else joins their team the moment they sign up with the email you imported.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Actions

    private func loadFile(_ picked: Result<URL, Error>) {
        do {
            let url = try picked.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            errorMessage = "Couldn't read that file: \(error.localizedDescription)"
        }
    }

    private func runImport() async {
        isImporting = true
        errorMessage = nil
        do {
            result = try await rosterService.importRoster(leagueId: league.id, rows: parsed.rows)
            await onDone()
        } catch {
            errorMessage = error.localizedDescription
        }
        isImporting = false
    }
}
