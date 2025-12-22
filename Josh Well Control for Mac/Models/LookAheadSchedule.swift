//
//  LookAheadSchedule.swift
//  Josh Well Control for Mac
//
//  Container for a sequence of linked look ahead tasks.
//

import Foundation
import SwiftData

@Model
final class LookAheadSchedule {
    var id: UUID = UUID()
    var name: String = "New Schedule"
    var startDate: Date = Date.now
    var notes: String = ""
    var isActive: Bool = true

    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    // Relationships
    @Relationship(deleteRule: .nullify) var pad: Pad?
    @Relationship(deleteRule: .nullify) var well: Well?
    @Relationship(deleteRule: .cascade, inverse: \LookAheadTask.schedule) var tasks: [LookAheadTask]?

    init(name: String = "New Schedule", startDate: Date = Date.now) {
        self.name = name
        self.startDate = startDate
    }

    // MARK: - Computed Properties

    /// Tasks sorted by sequence order
    var sortedTasks: [LookAheadTask] {
        (tasks ?? []).sorted { $0.sequenceOrder < $1.sequenceOrder }
    }

    /// Calculated end date from last task
    var calculatedEndDate: Date {
        sortedTasks.last?.endTime ?? startDate
    }

    /// Total scheduled duration in seconds
    var totalDuration: TimeInterval {
        calculatedEndDate.timeIntervalSince(startDate)
    }

    /// Total duration in hours
    var totalDurationHours: Double {
        totalDuration / 3600
    }

    /// Formatted total duration
    var totalDurationFormatted: String {
        let hours = Int(totalDuration) / 3600
        let days = hours / 24
        let remainingHours = hours % 24

        if days > 0 {
            return "\(days)d \(remainingHours)h"
        }
        return "\(hours)h"
    }

    // MARK: - Task Counts

    var taskCount: Int {
        tasks?.count ?? 0
    }

    var completedTaskCount: Int {
        (tasks ?? []).filter { $0.status == .completed }.count
    }

    var pendingTaskCount: Int {
        (tasks ?? []).filter { $0.status == .scheduled }.count
    }

    var inProgressTaskCount: Int {
        (tasks ?? []).filter { $0.status == .inProgress }.count
    }

    var delayedTaskCount: Int {
        (tasks ?? []).filter { $0.status == .delayed }.count
    }

    /// Progress percentage (0.0 to 1.0)
    var progressPercentage: Double {
        guard taskCount > 0 else { return 0 }
        return Double(completedTaskCount) / Double(taskCount)
    }

    // MARK: - Call Status

    /// Tasks that need calls
    var tasksNeedingCalls: [LookAheadTask] {
        sortedTasks.filter { !$0.assignedVendors.isEmpty && !$0.hasConfirmedCall && $0.isActive }
    }

    /// Tasks with overdue calls
    var tasksWithOverdueCalls: [LookAheadTask] {
        sortedTasks.filter { $0.isCallOverdue }
    }

    /// Tasks with confirmed vendor calls
    var tasksWithConfirmedCalls: [LookAheadTask] {
        sortedTasks.filter { $0.hasConfirmedCall }
    }

    // MARK: - Analytics

    /// Tasks that have actual duration recorded
    var completedTasksWithActual: [LookAheadTask] {
        sortedTasks.filter { $0.actualDuration_min != nil }
    }

    /// Total estimated duration in minutes
    var totalEstimatedDuration_min: Double {
        sortedTasks.reduce(0) { $0 + $1.estimatedDuration_min }
    }

    /// Total actual duration in minutes (for completed tasks)
    var totalActualDuration_min: Double {
        completedTasksWithActual.reduce(0) { $0 + ($1.actualDuration_min ?? 0) }
    }

    /// Average variance percentage across completed tasks
    var averageVariancePercentage: Double? {
        let tasksWithVariance = completedTasksWithActual.compactMap { $0.variancePercentage }
        guard !tasksWithVariance.isEmpty else { return nil }
        return tasksWithVariance.reduce(0, +) / Double(tasksWithVariance.count)
    }

    // MARK: - Date Range Helpers

    var dateRangeFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"

        let start = formatter.string(from: startDate)
        let end = formatter.string(from: calculatedEndDate)

        if Calendar.current.isDate(startDate, inSameDayAs: calculatedEndDate) {
            return start
        }
        return "\(start) - \(end)"
    }

    /// Get tasks for a specific date
    func tasks(for date: Date) -> [LookAheadTask] {
        let calendar = Calendar.current
        return sortedTasks.filter { task in
            calendar.isDate(task.startTime, inSameDayAs: date)
        }
    }

    /// Get all unique dates that have tasks
    var taskDates: [Date] {
        let calendar = Calendar.current
        var dates: Set<Date> = []
        for task in sortedTasks {
            let startOfDay = calendar.startOfDay(for: task.startTime)
            dates.insert(startOfDay)
        }
        return dates.sorted()
    }

    // MARK: - Next Task Helpers

    /// Next task that hasn't started yet
    var nextPendingTask: LookAheadTask? {
        sortedTasks.first { $0.status == .scheduled && $0.startTime > Date.now }
    }

    /// Currently active task (in progress or should be starting)
    var currentTask: LookAheadTask? {
        // First check for explicitly in-progress
        if let inProgress = sortedTasks.first(where: { $0.status == .inProgress }) {
            return inProgress
        }
        // Then check for task that should be active now
        let now = Date.now
        return sortedTasks.first { task in
            task.status == .scheduled && task.startTime <= now && task.endTime > now
        }
    }
}
