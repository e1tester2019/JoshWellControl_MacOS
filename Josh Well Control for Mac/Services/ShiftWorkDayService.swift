//
//  ShiftWorkDayService.swift
//  Josh Well Control for Mac
//
//  Service for auto-syncing ShiftEntry ↔ WorkDay relationships.
//

import Foundation
import SwiftData

enum ShiftWorkDayService {

    // MARK: - Ensure WorkDay Sync

    /// Ensures a WorkDay exists (or is removed) based on shift state.
    /// - If shift is Day/Night and client is set: creates or updates linked WorkDay.
    /// - If shift is Off or client is nil: deletes WorkDay (unless invoiced — returns warning).
    /// - Returns a warning message if an invoiced WorkDay would be affected.
    @discardableResult
    static func ensureWorkDay(
        for shiftEntry: ShiftEntry,
        client: Client?,
        well: Well?,
        mileageToLocation: Double = 0,
        mileageFromLocation: Double = 0,
        mileageInField: Double = 0,
        mileageCommute: Double = 0,
        notes: String = "",
        context: ModelContext
    ) -> String? {
        let dayStart = Calendar.current.startOfDay(for: shiftEntry.date)

        if shiftEntry.isWorkingShift && client != nil {
            // Need a WorkDay — create or update
            let workDay: WorkDay
            if let existing = shiftEntry.workDay {
                workDay = existing
            } else {
                workDay = WorkDay(startDate: dayStart, endDate: dayStart)
                context.insert(workDay)
                shiftEntry.workDay = workDay
            }

            workDay.startDate = dayStart
            workDay.endDate = dayStart
            workDay.client = client
            workDay.well = well
            workDay.mileageToLocation = mileageToLocation
            workDay.mileageFromLocation = mileageFromLocation
            workDay.mileageInField = mileageInField
            workDay.mileageCommute = mileageCommute
            workDay.notes = notes

            return nil

        } else if let existingWorkDay = shiftEntry.workDay {
            // Shift is off or no client — remove WorkDay if not invoiced
            if existingWorkDay.isInvoiced {
                return "This shift has an invoiced WorkDay that cannot be auto-deleted."
            }
            context.delete(existingWorkDay)
            shiftEntry.workDay = nil
            return nil
        }

        return nil
    }

    // MARK: - Orphan Migration

    /// One-time migration: finds ShiftEntries where isWorkingShift == true
    /// AND workDay == nil AND client != nil, then creates WorkDays for them.
    @MainActor
    static func migrateOrphanShifts(context: ModelContext) {
        let migrationKey = "hasRunShiftWorkDayMigration_v1"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        do {
            let descriptor = FetchDescriptor<ShiftEntry>(sortBy: [SortDescriptor(\ShiftEntry.date)])
            let allShifts = try context.fetch(descriptor)

            var createdCount = 0
            for entry in allShifts {
                guard entry.isWorkingShift,
                      entry.workDay == nil,
                      entry.client != nil else { continue }

                let dayStart = Calendar.current.startOfDay(for: entry.date)
                let workDay = WorkDay(startDate: dayStart, endDate: dayStart)
                workDay.client = entry.client
                workDay.well = entry.well
                context.insert(workDay)
                entry.workDay = workDay
                createdCount += 1
            }

            if createdCount > 0 {
                try context.save()
                print("📋 ShiftWorkDay migration: created \(createdCount) WorkDays for orphan shifts")
            }

            UserDefaults.standard.set(true, forKey: migrationKey)
        } catch {
            print("⚠️ ShiftWorkDay orphan migration failed: \(error)")
        }
    }

    // MARK: - Bulk Create

    /// Creates ShiftEntry + WorkDay together for working shifts during bulk generation.
    /// Only creates WorkDay if a client is provided.
    static func bulkCreateShiftsWithWorkDays(
        settings: ShiftRotationSettings,
        days: Int,
        client: Client?,
        well: Well?,
        context: ModelContext
    ) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Fetch existing entries to avoid duplicates
        let descriptor = FetchDescriptor<ShiftEntry>(sortBy: [SortDescriptor(\ShiftEntry.date)])
        let existingEntries = (try? context.fetch(descriptor)) ?? []
        let existingDates = Set(existingEntries.map { calendar.startOfDay(for: $0.date) })

        for dayOffset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: today) else {
                continue
            }

            let dayStart = calendar.startOfDay(for: date)

            // Skip if entry already exists
            if existingDates.contains(dayStart) {
                continue
            }

            let expectedType = settings.expectedShiftType(for: date)
            let entry = ShiftEntry(date: dayStart, shiftType: expectedType)
            context.insert(entry)

            // Create WorkDay for working shifts with a client
            if expectedType != .off, let client = client {
                let workDay = WorkDay(startDate: dayStart, endDate: dayStart)
                workDay.client = client
                workDay.well = well
                context.insert(workDay)
                entry.workDay = workDay
            }
        }
    }
}
