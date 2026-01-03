//
//  QuickNoteManager.swift
//  Josh Well Control for Mac
//
//  Global state for quick-adding notes and tasks from anywhere in the app
//

import Foundation
import SwiftUI
import SwiftData

/// Type of item to quick-add
enum QuickAddType: String, CaseIterable {
    case note = "Note"
    case task = "Task"

    var icon: String {
        switch self {
        case .note: return "note.text"
        case .task: return "checkmark.circle"
        }
    }
}

/// Global manager for quick note/task creation
@Observable
@MainActor
final class QuickNoteManager {
    static let shared = QuickNoteManager()

    // MARK: - Sheet State

    var quickAddType: QuickAddType = .note
    var showNoteEditor = false
    var showTaskEditor = false

    // MARK: - Save Guards (shared across all view instances)

    /// Prevents duplicate note saves across all NoteEditorView instances
    var isSavingNote = false
    /// Prevents duplicate task saves across all TaskEditorView instances
    var isSavingTask = false

    // MARK: - Current Context (set by active view)

    var currentWell: Well?
    var currentProject: ProjectState?
    var currentPad: Pad?

    // MARK: - Pending Item Data

    var pendingTitle: String = ""
    var pendingContent: String = ""
    var pendingCategory: NoteCategory = .general
    var pendingPriority: TaskPriority = .medium
    var pendingDueDate: Date?
    var pendingIsPinned: Bool = false

    // MARK: - Badges

    /// Count of pending tasks across all wells (for badge display)
    var pendingTaskCount: Int = 0
    /// Count of overdue tasks (for urgent badge)
    var overdueTaskCount: Int = 0

    private init() {}

    // MARK: - Quick Actions

    /// Shows the quick-add sheet for notes
    func showAddNote() {
        resetPendingData()
        quickAddType = .note
        showNoteEditor = true
    }

    /// Shows the quick-add sheet for tasks
    func showAddTask() {
        resetPendingData()
        quickAddType = .task
        showTaskEditor = true
    }

    /// Dismisses the quick-add sheet
    func dismiss() {
        showNoteEditor = false
        showTaskEditor = false
        resetPendingData()
    }

    // MARK: - Context Management

    /// Updates the current context when well/project changes
    func updateContext(well: Well?, project: ProjectState?) {
        currentWell = well
        currentProject = project
        currentPad = well?.pad
    }

    // MARK: - Creation

    /// Creates a note with the current pending data
    /// - Parameter context: SwiftData model context
    /// - Returns: The created note, or nil if no well is set
    @discardableResult
    func createNote(context: ModelContext) -> HandoverNote? {
        guard let well = currentWell else { return nil }
        guard !pendingTitle.isEmpty else { return nil }

        let note = HandoverNote(
            title: pendingTitle,
            content: pendingContent,
            category: pendingCategory,
            author: "", // Could be set from user preferences
            isPinned: pendingIsPinned
        )
        context.insert(note)
        // SwiftData automatically manages the inverse relationship
        note.well = well
        note.project = currentProject
        note.pad = currentPad

        try? context.save()
        dismiss()
        return note
    }

    /// Creates a task with the current pending data
    /// - Parameter context: SwiftData model context
    /// - Returns: The created task, or nil if no well is set
    @discardableResult
    func createTask(context: ModelContext) -> WellTask? {
        guard let well = currentWell else { return nil }
        guard !pendingTitle.isEmpty else { return nil }

        let task = WellTask(
            title: pendingTitle,
            description: pendingContent,
            priority: pendingPriority,
            status: .pending,
            dueDate: pendingDueDate,
            author: ""
        )
        context.insert(task)
        // SwiftData automatically manages the inverse relationship
        task.well = well
        task.project = currentProject
        task.pad = currentPad

        try? context.save()
        dismiss()
        return task
    }

    // MARK: - Badge Updates

    /// Updates task counts for badge display
    /// - Parameter wells: All wells to count tasks from
    func updateTaskCounts(from wells: [Well]) {
        var pending = 0
        var overdue = 0

        for well in wells {
            for task in well.tasks ?? [] {
                if task.isPending {
                    pending += 1
                    if task.isOverdue {
                        overdue += 1
                    }
                }
            }
        }

        pendingTaskCount = pending
        overdueTaskCount = overdue
    }

    // MARK: - Private

    private func resetPendingData() {
        pendingTitle = ""
        pendingContent = ""
        pendingCategory = .general
        pendingPriority = .medium
        pendingDueDate = nil
        pendingIsPinned = false
    }
}
