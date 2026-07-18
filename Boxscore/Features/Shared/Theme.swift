import SwiftUI

/// The Boxscore design system, translated from the Figma Make prototype:
/// confident orange, bold condensed display type for headlines and stat
/// numerals, card-based layout, automatic light/dark support.
enum Brand {
    /// #FF5F1F
    static let orange = Color(red: 1.0, green: 0.373, blue: 0.122)

    /// Card surface — adapts to light/dark like the prototype's #F6F6F6 / #1C1C1C.
    static let card = Color(.secondarySystemBackground)

    /// Subtle hairline border used on cards.
    static let border = Color.primary.opacity(0.08)

    /// Positive/negative accents for W/L, records, etc.
    static let win = Color.green
    static let loss = Color.red.opacity(0.85)
}

extension Font {
    /// The display face: SF condensed at black weight — the native stand-in
    /// for the prototype's Barlow Condensed headlines and stat numerals.
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black).width(.condensed)
    }
}

/// ALL-CAPS micro section header ("CAREER STATS", "MY LEAGUES", ...).
struct SectionHeaderText: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .black).width(.condensed))
            .kerning(1.8)
            .foregroundStyle(.secondary)
    }
}

/// Rounded card container matching the prototype's card style.
struct BrandCard: ViewModifier {
    var padding: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Brand.border, lineWidth: 1)
            )
    }
}

extension View {
    func brandCard(padding: CGFloat = 14) -> some View {
        modifier(BrandCard(padding: padding))
    }
}

/// Big-number stat tile (PPG / RPG / APG / FG%).
struct BigStatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.display(26))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .kerning(0.5)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Brand.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Brand.border, lineWidth: 1)
        )
    }
}

/// The BOXSCORE wordmark.
struct Wordmark: View {
    var size: CGFloat = 28

    var body: some View {
        Text("BOXSCORE")
            .font(.display(size))
            .foregroundStyle(Brand.orange)
    }
}

/// Primary filled action button (orange pill).
struct BrandPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                Brand.orange.opacity(configuration.isPressed ? 0.8 : 1),
                in: RoundedRectangle(cornerRadius: 16)
            )
    }
}

/// Secondary bordered action button.
struct BrandSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                Brand.card.opacity(configuration.isPressed ? 0.6 : 1),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Brand.border, lineWidth: 1)
            )
    }
}
