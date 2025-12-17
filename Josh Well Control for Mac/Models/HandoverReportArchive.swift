//
//  HandoverReportArchive.swift
//  Josh Well Control for Mac
//
//  Archive of exported handover reports for reference
//

import Foundation
import SwiftData

/// Archived handover report content - stores snapshot of a task at time of export
struct ArchivedTask: Codable, Identifiable {
    var id: UUID
    var title: String
    var description: String
    var priority: String
    var status: String
    var dueDate: Date?
    var wellName: String?
    var padName: String?
}

/// Archived handover note content - stores snapshot of a note at time of export
struct ArchivedNote: Codable, Identifiable {
    var id: UUID
    var title: String
    var content: String
    var category: String
    var author: String
    var createdAt: Date
    var wellName: String?
    var padName: String?
}

@Model
final class HandoverReportArchive {
    var id: UUID = UUID()
    var exportDate: Date = Date.now
    var reportTitle: String = ""

    // Date range covered by the report
    var startDate: Date = Date.now
    var endDate: Date = Date.now

    // Wells/Pads included (stored as JSON-encoded Data to avoid CloudKit array issues)
    var wellNamesData: Data?
    var padNamesData: Data?

    // Archived content (stored as JSON)
    var tasksData: Data?
    var notesData: Data?

    // Optional: store the PDF data for direct viewing
    var pdfData: Data?

    // Summary stats
    var taskCount: Int = 0
    var noteCount: Int = 0

    init(reportTitle: String = "",
         startDate: Date = Date.now,
         endDate: Date = Date.now,
         wellNames: [String] = [],
         padNames: [String] = []) {
        self.reportTitle = reportTitle
        self.startDate = startDate
        self.endDate = endDate
        self.wellNames = wellNames
        self.padNames = padNames
    }

    // MARK: - Computed Accessors for Arrays

    var wellNames: [String] {
        get {
            guard let data = wellNamesData else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            wellNamesData = try? JSONEncoder().encode(newValue)
        }
    }

    var padNames: [String] {
        get {
            guard let data = padNamesData else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            padNamesData = try? JSONEncoder().encode(newValue)
        }
    }

    // MARK: - Computed Properties

    var archivedTasks: [ArchivedTask] {
        get {
            guard let data = tasksData else { return [] }
            return (try? JSONDecoder().decode([ArchivedTask].self, from: data)) ?? []
        }
        set {
            tasksData = try? JSONEncoder().encode(newValue)
            taskCount = newValue.count
        }
    }

    var archivedNotes: [ArchivedNote] {
        get {
            guard let data = notesData else { return [] }
            return (try? JSONDecoder().decode([ArchivedNote].self, from: data)) ?? []
        }
        set {
            notesData = try? JSONEncoder().encode(newValue)
            noteCount = newValue.count
        }
    }

    var dateRangeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        return "\(formatter.string(from: startDate)) – \(formatter.string(from: endDate))"
    }

    var exportDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy 'at' HH:mm"
        return formatter.string(from: exportDate)
    }

    // MARK: - Factory Methods

    /// Create an archived task from a WellTask
    static func archiveTask(_ task: WellTask) -> ArchivedTask {
        ArchivedTask(
            id: task.id,
            title: task.title,
            description: task.taskDescription,
            priority: task.priority.rawValue,
            status: task.status.rawValue,
            dueDate: task.dueDate,
            wellName: task.well?.name,
            padName: task.pad?.name
        )
    }

    /// Create an archived note from a HandoverNote
    static func archiveNote(_ note: HandoverNote) -> ArchivedNote {
        ArchivedNote(
            id: note.id,
            title: note.title,
            content: note.content,
            category: note.category.rawValue,
            author: note.author,
            createdAt: note.createdAt,
            wellName: note.well?.name,
            padName: note.pad?.name
        )
    }
}
