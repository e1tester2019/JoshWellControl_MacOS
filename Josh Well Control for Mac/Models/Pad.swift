//
//  Pad.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-12-09.
//

import Foundation
import SwiftData

@Model
final class Pad {
    var id: UUID = UUID()
    var name: String = "New Pad"
    var surfaceLocation: String = ""
    var directions: String = ""
    var latitude: Double? = nil
    var longitude: Double? = nil
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var isLocked: Bool = false

    @Relationship(deleteRule: .nullify, inverse: \Well.pad) var wells: [Well]?
    @Relationship(deleteRule: .cascade, inverse: \WellTask.pad) var tasks: [WellTask]?
    @Relationship(deleteRule: .cascade, inverse: \HandoverNote.pad) var notes: [HandoverNote]?

    init(name: String = "New Pad", surfaceLocation: String = "", latitude: Double? = nil, longitude: Double? = nil) {
        self.name = name
        self.surfaceLocation = surfaceLocation
        self.latitude = latitude
        self.longitude = longitude
    }

    var wellsSorted: [Well] {
        (wells ?? []).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Pad's own tasks/notes

    var padTasks: [WellTask] {
        tasks ?? []
    }

    var padNotes: [HandoverNote] {
        notes ?? []
    }

    var pendingPadTasks: [WellTask] {
        padTasks.filter { $0.isPending }.sorted { $0.priority.sortOrder < $1.priority.sortOrder }
    }

    var overduePadTasks: [WellTask] {
        padTasks.filter { $0.isOverdue }
    }

    // MARK: - All tasks/notes (pad + wells)

    var allTasks: [WellTask] {
        padTasks + (wells ?? []).flatMap { $0.tasks ?? [] }
    }

    var allNotes: [HandoverNote] {
        padNotes + (wells ?? []).flatMap { $0.notes ?? [] }
    }

    var pendingTaskCount: Int {
        allTasks.filter { $0.isPending }.count
    }

    var overdueTaskCount: Int {
        allTasks.filter { $0.isOverdue }.count
    }
}

import SwiftData

extension Pad {
    func createTask(title: String, description: String = "", priority: TaskPriority = .medium, dueDate: Date? = nil, author: String = "", context: ModelContext) -> WellTask {
        let task = WellTask(title: title, description: description, priority: priority, dueDate: dueDate, author: author)
        task.pad = self
        if tasks == nil { tasks = [] }
        tasks?.append(task)
        context.insert(task)
        return task
    }

    func createNote(title: String, content: String = "", category: NoteCategory = .general, author: String = "", isPinned: Bool = false, context: ModelContext) -> HandoverNote {
        let note = HandoverNote(title: title, content: content, category: category, author: author, isPinned: isPinned)
        note.pad = self
        if notes == nil { notes = [] }
        notes?.append(note)
        context.insert(note)
        return note
    }
}
