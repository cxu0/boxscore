import SwiftUI

/// A compact tap target for incrementing/decrementing one stat category,
/// used inside the box score entry grid. Muted minus, orange plus, value
/// in bold condensed numerals — matching the Boxscore design system.
struct StatStepper: View {
    let label: String
    @Binding var value: Int

    var body: some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .black).width(.condensed))
                .kerning(0.8)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.display(24))
                .monospacedDigit()
                .contentTransition(.numericText())
            HStack(spacing: 4) {
                Button {
                    if value > 0 { value -= 1 }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 26)
                        .background(Brand.card, in: RoundedRectangle(cornerRadius: 8))
                }
                .disabled(value == 0)
                .opacity(value == 0 ? 0.4 : 1)

                Button {
                    value += 1
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 26)
                        .background(Brand.orange, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Brand.card.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}
