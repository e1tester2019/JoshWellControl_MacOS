import SwiftUI

/// Unified section header used across all views.
/// Replaces ad-hoc header patterns (plain Text, icon+title HStacks, custom sectionHeader helpers).
struct StandardSectionHeader<Trailing: View>: View {
    let title: String
    var icon: String? = nil
    var subtitle: String? = nil
    var accent: Color = .accentColor
    let trailing: Trailing

    init(
        title: String,
        icon: String? = nil,
        subtitle: String? = nil,
        accent: Color = .accentColor,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.icon = icon
        self.subtitle = subtitle
        self.accent = accent
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            if let icon {
                Image(systemName: icon)
                    .foregroundStyle(accent.gradient)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            trailing
        }
    }
}
