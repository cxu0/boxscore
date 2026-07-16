import SwiftUI

/// A compact tap target for incrementing/decrementing one stat category,
/// used inside the box score entry grid.
struct StatStepper: View {
    let label: String
    @Binding var value: Int

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button {
                    if value > 0 { value -= 1 }
                } label: {
                    Image(systemName: "minus.circle.fill")
                }
                .disabled(value == 0)

                Text("\(value)")
                    .font(.headline)
                    .frame(minWidth: 20)
                    .contentTransition(.numericText())

                Button {
                    value += 1
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
            }
            .buttonStyle(.plain)
            .font(.title3)
        }
    }
}
