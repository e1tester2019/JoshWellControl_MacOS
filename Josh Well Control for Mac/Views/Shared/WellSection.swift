import SwiftUI

/// A reusable container that mirrors the clean card aesthetic used by the mud placement
/// and trip simulation screens. Provides a consistent chrome for every major section.
struct WellSection<Content: View>: View {
    let title: String
    var icon: String
    var subtitle: String?
    var spacing: CGFloat
    var trailing: AnyView?
    var isCollapsible: Bool
    let content: Content

    @State private var isExpanded: Bool = true

    init(
        title: String,
        icon: String = "square.grid.2x2",
        subtitle: String? = nil,
        spacing: CGFloat = 12,
        trailing: AnyView? = nil,
        isCollapsible: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.subtitle = subtitle
        self.spacing = spacing
        self.trailing = trailing
        self.isCollapsible = isCollapsible
        self.content = content()
    }

    private var backgroundBaseColor: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(.systemBackground)
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            HStack(alignment: .firstTextBaseline) {
                if isCollapsible {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Label(title, systemImage: icon)
                                .font(.headline)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    Label(title, systemImage: icon)
                        .font(.headline)
                }
                Spacer()
                if let trailing {
                    trailing
                }
            }
            if let subtitle, isExpanded || !isCollapsible {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if isExpanded || !isCollapsible {
                content
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [backgroundBaseColor, Color.accentColor.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.25).blendMode(.screen), lineWidth: 0.6)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 20, y: 8)
    }
}
