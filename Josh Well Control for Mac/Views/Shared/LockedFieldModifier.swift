//
//  LockedFieldModifier.swift
//  Josh Well Control for Mac
//
//  View modifier that disables fields when a project is being edited in another window
//

import SwiftUI

/// View modifier that shows a lock indicator and disables interaction when locked
struct LockedFieldModifier: ViewModifier {
    let isLocked: Bool
    let onLockedTap: (() -> Void)?

    @State private var showingLockAlert = false

    func body(content: Content) -> some View {
        content
            .disabled(isLocked)
            .opacity(isLocked ? 0.6 : 1.0)
            .overlay(alignment: .trailing) {
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.trailing, 8)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if isLocked {
                    if let onLockedTap {
                        onLockedTap()
                    } else {
                        showingLockAlert = true
                    }
                }
            }
            .alert("Field Locked", isPresented: $showingLockAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This project is being edited in another window. Close that window or wait for the lock to expire to edit here.")
            }
    }
}

/// Container that wraps content with project-aware locking
struct LockableField<Content: View>: View {
    let projectID: UUID
    @Environment(\.windowID) private var windowID
    let content: Content

    @State private var showingLockAlert = false

    init(projectID: UUID, @ViewBuilder content: () -> Content) {
        self.projectID = projectID
        self.content = content()
    }

    private var isLocked: Bool {
        ProjectLockingService.shared.isLocked(projectID, byOtherThan: windowID)
    }

    var body: some View {
        content
            .disabled(isLocked)
            .opacity(isLocked ? 0.6 : 1.0)
            .overlay(alignment: .trailing) {
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.trailing, 8)
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture().onEnded {
                    if isLocked {
                        showingLockAlert = true
                    }
                }
            )
            .alert("Field Locked", isPresented: $showingLockAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This project is being edited in another window.")
            }
            .onChange(of: isLocked) { wasLocked, nowLocked in
                // When we gain access, refresh the lock for this window
                if wasLocked && !nowLocked {
                    ProjectLockingService.shared.acquireLock(for: projectID, windowID: windowID)
                }
            }
    }
}

/// TextField that automatically acquires/releases locks
struct LockingTextField: View {
    let label: String
    @Binding var text: String
    let projectID: UUID

    @Environment(\.windowID) private var windowID
    @FocusState private var isFocused: Bool

    private var isLocked: Bool {
        ProjectLockingService.shared.isLocked(projectID, byOtherThan: windowID)
    }

    var body: some View {
        TextField(label, text: $text)
            .textFieldStyle(.roundedBorder)
            .focused($isFocused)
            .disabled(isLocked)
            .opacity(isLocked ? 0.6 : 1.0)
            .overlay(alignment: .trailing) {
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.trailing, 8)
                }
            }
            .onChange(of: isFocused) { _, nowFocused in
                if nowFocused {
                    // Acquire lock when editing starts
                    ProjectLockingService.shared.acquireLock(
                        for: projectID,
                        windowID: windowID,
                        fieldPath: label
                    )
                } else {
                    // Release lock when editing ends
                    ProjectLockingService.shared.releaseLock(for: projectID, windowID: windowID)
                }
            }
    }
}

// MARK: - View Extensions

extension View {
    /// Makes this view lockable based on project editing state
    /// - Parameters:
    ///   - isLocked: Whether the field should be locked
    ///   - onLockedTap: Optional callback when user taps a locked field
    /// - Returns: Modified view
    func lockable(isLocked: Bool, onLockedTap: (() -> Void)? = nil) -> some View {
        modifier(LockedFieldModifier(isLocked: isLocked, onLockedTap: onLockedTap))
    }

    /// Wraps content in a project-aware locking container
    /// - Parameter projectID: The project ID to check locks against
    /// - Returns: View wrapped in LockableField
    func projectLockable(_ projectID: UUID) -> some View {
        LockableField(projectID: projectID) { self }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Locked Field States") {
    VStack(spacing: 20) {
        GroupBox("Unlocked") {
            TextField("Name", text: .constant("Test Well"))
                .textFieldStyle(.roundedBorder)
                .lockable(isLocked: false)
        }

        GroupBox("Locked") {
            TextField("Name", text: .constant("Test Well"))
                .textFieldStyle(.roundedBorder)
                .lockable(isLocked: true)
        }
    }
    .padding()
    .frame(width: 300)
}
#endif
