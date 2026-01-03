//
//  QuickAddButton.swift
//  Josh Well Control for Mac
//
//  Toolbar button for quick-adding notes/tasks with badge
//

import SwiftUI

/// Toolbar button that shows a badge and provides quick access to notes/tasks
struct QuickAddButton: View {
    @Bindable var manager: QuickNoteManager

    var body: some View {
        Menu {
            Button(action: { manager.showNoteEditor = true }) {
                Label("Add Note", systemImage: "note.text.badge.plus")
            }

            Button(action: { manager.showTaskEditor = true }) {
                Label("Add Task", systemImage: "checkmark.circle.badge.plus")
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "plus.circle")
                    .font(.title2)

                // Badge
                if manager.overdueTaskCount > 0 {
                    BadgeView(count: manager.overdueTaskCount, color: .red)
                } else if manager.pendingTaskCount > 0 {
                    BadgeView(count: manager.pendingTaskCount, color: .blue)
                }
            }
        } primaryAction: {
            // Primary tap adds a note
            manager.showNoteEditor = true
        }
        .help("Quick Add (Cmd+Shift+N)")
        .keyboardShortcut("n", modifiers: [.command, .shift])
    }
}

/// Badge overlay for counts
private struct BadgeView: View {
    let count: Int
    let color: Color

    var body: some View {
        Text("\(min(count, 99))")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                Capsule()
                    .fill(color)
            )
            .offset(x: 6, y: -4)
    }
}

// MARK: - View Modifier for Integration

/// Adds quick-add sheets to any view (button should be added separately to toolbar)
struct QuickAddSheetModifier: ViewModifier {
    @Bindable var manager: QuickNoteManager

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $manager.showNoteEditor) {
                NoteEditorView()
            }
            .sheet(isPresented: $manager.showTaskEditor) {
                TaskEditorView()
            }
    }
}

extension View {
    /// Attaches the quick-add sheets to this view
    func quickAddSheet(manager: QuickNoteManager) -> some View {
        modifier(QuickAddSheetModifier(manager: manager))
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Quick Add Button") {
    QuickAddButton(manager: QuickNoteManager.shared)
        .padding()
}
#endif
