import SwiftUI

/// Unified empty state view used when a list, panel, or section has no data.
/// Replaces ad-hoc empty states (plain Text, custom VStacks with icons).
struct StandardEmptyState: View {
    let icon: String
    let title: String
    var description: String? = nil
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            if let description {
                Text(description)
            }
        } actions: {
            if let actionLabel, let action {
                Button(actionLabel, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
