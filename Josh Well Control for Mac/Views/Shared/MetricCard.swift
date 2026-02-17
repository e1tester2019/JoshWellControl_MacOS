import SwiftUI

/// Lightweight metric tile that can be reused throughout the workspace.
struct MetricCard: View {
    enum Style { case standard, compact }

    let title: String
    let value: String
    var caption: String?
    var icon: String?
    var accent: Color = .accentColor
    var style: Style = .standard

    private var valueFontSize: CGFloat { style == .compact ? 17 : 22 }
    private var padding: CGFloat { style == .compact ? 10 : 14 }
    private var cornerRadius: CGFloat { style == .compact ? 12 : 16 }

    var body: some View {
        VStack(alignment: .leading, spacing: style == .compact ? 4 : 6) {
            if let icon {
                Label(title, systemImage: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: valueFontSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(accent.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(accent.opacity(0.25), lineWidth: 1)
        )
    }
}
