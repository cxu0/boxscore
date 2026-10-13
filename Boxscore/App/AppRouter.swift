import Foundation
import Combine

/// Where the app should share links from and how it parses incoming ones.
/// NOTE: `linkDomain` must be a domain you own and have configured for Apple
/// universal links (see docs/universal-links-setup.md). Until then, links
/// still open in a browser to the fallback page, which shows the code.
enum AppConfig {
    static let linkDomain = "getboxscore.app"

    static func staffURL(code: String) -> URL { URL(string: "https://\(linkDomain)/keeper/\(code)")! }
    static func leagueURL(id: UUID) -> URL { URL(string: "https://\(linkDomain)/league/\(id.uuidString)")! }
}

/// Holds a pending deep-link destination for the UI to resolve and open.
@MainActor
final class AppRouter: ObservableObject {
    enum Destination: Equatable {
        case staffCode(String)
        case publicLeague(UUID)
    }

    @Published var pending: Destination?

    /// Parse a universal link / custom URL into a destination.
    func handle(_ url: URL) {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2 else { return }
        switch parts[0] {
        case "keeper":
            pending = .staffCode(parts[1].uppercased())
        case "league":
            if let id = UUID(uuidString: parts[1]) { pending = .publicLeague(id) }
        default:
            break
        }
    }
}
