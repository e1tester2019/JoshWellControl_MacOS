//
//  TaskVendorAssignment.swift
//  Josh Well Control for Mac
//
//  Links a vendor to a task with individual call reminder settings.
//

import Foundation
import SwiftData

@Model
final class TaskVendorAssignment {
    var id: UUID = UUID()

    /// Minutes before task start to remind for this vendor
    var callReminderMinutesBefore: Int = 60

    /// Whether this vendor has been confirmed
    var isConfirmed: Bool = false

    /// Notes specific to this vendor for this task
    var notes: String = ""

    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    // Relationships
    @Relationship(deleteRule: .nullify) var task: LookAheadTask?
    @Relationship(deleteRule: .nullify) var vendor: Vendor?

    init(vendor: Vendor, callReminderMinutesBefore: Int = 60) {
        self.vendor = vendor
        self.callReminderMinutesBefore = callReminderMinutesBefore
    }

    // MARK: - Computed Properties

    /// Reminder time for this specific vendor
    var reminderTime: Date? {
        guard let task = task else { return nil }
        return task.startTime.addingTimeInterval(-Double(callReminderMinutesBefore * 60))
    }

    /// Whether reminder is overdue
    var isReminderOverdue: Bool {
        guard let time = reminderTime else { return false }
        return time < Date.now && !isConfirmed
    }

    /// Formatted reminder time
    var reminderTimeFormatted: String {
        switch callReminderMinutesBefore {
        case 30: return "30 min before"
        case 60: return "1 hour before"
        case 120: return "2 hours before"
        case 240: return "4 hours before"
        case 1440: return "1 day before"
        default:
            let hours = callReminderMinutesBefore / 60
            let mins = callReminderMinutesBefore % 60
            if hours > 0 && mins > 0 {
                return "\(hours)h \(mins)m before"
            } else if hours > 0 {
                return "\(hours)h before"
            } else {
                return "\(mins)m before"
            }
        }
    }
}
