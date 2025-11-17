import SwiftUI

/// Lightweight metric tile that can be reused throughout the workspace.
struct MetricCard: View {
    let title: String
    let value: String
    var caption: String?
    var icon: String?
    var accent: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(accent.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(accent.opacity(0.25), lineWidth: 1)
        )
    }
}
