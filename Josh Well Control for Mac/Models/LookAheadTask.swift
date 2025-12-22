//
//  LookAheadTask.swift
//  Josh Well Control for Mac
//
//  Individual task in a look ahead schedule with linked timing.
//

import Foundation
import SwiftData

enum LookAheadTaskStatus: String, Codable, CaseIterable {
    case scheduled = "Scheduled"
    case inProgress = "In Progress"
    case completed = "Completed"
    case delayed = "Delayed"
    case cancelled = "Cancelled"

    var icon: String {
        switch self {
        case .scheduled: return "clock"
        case .inProgress: return "play.fill"
        case .completed: return "checkmark.circle.fill"
        case .delayed: return "exclamationmark.triangle"
        case .cancelled: return "xmark.circle"
        }
    }

    var color: String {
        switch self {
        case .scheduled: return "blue"
        case .inProgress: return "orange"
        case .completed: return "green"
        case .delayed: return "red"
        case .cancelled: return "gray"
        }
    }

    var sortOrder: Int {
        switch self {
        case .inProgress: return 0
        case .delayed: return 1
        case .scheduled: return 2
        case .completed: return 3
        case .cancelled: return 4
        }
    }
}

@Model
final class LookAheadTask {
    var id: UUID = UUID()
    var sequenceOrder: Int = 0
    var name: String = ""
    var notes: String = ""

    // Timing
    var startTime: Date = Date.now
    var estimatedDuration_min: Double = 60
    var actualDuration_min: Double?

    // Meterage-based estimation (start/end depth)
    var startDepth_m: Double?
    var endDepth_m: Double?
    var isMetarageBased: Bool = false

    /// Calculated meterage from start to end depth
    var meterage_m: Double? {
        guard let start = startDepth_m, let end = endDepth_m else { return nil }
        return max(0, end - start)
    }

    // Status
    var statusRaw: String = LookAheadTaskStatus.scheduled.rawValue
    var completedAt: Date?
    var startedAt: Date?

    // Call scheduling
    var firstCallTime: Date?
    var callReminderMinutesBefore: Int = 60
    var notificationScheduled: Bool = false

    // Comments from Excel (for migration/display)
    var vendorComments: String = ""
    var finalCallDescription: String = ""

    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    // Relationships
    @Relationship(deleteRule: .nullify) var schedule: LookAheadSchedule?
    @Relationship(deleteRule: .nullify) var jobCode: JobCode?
    @Relationship(deleteRule: .cascade, inverse: \TaskVendorAssignment.task) var vendorAssignments: [TaskVendorAssignment]?
    @Relationship(deleteRule: .nullify) var well: Well?
    @Relationship(deleteRule: .nullify) var pad: Pad?
    @Relationship(deleteRule: .cascade, inverse: \CallLogEntry.task) var callLog: [CallLogEntry]?

    /// All vendor assignments
    var assignments: [TaskVendorAssignment] {
        vendorAssignments ?? []
    }

    /// Convenience for single vendor access (first vendor)
    var primaryVendor: Vendor? {
        assignments.first?.vendor
    }

    /// All assigned vendors
    var assignedVendors: [Vendor] {
        assignments.compactMap { $0.vendor }
    }

    /// Vendors array for backward compatibility (sets with default reminder)
    var vendors: [Vendor]? {
        get { assignedVendors }
        set {
            // This is handled through vendorAssignments now
            // Setting directly is deprecated - use addVendor/removeVendor
        }
    }

    init(name: String = "",
         estimatedDuration_min: Double = 60,
         sequenceOrder: Int = 0) {
        self.name = name
        self.estimatedDuration_min = estimatedDuration_min
        self.sequenceOrder = sequenceOrder
    }

    // MARK: - Computed Properties

    var status: LookAheadTaskStatus {
        get { LookAheadTaskStatus(rawValue: statusRaw) ?? .scheduled }
        set {
            statusRaw = newValue.rawValue
            updatedAt = .now
            if newValue == .completed {
                completedAt = Date.now
            } else if newValue == .inProgress && startedAt == nil {
                startedAt = Date.now
            }
        }
    }

    var endTime: Date {
        startTime.addingTimeInterval(estimatedDuration_min * 60)
    }

    var actualEndTime: Date? {
        guard let actual = actualDuration_min else { return nil }
        return startTime.addingTimeInterval(actual * 60)
    }

    // MARK: - Duration Calculations

    var durationVariance_min: Double? {
        guard let actual = actualDuration_min else { return nil }
        return actual - estimatedDuration_min
    }

    var variancePercentage: Double? {
        guard let variance = durationVariance_min, estimatedDuration_min > 0 else { return nil }
        return (variance / estimatedDuration_min) * 100
    }

    var estimatedDurationFormatted: String {
        formatDuration(estimatedDuration_min)
    }

    var actualDurationFormatted: String? {
        guard let actual = actualDuration_min else { return nil }
        return formatDuration(actual)
    }

    private func formatDuration(_ minutes: Double) -> String {
        let hours = Int(minutes) / 60
        let mins = Int(minutes) % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }

    // MARK: - Call Reminders

    /// Earliest reminder time across all vendor assignments
    var reminderTime: Date {
        let times = assignments.compactMap { $0.reminderTime }
        return times.min() ?? startTime.addingTimeInterval(-Double(callReminderMinutesBefore * 60))
    }

    var timeUntilCallReminder: TimeInterval {
        reminderTime.timeIntervalSinceNow
    }

    var needsCallReminder: Bool {
        !assignments.isEmpty && status == .scheduled && timeUntilCallReminder > 0 && timeUntilCallReminder < 3600
    }

    var isCallOverdue: Bool {
        assignments.contains { $0.isReminderOverdue } && status == .scheduled
    }

    /// Assignments that haven't been confirmed yet
    var pendingAssignments: [TaskVendorAssignment] {
        assignments.filter { !$0.isConfirmed }
    }

    /// Vendors that haven't been confirmed yet
    var vendorsPendingCall: [Vendor] {
        pendingAssignments.compactMap { $0.vendor }
    }

    /// Check if all vendors have been confirmed
    var allVendorsConfirmed: Bool {
        pendingAssignments.isEmpty && !assignments.isEmpty
    }

    var hasConfirmedCall: Bool {
        assignments.contains { $0.isConfirmed }
    }

    var latestCall: CallLogEntry? {
        (callLog ?? []).sorted { $0.timestamp > $1.timestamp }.first
    }

    var callCount: Int {
        callLog?.count ?? 0
    }

    // MARK: - Status Helpers

    var isOverdue: Bool {
        status == .scheduled && startTime < Date.now
    }

    var isActive: Bool {
        status == .scheduled || status == .inProgress
    }

    var isPending: Bool {
        status == .scheduled
    }

    // MARK: - Display Helpers

    var timeRangeFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: startTime)) - \(formatter.string(from: endTime))"
    }

    var dateFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, d MMM"
        return formatter.string(from: startTime)
    }

    var wellOrPadName: String? {
        well?.name ?? pad?.name
    }

    /// Summary for list display
    var summaryLine: String {
        var parts: [String] = [timeRangeFormatted]
        if let location = wellOrPadName {
            parts.append(location)
        }
        if let jc = jobCode {
            parts.append(jc.code)
        }
        return parts.joined(separator: " | ")
    }
}
