//
//  WellTask.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-12-09.
//

import Foundation
import SwiftData

enum TaskPriority: String, Codable, CaseIterable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case critical = "Critical"

    var sortOrder: Int {
        switch self {
        case .critical: return 0
        case .high: return 1
        case .medium: return 2
        case .low: return 3
        }
    }
}

enum TaskStatus: String, Codable, CaseIterable {
    case pending = "Pending"
    case inProgress = "In Progress"
    case completed = "Completed"
    case cancelled = "Cancelled"
}

@Model
final class WellTask {
    var id: UUID = UUID()
    var title: String = ""
    var taskDescription: String = ""
    var priorityRaw: String = TaskPriority.medium.rawValue
    var statusRaw: String = TaskStatus.pending.rawValue
    var createdAt: Date = Date.now
    var dueDate: Date? = nil
    var completedAt: Date? = nil
    var author: String = ""

    @Relationship var well: Well?
    @Relationship var pad: Pad?  // Can be assigned to pad instead of well
    @Relationship var project: ProjectState?  // Optional: can be tied to specific project

    init(title: String = "",
         description: String = "",
         priority: TaskPriority = .medium,
         status: TaskStatus = .pending,
         dueDate: Date? = nil,
         author: String = "") {
        self.title = title
        self.taskDescription = description
        self.priorityRaw = priority.rawValue
        self.statusRaw = status.rawValue
        self.dueDate = dueDate
        self.author = author
    }

    var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .medium }
        set { priorityRaw = newValue.rawValue }
    }

    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .pending }
        set {
            statusRaw = newValue.rawValue
            if newValue == .completed {
                completedAt = Date.now
            }
        }
    }

    var isOverdue: Bool {
        guard let due = dueDate, status != .completed && status != .cancelled else { return false }
        return due < Date.now
    }

    var isPending: Bool {
        status == .pending || status == .inProgress
    }
}
