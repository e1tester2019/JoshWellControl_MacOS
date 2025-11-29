import SwiftUI

/// A reusable container that mirrors the clean card aesthetic used by the mud placement
/// and trip simulation screens. Provides a consistent chrome for every major section.
struct WellSection<Content: View>: View {
    let title: String
    var icon: String
    var subtitle: String?
    var spacing: CGFloat
    var trailing: AnyView?
    let content: Content

    init(
        title: String,
        icon: String = "square.grid.2x2",
        subtitle: String? = nil,
        spacing: CGFloat = 12,
        trailing: AnyView? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.subtitle = subtitle
        self.spacing = spacing
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            HStack(alignment: .firstTextBaseline) {
                Label(title, systemImage: icon)
                    .font(.headline)
                Spacer()
                if let trailing {
                    trailing
                }
            }
            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            #if os(macOS)
                            Color(nsColor: .windowBackgroundColor),
                            #else
                            Color(.systemBackground),
                            #endif
                            Color.accentColor.opacity(0.08)
                        ],
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
