import SwiftUI

/// The floating pill tab bar: three plain icon+label tabs plus an elevated
/// orange Create button. The selected tab (and a tapped Create) pops —
/// grows slightly and gains a shadow — via a spring animation.
struct CustomTabBar: View {
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 0) {
            tabButton(tag: 0, icon: "house", filledIcon: "house.fill", label: "Home")
            tabButton(tag: 1, icon: "trophy", filledIcon: "trophy.fill", label: "Leagues")
            createButton
            tabButton(tag: 3, icon: "person.crop.circle", filledIcon: "person.crop.circle.fill", label: "Me")
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(
            Capsule(style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    private func tabButton(tag: Int, icon: String, filledIcon: String, label: String) -> some View {
        let selected = selection == tag
        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.65)) { selection = tag }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: selected ? filledIcon : icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(selected ? Brand.orange : .secondary)
                    .frame(width: 42, height: 30)
                    .background(Capsule().fill(selected ? Brand.orange.opacity(0.14) : .clear))
                    .scaleEffect(selected ? 1.1 : 1.0)
                    .shadow(color: selected ? Brand.orange.opacity(0.22) : .clear, radius: selected ? 6 : 0, y: selected ? 2 : 0)
                Text(label)
                    .font(.system(size: 10, weight: selected ? .bold : .medium))
                    .foregroundStyle(selected ? Brand.orange : .secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var createButton: some View {
        let selected = selection == 2
        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.6)) { selection = 2 }
        } label: {
            ZStack {
                Circle()
                    .fill(Brand.orange)
                    .frame(width: selected ? 60 : 54, height: selected ? 60 : 54)
                    .shadow(color: Brand.orange.opacity(selected ? 0.45 : 0.28), radius: selected ? 14 : 7, y: selected ? 6 : 3)
                Image(systemName: "plus")
                    .font(.system(size: selected ? 25 : 22, weight: .bold))
                    .foregroundStyle(.white)
            }
            .offset(y: -14)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
