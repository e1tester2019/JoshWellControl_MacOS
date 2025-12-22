//
//  LookAheadViewModel.swift
//  Josh Well Control for Mac
//
//  ViewModel for managing look ahead schedules with linked timeline cascading.
//

import Foundation
import SwiftUI
import SwiftData
import Observation

@Observable
class LookAheadViewModel {
    var schedule: LookAheadSchedule?

    // Current editing state
    var selectedTask: LookAheadTask?
    var isEditing: Bool = false

    // Filter state
    var filterStatus: LookAheadTaskStatus?
    var showCompletedTasks: Bool = true
    var searchText: String = ""

    // Analytics cache (recalculated on changes)
    var totalEstimatedDuration: TimeInterval = 0
    var tasksRequiringCalls: [LookAheadTask] = []
    var overdueTasks: [LookAheadTask] = []

    // MARK: - Filtered Tasks

    var filteredTasks: [LookAheadTask] {
        guard let schedule = schedule else { return [] }
        var tasks = schedule.sortedTasks

        // Filter by status
        if let status = filterStatus {
            tasks = tasks.filter { $0.status == status }
        }

        // Hide completed if toggle is off
        if !showCompletedTasks {
            tasks = tasks.filter { $0.status != .completed && $0.status != .cancelled }
        }

        // Search filter
        if !searchText.isEmpty {
            let search = searchText.lowercased()
            tasks = tasks.filter { task in
                task.name.lowercased().contains(search) ||
                task.jobCode?.name.lowercased().contains(search) == true ||
                task.assignedVendors.contains { $0.companyName.lowercased().contains(search) } ||
                task.well?.name.lowercased().contains(search) == true
            }
        }

        return tasks
    }

    // MARK: - Task Insertion

    /// Insert a new task at a specific position, cascade subsequent times
    func insertTask(at position: Int, task: LookAheadTask, context: ModelContext) {
        guard let schedule = schedule else { return }

        // 1. Shift sequence orders for all tasks at or after position
        for existingTask in schedule.sortedTasks where existingTask.sequenceOrder >= position {
            existingTask.sequenceOrder += 1
        }

        // 2. Set the new task's sequence order
        task.sequenceOrder = position
        task.schedule = schedule

        // 3. Calculate start time from previous task (or schedule start)
        if position == 0 {
            task.startTime = schedule.startDate
        } else if let previousTask = schedule.sortedTasks.first(where: { $0.sequenceOrder == position - 1 }) {
            task.startTime = previousTask.endTime
        }

        // 4. Insert into schedule
        if schedule.tasks == nil { schedule.tasks = [] }
        schedule.tasks?.append(task)
        context.insert(task)

        // 5. Cascade times for all subsequent tasks
        cascadeTimesFromPosition(position + 1, context: context)

        schedule.updatedAt = .now
        try? context.save()

        calculateAnalytics()
    }

    /// Insert a task at the end of the schedule
    func appendTask(_ task: LookAheadTask, context: ModelContext) {
        guard let schedule = schedule else { return }
        let position = schedule.taskCount
        insertTask(at: position, task: task, context: context)
    }

    // MARK: - Task Deletion

    /// Delete a task and cascade subsequent times backward
    func deleteTask(_ task: LookAheadTask, context: ModelContext) {
        guard let schedule = schedule else { return }
        let deletedPosition = task.sequenceOrder

        // 1. Remove the task from schedule
        schedule.tasks?.removeAll { $0.id == task.id }
        context.delete(task)

        // 2. Shift sequence orders down
        for existingTask in (schedule.tasks ?? []) where existingTask.sequenceOrder > deletedPosition {
            existingTask.sequenceOrder -= 1
        }

        // 3. Cascade times from deleted position
        cascadeTimesFromPosition(deletedPosition, context: context)

        schedule.updatedAt = .now
        try? context.save()

        calculateAnalytics()
    }

    /// Delete multiple tasks by their offsets
    func deleteTasks(at offsets: IndexSet, context: ModelContext) {
        guard let schedule = schedule else { return }
        let sorted = schedule.sortedTasks
        for index in offsets.sorted().reversed() {
            guard index < sorted.count else { continue }
            deleteTask(sorted[index], context: context)
        }
    }

    // MARK: - Duration Updates

    /// Update duration of a task and cascade all subsequent times
    func updateDuration(_ task: LookAheadTask, newDuration: Double, context: ModelContext) {
        task.estimatedDuration_min = newDuration
        task.updatedAt = .now

        // Cascade from the next task
        cascadeTimesFromPosition(task.sequenceOrder + 1, context: context)

        schedule?.updatedAt = .now
        try? context.save()

        calculateAnalytics()
    }

    /// Recalculate a task's duration when meterage changes
    func recalculateDurationForMeterage(_ task: LookAheadTask, context: ModelContext) {
        guard task.isMetarageBased, let jobCode = task.jobCode else { return }

        let newDuration = jobCode.estimateDuration(forMeters: task.meterage_m)
        updateDuration(task, newDuration: newDuration, context: context)
    }

    // MARK: - Task Reordering

    /// Move a task to a new position
    func moveTask(_ task: LookAheadTask, to newPosition: Int, context: ModelContext) {
        guard let schedule = schedule else { return }
        let oldPosition = task.sequenceOrder

        guard newPosition != oldPosition else { return }
        guard newPosition >= 0 && newPosition <= schedule.taskCount else { return }

        // 1. Remove from old position (shift others up)
        for t in (schedule.tasks ?? []) where t.sequenceOrder > oldPosition && t.id != task.id {
            t.sequenceOrder -= 1
        }

        // 2. Adjust target position if moving down
        let adjustedNewPosition = newPosition > oldPosition ? newPosition - 1 : newPosition

        // 3. Make room at new position (shift others down)
        for t in (schedule.tasks ?? []) where t.sequenceOrder >= adjustedNewPosition && t.id != task.id {
            t.sequenceOrder += 1
        }

        // 4. Set new position
        task.sequenceOrder = adjustedNewPosition

        // 5. Recalculate all times from the earliest affected position
        let startPosition = min(oldPosition, adjustedNewPosition)
        cascadeTimesFromPosition(startPosition, context: context)

        schedule.updatedAt = .now
        try? context.save()

        calculateAnalytics()
    }

    /// Move tasks from source offsets to destination (for drag & drop)
    func moveTasks(from source: IndexSet, to destination: Int, context: ModelContext) {
        guard let schedule = schedule, let sourceIndex = source.first else { return }
        let task = schedule.sortedTasks[sourceIndex]
        moveTask(task, to: destination, context: context)
    }

    // MARK: - Timeline Cascading

    /// Core cascading algorithm - recalculate start times from a position onward
    private func cascadeTimesFromPosition(_ position: Int, context: ModelContext) {
        guard let schedule = schedule else { return }
        let sorted = schedule.sortedTasks

        for i in position..<sorted.count {
            let task = sorted[i]
            if i == 0 {
                task.startTime = schedule.startDate
            } else {
                let previousTask = sorted[i - 1]
                task.startTime = previousTask.endTime
            }
        }
    }

    /// Shift all tasks from a date by a certain amount
    func shiftTasksFromDate(_ date: Date, by minutes: Double, context: ModelContext) {
        guard let schedule = schedule else { return }

        for task in schedule.sortedTasks where task.startTime >= date {
            task.startTime = task.startTime.addingTimeInterval(minutes * 60)
        }

        schedule.updatedAt = .now
        try? context.save()

        calculateAnalytics()
    }

    /// Update schedule start date and cascade all tasks
    func updateScheduleStartDate(_ newDate: Date, context: ModelContext) {
        guard let schedule = schedule else { return }
        schedule.startDate = newDate
        cascadeTimesFromPosition(0, context: context)
        schedule.updatedAt = .now
        try? context.save()

        calculateAnalytics()
    }

    /// Recalculate all task times from the schedule start - fixes any timing issues
    func recalculateAllTimes(context: ModelContext) {
        guard let schedule = schedule else { return }
        cascadeTimesFromPosition(0, context: context)
        schedule.updatedAt = .now
        try? context.save()

        calculateAnalytics()
    }

    // MARK: - Task Completion

    /// Mark task as completed and record actual duration
    func completeTask(_ task: LookAheadTask, actualDuration: Double, context: ModelContext) {
        task.status = .completed
        task.actualDuration_min = actualDuration
        task.completedAt = .now

        // Update job code averages for learning
        if let jobCode = task.jobCode {
            jobCode.recordCompletion(duration_min: actualDuration, meterage_m: task.meterage_m)
        }

        schedule?.updatedAt = .now
        try? context.save()

        calculateAnalytics()
    }

    /// Start a task (mark as in progress)
    func startTask(_ task: LookAheadTask, context: ModelContext) {
        task.status = .inProgress
        task.startedAt = .now
        schedule?.updatedAt = .now
        try? context.save()

        calculateAnalytics()
    }

    /// Mark a task as delayed
    func delayTask(_ task: LookAheadTask, context: ModelContext) {
        task.status = .delayed
        schedule?.updatedAt = .now
        try? context.save()

        calculateAnalytics()
    }

    // MARK: - Duration Estimation

    /// Calculate estimated duration based on job code and optional meterage
    func estimateDuration(for jobCode: JobCode?, meters: Double?) -> Double {
        guard let jc = jobCode else { return 60 } // Default 1 hour
        return jc.estimateDuration(forMeters: meters)
    }

    // MARK: - Analytics

    func calculateAnalytics() {
        guard let schedule = schedule else {
            totalEstimatedDuration = 0
            tasksRequiringCalls = []
            overdueTasks = []
            return
        }

        totalEstimatedDuration = schedule.sortedTasks.reduce(0) { $0 + $1.estimatedDuration_min * 60 }

        tasksRequiringCalls = schedule.sortedTasks.filter {
            !$0.assignedVendors.isEmpty && $0.needsCallReminder
        }

        overdueTasks = schedule.sortedTasks.filter {
            $0.status == .scheduled && $0.startTime < Date.now
        }
    }

    /// Accuracy metrics for completed tasks
    var accuracyMetrics: (avgVariance: Double?, totalTasks: Int, accurateCount: Int) {
        guard let schedule = schedule else { return (nil, 0, 0) }

        let completedWithActual = schedule.completedTasksWithActual
        guard !completedWithActual.isEmpty else { return (nil, 0, 0) }

        let variances = completedWithActual.compactMap { $0.variancePercentage }
        let avgVariance = variances.isEmpty ? nil : variances.reduce(0, +) / Double(variances.count)

        // Consider "accurate" if within 10% of estimate
        let accurateCount = completedWithActual.filter { task in
            guard let variance = task.variancePercentage else { return false }
            return abs(variance) <= 10
        }.count

        return (avgVariance, completedWithActual.count, accurateCount)
    }

    // MARK: - Schedule Management

    /// Create a new schedule
    func createSchedule(name: String, startDate: Date, context: ModelContext) -> LookAheadSchedule {
        // Deactivate other schedules
        let descriptor = FetchDescriptor<LookAheadSchedule>()
        if let existing = try? context.fetch(descriptor) {
            for s in existing { s.isActive = false }
        }

        let newSchedule = LookAheadSchedule(name: name, startDate: startDate)
        context.insert(newSchedule)
        try? context.save()

        self.schedule = newSchedule
        calculateAnalytics()

        return newSchedule
    }

    /// Switch to a different schedule
    func switchToSchedule(_ newSchedule: LookAheadSchedule) {
        self.schedule = newSchedule
        self.selectedTask = nil
        calculateAnalytics()
    }

    /// Duplicate current schedule
    func duplicateSchedule(context: ModelContext) -> LookAheadSchedule? {
        guard let source = schedule else { return nil }

        let copy = LookAheadSchedule(
            name: "\(source.name) (Copy)",
            startDate: source.startDate
        )
        copy.notes = source.notes
        copy.pad = source.pad
        copy.well = source.well
        copy.isActive = true

        // Deactivate source
        source.isActive = false

        context.insert(copy)

        // Copy tasks
        var newTasks: [LookAheadTask] = []
        for task in source.sortedTasks {
            let newTask = LookAheadTask(
                name: task.name,
                estimatedDuration_min: task.estimatedDuration_min,
                sequenceOrder: task.sequenceOrder
            )
            newTask.notes = task.notes
            newTask.startTime = task.startTime
            newTask.startDepth_m = task.startDepth_m
            newTask.endDepth_m = task.endDepth_m
            newTask.isMetarageBased = task.isMetarageBased
            newTask.callReminderMinutesBefore = task.callReminderMinutesBefore
            newTask.vendorComments = task.vendorComments
            newTask.finalCallDescription = task.finalCallDescription
            newTask.jobCode = task.jobCode
            newTask.well = task.well
            newTask.pad = task.pad
            newTask.schedule = copy

            context.insert(newTask)

            // Copy vendor assignments
            for assignment in task.assignments {
                guard let vendor = assignment.vendor else { continue }
                let newAssignment = TaskVendorAssignment(
                    vendor: vendor,
                    callReminderMinutesBefore: assignment.callReminderMinutesBefore
                )
                newAssignment.notes = assignment.notes
                newAssignment.task = newTask
                context.insert(newAssignment)
            }

            newTasks.append(newTask)
        }

        copy.tasks = newTasks
        try? context.save()

        self.schedule = copy
        calculateAnalytics()

        return copy
    }
}
