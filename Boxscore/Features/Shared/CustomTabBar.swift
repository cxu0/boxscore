import SwiftUI

/// Flat bottom tab bar: outline icons with condensed caps labels, the current
/// tab tinted orange, and a raised orange Create button in the middle.
struct CustomTabBar: View {
    @Binding var selection: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            tabButton(tag: 0, icon: "house", selectedIcon: "house.fill", label: "HOME")
            tabButton(tag: 1, icon: "line.3.horizontal", selectedIcon: "line.3.horizontal", label: "LEAGUES")
            createButton
            tabButton(tag: 3, icon: "person", selectedIcon: "person.fill", label: "ME")
        }
        .padding(.top, 8)
        .padding(.bottom, 2)
        .background(
            Brand.card
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) { Rectangle().fill(Brand.border).frame(height: 1) }
        )
    }

    private func tabButton(tag: Int, icon: String, selectedIcon: String, label: String) -> some View {
        let selected = selection == tag
        return Button {
            selection = tag
        } label: {
            VStack(spacing: 5) {
                Image(systemName: selected ? selectedIcon : icon)
                    .font(.system(size: 21, weight: .regular))
                    .frame(height: 26)
                Text(label)
                    .font(.system(size: 10, weight: .black).width(.condensed))
                    .kerning(0.8)
            }
            .foregroundStyle(selected ? Brand.orange : Color.primary.opacity(0.75))
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var createButton: some View {
        let selected = selection == 2
        return Button {
            selection = 2
        } label: {
            VStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Brand.orange)
                    .frame(width: 42, height: 42)
                    .shadow(color: Brand.orange.opacity(0.35), radius: 6, y: 3)
                    .overlay(
                        Image(systemName: "plus")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(.white)
                    )
                    .offset(y: -6)
                    .padding(.bottom, -6)
                Text("CREATE")
                    .font(.system(size: 10, weight: .black).width(.condensed))
                    .kerning(0.8)
                    .foregroundStyle(selected ? Brand.orange : Color.primary.opacity(0.75))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
